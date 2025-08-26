/*
          # [Fix Dependencies & Recreate DB]
          This script fixes a dependency error from the previous migration by dropping all database objects in the correct order before recreating them. It ensures a clean and correct setup for the Wasl application.

          ## Query Description: [This script will completely reset the application's database schema. It drops all existing policies, functions, triggers, and tables related to the app and then rebuilds them from scratch. This is a destructive operation for the schema but ensures that all dependencies are correctly resolved. No user data from `auth.users` will be lost, but all profiles, conversations, and messages will be deleted.]
          
          ## Metadata:
          - Schema-Category: ["Dangerous"]
          - Impact-Level: ["High"]
          - Requires-Backup: [true]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops and recreates tables: `profiles`, `conversations`, `conversation_members`, `messages`.
          - Drops and recreates all RLS policies.
          - Drops and recreates all helper functions and triggers.
          
          ## Security Implications:
          - RLS Status: [Re-enabled]
          - Policy Changes: [Yes]
          - Auth Requirements: [None for migration]
          
          ## Performance Impact:
          - Indexes: [Re-created]
          - Triggers: [Re-created]
          - Estimated Impact: [Low, as it's a setup script.]
          */

-- =================================================================
-- 1. DROP EXISTING OBJECTS IN CORRECT ORDER
-- =================================================================

-- Drop policies first to remove dependencies
DROP POLICY IF EXISTS "Users can view their own profile." ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile." ON public.profiles;
DROP POLICY IF EXISTS "Profiles are public." ON public.profiles;
DROP POLICY IF EXISTS "Users can view conversations they are a member of." ON public.conversations;
DROP POLICY IF EXISTS "Users can view members of conversations they are in." ON public.conversation_members;
DROP POLICY IF EXISTS "Users can insert themselves into conversations." ON public.conversation_members;
DROP POLICY IF EXISTS "Users can view messages in conversations they are a member of." ON public.messages;
DROP POLICY IF EXISTS "Users can insert messages in conversations they are a member of." ON public.messages;

-- Drop triggers
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.create_private_conversation(uuid);
DROP FUNCTION IF EXISTS public.get_conversation_partner(uuid);
DROP FUNCTION IF EXISTS public.get_user_conversations();
DROP FUNCTION IF EXISTS public.search_users(text);

-- Drop tables (child tables first)
DROP TABLE IF EXISTS public.messages;
DROP TABLE IF EXISTS public.conversation_members;
DROP TABLE IF EXISTS public.conversations;
DROP TABLE IF EXISTS public.profiles;


-- =================================================================
-- 2. CREATE TABLES
-- =================================================================

-- Profiles Table
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL PRIMARY KEY,
  full_name TEXT,
  username TEXT UNIQUE,
  avatar_url TEXT,
  status TEXT DEFAULT 'مرحباً، أستخدم وصل!',
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT username_length CHECK (char_length(username) >= 3)
);
COMMENT ON TABLE public.profiles IS 'Stores user profile information.';

-- Conversations Table
CREATE TABLE public.conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE public.conversations IS 'Stores conversation metadata.';

-- Conversation Members Table
CREATE TABLE public.conversation_members (
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);
COMMENT ON TABLE public.conversation_members IS 'Links users to conversations.';

-- Messages Table
CREATE TABLE public.messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE public.messages IS 'Stores individual chat messages.';


-- =================================================================
-- 3. CREATE STORAGE BUCKETS
-- =================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;


-- =================================================================
-- 4. CREATE FUNCTIONS AND TRIGGERS
-- =================================================================

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

-- Trigger to call the function on new user signup
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Function to create a private conversation
CREATE OR REPLACE FUNCTION public.create_private_conversation(other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  conversation_id UUID;
BEGIN
  -- Check if a conversation already exists
  SELECT c.id INTO conversation_id
  FROM conversations c
  JOIN conversation_members cm1 ON c.id = cm1.conversation_id
  JOIN conversation_members cm2 ON c.id = cm2.conversation_id
  WHERE cm1.user_id = auth.uid() AND cm2.user_id = other_user_id;

  -- If not, create a new one
  IF conversation_id IS NULL THEN
    INSERT INTO conversations DEFAULT VALUES RETURNING id INTO conversation_id;
    INSERT INTO conversation_members (conversation_id, user_id) VALUES (conversation_id, auth.uid());
    INSERT INTO conversation_members (conversation_id, user_id) VALUES (conversation_id, other_user_id);
  END IF;

  RETURN conversation_id;
END;
$$;

-- Function to get conversation partner details
CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id UUID)
RETURNS TABLE(user_id UUID, username TEXT, full_name TEXT, avatar_url TEXT)
LANGUAGE sql
AS $$
  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM profiles p
  JOIN conversation_members cm ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id AND cm.user_id != auth.uid()
  LIMIT 1;
$$;

-- Function to get all user conversations with last message
CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE(
  conversation_id UUID,
  other_user_id UUID,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT,
  last_message_content TEXT,
  last_message_created_at TIMESTAMPTZ
)
LANGUAGE sql
AS $$
  SELECT
    c.id as conversation_id,
    p.id as other_user_id,
    p.username,
    p.full_name,
    p.avatar_url,
    last_msg.content as last_message_content,
    last_msg.created_at as last_message_created_at
  FROM conversations c
  JOIN conversation_members cm ON c.id = cm.conversation_id
  JOIN profiles p ON p.id = cm.user_id
  LEFT JOIN LATERAL (
    SELECT content, created_at
    FROM messages
    WHERE conversation_id = c.id
    ORDER BY created_at DESC
    LIMIT 1
  ) last_msg ON true
  WHERE cm.user_id != auth.uid() AND c.id IN (
    SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid()
  )
  ORDER BY last_msg.created_at DESC NULLS LAST;
$$;


-- =================================================================
-- 5. SETUP ROW LEVEL SECURITY (RLS)
-- =================================================================

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Policies for Profiles
CREATE POLICY "Profiles are public." ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can insert their own profile." ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile." ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Policies for Conversations
CREATE POLICY "Users can view conversations they are a member of." ON public.conversations FOR SELECT USING (
  id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);

-- Policies for Conversation Members
CREATE POLICY "Users can view members of conversations they are in." ON public.conversation_members FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);
CREATE POLICY "Users can insert themselves into conversations." ON public.conversation_members FOR INSERT WITH CHECK (user_id = auth.uid());

-- Policies for Messages
CREATE POLICY "Users can view messages in conversations they are a member of." ON public.messages FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);
CREATE POLICY "Users can insert messages in conversations they are a member of." ON public.messages FOR INSERT WITH CHECK (
  user_id = auth.uid() AND conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid())
);

-- Policies for Storage
CREATE POLICY "Avatar images are publicly accessible." ON storage.objects FOR SELECT USING ( bucket_id = 'avatars' );
CREATE POLICY "Anyone can upload an avatar." ON storage.objects FOR INSERT WITH CHECK ( bucket_id = 'avatars' );
CREATE POLICY "Anyone can update their own avatar." ON storage.objects FOR UPDATE USING ( auth.uid() = owner ) WITH CHECK ( bucket_id = 'avatars' );
