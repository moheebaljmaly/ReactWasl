/*
# [إعادة تعيين وإعداد قاعدة بيانات تطبيق وصل]
[يقوم هذا السكربت بإعادة تعيين قاعدة البيانات بالكامل وإعدادها من الصفر. يتضمن حذف جميع الجداول والسياسات والدوال المتعلقة بالتطبيق ثم إعادة إنشائها بشكل آمن وصحيح.]

## Query Description: [سيقوم هذا السكربت بحذف جميع البيانات المتعلقة بالمستخدمين والمحادثات. إذا كان لديك بيانات مهمة، يرجى أخذ نسخة احتياطية قبل التشغيل. تم تصميم السكربت ليكون آمنًا للتشغيل عدة مرات.]

## Metadata:
- Schema-Category: ["Dangerous", "Structural"]
- Impact-Level: ["High"]
- Requires-Backup: [true]
- Reversible: [false]

## Structure Details:
- **Tables Dropped & Recreated:** profiles, conversations, conversation_members, messages
- **Functions Dropped & Recreated:** handle_new_user, create_private_conversation, get_conversation_partner, get_user_conversations
- **Storage Bucket Dropped & Recreated:** avatars
- **RLS Policies:** All policies will be dropped and recreated.
*/

-- ========== PART 1: TEARDOWN (SAFE DELETION) ==========

-- Drop policies safely
DROP POLICY IF EXISTS "Users can view their own profile." ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile." ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile." ON public.profiles;

DROP POLICY IF EXISTS "Users can view conversations they are a member of." ON public.conversations;
DROP POLICY IF EXISTS "Users can insert conversations." ON public.conversations;

DROP POLICY IF EXISTS "Users can view members of conversations they are in." ON public.conversation_members;
DROP POLICY IF EXISTS "Users can insert themselves into conversations." ON public.conversation_members;

DROP POLICY IF EXISTS "Users can view messages in conversations they are a member of." ON public.messages;
DROP POLICY IF EXISTS "Users can insert messages in conversations they are a member of." ON public.messages;

-- Drop trigger safely
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop functions safely
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.create_private_conversation(other_user_id uuid);
DROP FUNCTION IF EXISTS public.get_conversation_partner(p_conversation_id uuid);
DROP FUNCTION IF EXISTS public.get_user_conversations();

-- Drop tables safely
DROP TABLE IF EXISTS public.messages;
DROP TABLE IF EXISTS public.conversation_members;
DROP TABLE IF EXISTS public.conversations;
DROP TABLE IF EXISTS public.profiles;

-- Drop storage policies and bucket safely
DROP POLICY IF EXISTS "Avatar images are publicly accessible." ON storage.objects;
DROP POLICY IF EXISTS "Anyone can upload an avatar." ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update their own avatar." ON storage.objects;
DELETE FROM storage.buckets WHERE id = 'avatars';


-- ========== PART 2: SETUP (RE-CREATION) ==========

-- Create profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  username TEXT UNIQUE,
  avatar_url TEXT,
  status TEXT DEFAULT 'مرحباً، أستخدم وصل!',
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE public.profiles IS 'Stores user profile information.';

-- Create conversations table
CREATE TABLE public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT CHECK (type IN ('private', 'group')) DEFAULT 'private',
  created_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE public.conversations IS 'Stores conversation metadata.';

-- Create conversation_members table
CREATE TABLE public.conversation_members (
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  PRIMARY KEY (conversation_id, user_id)
);
COMMENT ON TABLE public.conversation_members IS 'Links users to conversations.';

-- Create messages table
CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE public.messages IS 'Stores chat messages for all conversations.';

-- ========== PART 3: STORAGE SETUP ==========

-- Create avatars bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- ========== PART 4: FUNCTIONS AND TRIGGERS ==========

-- Function to create a profile for a new user
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

-- Trigger for new user
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to create a private conversation
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
  JOIN conversations c ON cm1.conversation_id = c.id
  WHERE cm1.user_id = auth.uid() AND cm2.user_id = other_user_id AND c.type = 'private';

  IF existing_conversation_id IS NOT NULL THEN
    RETURN existing_conversation_id;
  END IF;

  -- Create a new conversation
  INSERT INTO conversations (type) VALUES ('private') RETURNING id INTO new_conversation_id;
  INSERT INTO conversation_members (conversation_id, user_id) VALUES (new_conversation_id, auth.uid());
  INSERT INTO conversation_members (conversation_id, user_id) VALUES (new_conversation_id, other_user_id);
  
  RETURN new_conversation_id;
END;
$$;

-- Function to get conversation partner info
CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id UUID)
RETURNS TABLE (
  id UUID,
  full_name TEXT,
  username TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.full_name, p.username, p.avatar_url
  FROM profiles p
  JOIN conversation_members cm ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id AND cm.user_id != auth.uid();
END;
$$;

-- Function to get all user conversations with last message
CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE (
  conversation_id UUID,
  type TEXT,
  full_name TEXT,
  username TEXT,
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
  SELECT
    c.id as conversation_id,
    c.type,
    p.full_name,
    p.username,
    p.avatar_url,
    lm.content as last_message_content,
    lm.created_at as last_message_created_at
  FROM conversations c
  JOIN conversation_members cm ON c.id = cm.conversation_id
  JOIN profiles p ON cm.user_id = p.id AND p.id != auth.uid()
  LEFT JOIN LATERAL (
    SELECT content, created_at
    FROM messages
    WHERE conversation_id = c.id
    ORDER BY created_at DESC
    LIMIT 1
  ) lm ON true
  WHERE c.id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid());
END;
$$;

-- ========== PART 5: ROW LEVEL SECURITY (RLS) ==========

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Profiles Policies
CREATE POLICY "Users can view their own profile." ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can insert their own profile." ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile." ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Conversations Policies
CREATE POLICY "Users can view conversations they are a member of." ON public.conversations FOR SELECT USING (
  id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);
CREATE POLICY "Users can insert conversations." ON public.conversations FOR INSERT WITH CHECK (true); -- Further checks in function

-- Conversation Members Policies
CREATE POLICY "Users can view members of conversations they are in." ON public.conversation_members FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);
CREATE POLICY "Users can insert themselves into conversations." ON public.conversation_members FOR INSERT WITH CHECK (user_id = auth.uid());

-- Messages Policies
CREATE POLICY "Users can view messages in conversations they are a member of." ON public.messages FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);
CREATE POLICY "Users can insert messages in conversations they are a member of." ON public.messages FOR INSERT WITH CHECK (
  user_id = auth.uid() AND conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);

-- Storage Policies
CREATE POLICY "Avatar images are publicly accessible." ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
CREATE POLICY "Anyone can upload an avatar." ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'avatars');
CREATE POLICY "Authenticated users can update their own avatar." ON storage.objects FOR UPDATE USING (auth.uid() = owner) WITH CHECK (bucket_id = 'avatars');
