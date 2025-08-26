/*
          # [إعادة بناء شاملة لقاعدة البيانات]
          هذا السكربت يقوم بإعادة بناء كاملة لهيكل قاعدة البيانات لتطبيق "وصل".
          سيتم حذف جميع الجداول والوظائف والسياسات الحالية المتعلقة بالتطبيق وإعادة إنشائها بالترتيب الصحيح.

          ## تنبيه هام:
          - **فقدان البيانات**: سيؤدي تشغيل هذا السكربت إلى حذف جميع البيانات الموجودة في جداول التطبيق (المستخدمون، المحادثات، الرسائل).
          - **إجراء وقائي**: يوصى بشدة بأخذ نسخة احتياطية من قاعدة البيانات إذا كانت تحتوي على بيانات مهمة قبل المتابعة.

          ## Metadata:
          - Schema-Category: "Dangerous"
          - Impact-Level: "High"
          - Requires-Backup: true
          - Reversible: false (بدون استعادة النسخة الاحتياطية)
*/

-- الخطوة 1: حذف السياسات والمشغلات لتجنب أخطاء الاعتمادية
DROP POLICY IF EXISTS "Users can view their own profile." ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile." ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile." ON public.profiles;
DROP POLICY IF EXISTS "Users can view conversations they are a member of." ON public.conversations;
DROP POLICY IF EXISTS "Users can view members of conversations they are in." ON public.conversation_members;
DROP POLICY IF EXISTS "Users can insert members into conversations they are in." ON public.conversation_members;
DROP POLICY IF EXISTS "Users can send messages in conversations they are a member of." ON public.messages;
DROP POLICY IF EXISTS "Users can view messages in conversations they are a member of." ON public.messages;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- الخطوة 2: حذف الدوال
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_user_conversations();
DROP FUNCTION IF EXISTS public.create_private_conversation(uuid);
DROP FUNCTION IF EXISTS public.get_conversation_partner(uuid);

-- الخطوة 3: حذف الجداول بالترتيب العكسي للاعتمادية
DROP TABLE IF EXISTS public.message_status;
DROP TABLE IF EXISTS public.messages;
DROP TABLE IF EXISTS public.conversation_members;
DROP TABLE IF EXISTS public.conversations;
DROP TABLE IF EXISTS public.profiles;


-- الخطوة 4: إعادة إنشاء الجداول
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  full_name TEXT,
  username TEXT UNIQUE,
  avatar_url TEXT,
  status TEXT DEFAULT 'مرحباً، أستخدم وصل!',
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE public.profiles IS 'Stores user profile information.';

CREATE TABLE public.conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  type TEXT CHECK (type IN ('private', 'group')) DEFAULT 'private',
  name TEXT,
  description TEXT,
  avatar_url TEXT,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE public.conversations IS 'Stores conversation metadata.';

CREATE TABLE public.conversation_members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  role TEXT CHECK (role IN ('member', 'admin', 'owner')) DEFAULT 'member',
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(conversation_id, user_id)
);
COMMENT ON TABLE public.conversation_members IS 'Links users to conversations.';

CREATE TABLE public.messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT,
  message_type TEXT CHECK (message_type IN ('text', 'image', 'file', 'voice')) DEFAULT 'text',
  file_url TEXT,
  is_edited BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE public.messages IS 'Stores messages for each conversation.';

CREATE TABLE public.message_status (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  status TEXT CHECK (status IN ('sent', 'delivered', 'read')) DEFAULT 'sent',
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(message_id, user_id)
);
COMMENT ON TABLE public.message_status IS 'Tracks the status of each message for each recipient.';


-- الخطوة 5: إعادة إنشاء الدوال مع التحصين الأمني
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, username, avatar_url)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'username',
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_private_conversation(other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing_conversation_id UUID;
  new_conversation_id UUID;
  current_user_id UUID := auth.uid();
BEGIN
  -- ابحث عن محادثة خاصة حالية بين المستخدمين
  SELECT cm1.conversation_id INTO existing_conversation_id
  FROM conversation_members cm1
  JOIN conversation_members cm2 ON cm1.conversation_id = cm2.conversation_id
  JOIN conversations c ON cm1.conversation_id = c.id
  WHERE cm1.user_id = current_user_id
    AND cm2.user_id = other_user_id
    AND c.type = 'private';

  -- إذا وجدت محادثة، أرجع المعرف الخاص بها
  IF existing_conversation_id IS NOT NULL THEN
    RETURN existing_conversation_id;
  END IF;

  -- إذا لم توجد، أنشئ محادثة جديدة
  INSERT INTO conversations (type, created_by)
  VALUES ('private', current_user_id)
  RETURNING id INTO new_conversation_id;

  -- أضف كلا المستخدمين كأعضاء في المحادثة الجديدة
  INSERT INTO conversation_members (conversation_id, user_id)
  VALUES (new_conversation_id, current_user_id), (new_conversation_id, other_user_id);

  RETURN new_conversation_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id UUID)
RETURNS TABLE(user_id UUID, username TEXT, full_name TEXT, avatar_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM public.profiles p
  JOIN public.conversation_members cm ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id
    AND cm.user_id != auth.uid();
END;
$$;


CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE(
  conversation_id UUID,
  type TEXT,
  name TEXT,
  avatar_url TEXT,
  user_id UUID,
  username TEXT,
  full_name TEXT,
  last_message_content TEXT,
  last_message_created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH last_messages AS (
    SELECT
      conversation_id,
      MAX(created_at) as max_created_at
    FROM messages
    GROUP BY conversation_id
  )
  SELECT
    c.id as conversation_id,
    c.type,
    COALESCE(p.full_name, c.name) as name,
    COALESCE(p.avatar_url, c.avatar_url) as avatar_url,
    p.id as user_id,
    p.username,
    p.full_name,
    m.content as last_message_content,
    m.created_at as last_message_created_at
  FROM conversations c
  JOIN conversation_members cm ON c.id = cm.conversation_id
  LEFT JOIN conversation_members cm_partner ON c.id = cm_partner.conversation_id AND cm_partner.user_id != auth.uid()
  LEFT JOIN profiles p ON cm_partner.user_id = p.id AND c.type = 'private'
  LEFT JOIN last_messages lm ON c.id = lm.conversation_id
  LEFT JOIN messages m ON lm.conversation_id = m.conversation_id AND lm.max_created_at = m.created_at
  WHERE cm.user_id = auth.uid()
  ORDER BY m.created_at DESC NULLS LAST;
END;
$$;


-- الخطوة 6: إعادة إنشاء المشغل والسياسات
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own profile." ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can insert their own profile." ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile." ON public.profiles FOR UPDATE USING (auth.uid() = id);

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view conversations they are a member of." ON public.conversations FOR SELECT USING (
  id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
);

ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view members of conversations they are in." ON public.conversation_members FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
);
CREATE POLICY "Users can insert members into conversations they are in." ON public.conversation_members FOR INSERT WITH CHECK (
  conversation_id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view messages in conversations they are a member of." ON public.messages FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
);
CREATE POLICY "Users can send messages in conversations they are a member of." ON public.messages FOR INSERT WITH CHECK (
  user_id = auth.uid() AND
  conversation_id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
);
