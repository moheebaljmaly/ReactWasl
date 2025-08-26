-- ####################################################################
-- #                                                                  #
-- #          سكربت شامل ونهائي لبناء قاعدة بيانات "وصل" الآمنة           #
-- #                                                                  #
-- ####################################################################

-- الخطوة 1: حذف الكائنات القديمة بالترتيب الصحيح لتجنب أخطاء الاعتمادية
DROP POLICY IF EXISTS "Users can view conversations they are a member of." ON "public"."conversations";
DROP POLICY IF EXISTS "Users can insert their own messages" ON "public"."messages";
DROP POLICY IF EXISTS "Users can view messages in conversations they are members of" ON "public"."messages";
DROP POLICY IF EXISTS "Users can update their own profile" ON "public"."profiles";
DROP POLICY IF EXISTS "Users can view all profiles" ON "public"."profiles";
DROP POLICY IF EXISTS "Users can insert their own profile" ON "public"."profiles";
DROP POLICY IF EXISTS "Members can view other members of their conversations" ON "public"."conversation_members";
DROP POLICY IF EXISTS "Users can insert themselves into conversations" ON "public"."conversation_members";

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.create_private_conversation(other_user_id uuid);
DROP FUNCTION IF EXISTS public.get_user_conversations();
DROP FUNCTION IF EXISTS public.get_conversation_partner(p_conversation_id uuid);

DROP TABLE IF EXISTS public.message_status CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.conversation_members CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;


-- الخطوة 2: إنشاء الجداول من جديد
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  username TEXT UNIQUE,
  avatar_url TEXT,
  status TEXT DEFAULT 'مرحباً، أستخدم وصل!',
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE public.profiles IS 'Stores user profile information.';

CREATE TABLE public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE public.conversations IS 'Stores conversation metadata.';

CREATE TABLE public.conversation_members (
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);
COMMENT ON TABLE public.conversation_members IS 'Links users to conversations.';

CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE public.messages IS 'Stores chat messages for all conversations.';


-- الخطوة 3: إنشاء مخزن الصور (Storage Bucket)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', true, 5242880, ARRAY['image/jpeg', 'image/png'])
ON CONFLICT (id) DO NOTHING;

-- سياسة: السماح للمستخدمين المسجلين برفع الصور
CREATE POLICY "authenticated_user_can_upload" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'avatars');

-- سياسة: السماح للمستخدمين بتحديث صورهم الشخصية
CREATE POLICY "owner_can_update_avatar" ON storage.objects
FOR UPDATE TO authenticated
USING (auth.uid() = owner);

-- سياسة: السماح للجميع بقراءة الصور
CREATE POLICY "public_read_access" ON storage.objects
FOR SELECT
USING (bucket_id = 'avatars');


-- الخطوة 4: إنشاء الدوال والمشغلات الآمنة
-- دالة لإنشاء ملف شخصي جديد عند تسجيل مستخدم جديد
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, username, avatar_url)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'username',
    new.raw_user_meta_data->>'avatar_url'
  );
  RETURN new;
END;
$$;
COMMENT ON FUNCTION public.handle_new_user() IS 'Creates a new user profile upon registration.';

-- مشغل (Trigger) لاستدعاء الدالة أعلاه
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- دالة لبدء محادثة خاصة جديدة
CREATE OR REPLACE FUNCTION public.create_private_conversation(other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing_conversation_id UUID;
  new_conversation_id UUID;
BEGIN
  -- Check if a conversation already exists
  SELECT cm1.conversation_id INTO existing_conversation_id
  FROM conversation_members cm1
  JOIN conversation_members cm2 ON cm1.conversation_id = cm2.conversation_id
  WHERE cm1.user_id = auth.uid() AND cm2.user_id = other_user_id;

  IF existing_conversation_id IS NOT NULL THEN
    RETURN existing_conversation_id;
  END IF;

  -- Create a new conversation
  INSERT INTO conversations DEFAULT VALUES RETURNING id INTO new_conversation_id;

  -- Add both users to the conversation
  INSERT INTO conversation_members (conversation_id, user_id)
  VALUES (new_conversation_id, auth.uid()), (new_conversation_id, other_user_id);

  RETURN new_conversation_id;
END;
$$;
COMMENT ON FUNCTION public.create_private_conversation(uuid) IS 'Starts a new private conversation and returns its ID.';


-- دالة لجلب محادثات المستخدم مع آخر رسالة
CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE(
    conversation_id UUID,
    user_id UUID,
    username TEXT,
    full_name TEXT,
    avatar_url TEXT,
    last_message_content TEXT,
    last_message_created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    WITH ranked_messages AS (
        SELECT 
            m.conversation_id,
            m.content,
            m.created_at,
            ROW_NUMBER() OVER(PARTITION BY m.conversation_id ORDER BY m.created_at DESC) as rn
        FROM messages m
        JOIN conversation_members cm ON m.conversation_id = cm.conversation_id
        WHERE cm.user_id = auth.uid()
    )
    SELECT 
        c.id as conversation_id,
        p.id as user_id,
        p.username,
        p.full_name,
        p.avatar_url,
        lm.content as last_message_content,
        lm.created_at as last_message_created_at
    FROM conversations c
    JOIN conversation_members my_cm ON c.id = my_cm.conversation_id
    JOIN conversation_members partner_cm ON c.id = partner_cm.conversation_id AND my_cm.user_id != partner_cm.user_id
    JOIN profiles p ON partner_cm.user_id = p.id
    LEFT JOIN ranked_messages lm ON c.id = lm.conversation_id AND lm.rn = 1
    WHERE my_cm.user_id = auth.uid()
    ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;
COMMENT ON FUNCTION public.get_user_conversations() IS 'Fetches all conversations for the current user, including details of the conversation partner and the last message.';


-- دالة لجلب معلومات الطرف الآخر في المحادثة
CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id UUID)
RETURNS TABLE (
  id UUID,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM profiles p
  JOIN conversation_members cm ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id AND cm.user_id != auth.uid()
  LIMIT 1;
END;
$$;
COMMENT ON FUNCTION public.get_conversation_partner(uuid) IS 'Gets the profile of the other user in a private conversation.';


-- الخطوة 5: تفعيل RLS وتطبيق سياسات الأمان
-- تفعيل RLS على جميع الجداول
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- سياسات جدول profiles
CREATE POLICY "Users can view all profiles" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can insert their own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- سياسات جدول conversations
CREATE POLICY "Users can view conversations they are a member of." ON public.conversations FOR SELECT USING (id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid()));

-- سياسات جدول conversation_members
CREATE POLICY "Members can view other members of their conversations" ON public.conversation_members FOR SELECT USING (conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid()));

-- سياسات جدول messages
CREATE POLICY "Users can view messages in conversations they are members of" ON public.messages FOR SELECT USING (conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid()));
CREATE POLICY "Users can insert their own messages" ON public.messages FOR INSERT WITH CHECK (sender_id = auth.uid() AND conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid()));

-- Grant usage on schema to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT UPDATE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant usage for anon key as well for login
GRANT USAGE ON SCHEMA public TO anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;

-- ####################################################################
-- #                       اكتمل بناء قاعدة البيانات                     #
-- ####################################################################
