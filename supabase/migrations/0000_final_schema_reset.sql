-- #################################################################
-- ############# Wसल APP - FINAL DATABASE RESET SCRIPT #############
-- #################################################################
-- This script safely drops all existing objects and rebuilds the
-- entire database schema from scratch, fixing all previous errors.

-- ========= PHASE 1: SAFE DELETION (DROPPING OBJECTS) =========

-- Drop RLS policies first to remove dependencies
DROP POLICY IF EXISTS "Users can view their own profile." ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile." ON public.profiles;
DROP POLICY IF EXISTS "Users can view conversations they are a member of." ON public.conversations;
DROP POLICY IF EXISTS "Users can insert their own messages." ON public.messages;
DROP POLICY IF EXISTS "Users can view messages in conversations they are part of." ON public.messages;
DROP POLICY IF EXISTS "Users can view members of conversations they are in." ON public.conversation_members;
DROP POLICY IF EXISTS "Users can insert themselves into conversations." ON public.conversation_members;

-- Drop storage policies
DROP POLICY IF EXISTS "Avatar images are publicly accessible." ON storage.objects;
DROP POLICY IF EXISTS "Users can upload their own avatar." ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own avatar." ON storage.objects;

-- Drop the trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_user_conversations();
DROP FUNCTION IF EXISTS public.get_conversation_partner(uuid);
DROP FUNCTION IF EXISTS public.create_private_conversation(other_user_id uuid);

-- Drop tables in reverse order of creation
DROP TABLE IF EXISTS public.messages;
DROP TABLE IF EXISTS public.conversation_members;
DROP TABLE IF EXISTS public.conversations;
DROP TABLE IF EXISTS public.profiles;

-- Drop the storage bucket if it exists (CORRECTED METHOD)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'avatars') THEN
    PERFORM storage.delete_bucket('avatars');
  END IF;
END $$;


-- ========= PHASE 2: REBUILDING SCHEMA FROM SCRATCH =========

-- 1. Create Tables
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  status TEXT DEFAULT 'مرحباً، أستخدم وصل!',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE public.profiles IS 'Stores user profile information.';

CREATE TABLE public.conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  is_group BOOLEAN DEFAULT false
);
COMMENT ON TABLE public.conversations IS 'Stores conversation metadata.';

CREATE TABLE public.conversation_members (
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  PRIMARY KEY (conversation_id, user_id)
);
COMMENT ON TABLE public.conversation_members IS 'Associates users with conversations.';

CREATE TABLE public.messages (
  id BIGSERIAL PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE public.messages IS 'Stores chat messages for all conversations.';


-- 2. Create Storage Bucket for Avatars
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;


-- 3. Create Functions
-- Function to create a profile for a new user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, username, full_name, avatar_url)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'username',
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url'
  );
  RETURN new;
END;
$$;

-- Function to get all conversations for the current user
CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE (
  conversation_id UUID,
  is_group BOOLEAN,
  last_message_content TEXT,
  last_message_created_at TIMESTAMPTZ,
  user_id UUID,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH last_messages AS (
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
    c.is_group,
    lm.content as last_message_content,
    lm.created_at as last_message_created_at,
    p.id as user_id,
    p.username,
    p.full_name,
    p.avatar_url
  FROM conversations c
  JOIN conversation_members cm_self ON c.id = cm_self.conversation_id
  LEFT JOIN conversation_members cm_other ON c.id = cm_other.conversation_id AND cm_other.user_id != auth.uid()
  LEFT JOIN profiles p ON p.id = cm_other.user_id
  LEFT JOIN last_messages lm ON c.id = lm.conversation_id AND lm.rn = 1
  WHERE cm_self.user_id = auth.uid()
  ORDER BY lm.created_at DESC NULLS LAST, c.created_at DESC;
END;
$$;

-- Function to get the other user in a private conversation
CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id UUID)
RETURNS TABLE (
  id UUID,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM public.profiles p
  JOIN public.conversation_members cm ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id AND cm.user_id != auth.uid();
END;
$$;

-- Function to create a new private conversation
CREATE OR REPLACE FUNCTION public.create_private_conversation(other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
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

  -- If not, create a new one
  INSERT INTO conversations (is_group) VALUES (false) RETURNING id INTO new_conversation_id;
  INSERT INTO conversation_members (conversation_id, user_id) VALUES (new_conversation_id, auth.uid());
  INSERT INTO conversation_members (conversation_id, user_id) VALUES (new_conversation_id, other_user_id);

  RETURN new_conversation_id;
END;
$$;


-- 4. Create Trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- 5. Enable RLS and Create Policies
-- Profiles Table
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own profile." ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile." ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can view all profiles." ON public.profiles FOR SELECT TO authenticated USING (true);

-- Conversations Table
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view conversations they are a member of." ON public.conversations FOR SELECT USING (
  id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);

-- Conversation Members Table
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view members of conversations they are in." ON public.conversation_members FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);
CREATE POLICY "Users can insert themselves into conversations." ON public.conversation_members FOR INSERT WITH CHECK (user_id = auth.uid());

-- Messages Table
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can insert their own messages." ON public.messages FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can view messages in conversations they are part of." ON public.messages FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);

-- Storage Policies
CREATE POLICY "Avatar images are publicly accessible." ON storage.objects FOR SELECT TO public USING (bucket_id = 'avatars');
CREATE POLICY "Users can upload their own avatar." ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'avatars' AND auth.uid() = (storage.foldername(name))[1]::uuid);
CREATE POLICY "Users can update their own avatar." ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'avatars' AND auth.uid() = (storage.foldername(name))[1]::uuid);
