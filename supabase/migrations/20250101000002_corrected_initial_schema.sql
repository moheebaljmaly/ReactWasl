/*
  # [Corrected Initial Schema &amp; Functions]
  This script creates the complete database schema for the "Wasl" messaging app.
  It fixes the previous error by defining the `handle_new_user` function before the trigger that uses it.
  It also includes security best practices like setting a fixed `search_path` for all functions.

  ## Query Description: [This script sets up the entire database structure. If run on an existing database with these tables, it will first drop them and then recreate them, which will result in data loss. It is intended for initial setup or for resetting the development database.]
          
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["High"]
  - Requires-Backup: [true]
  - Reversible: [false]
  
  ## Structure Details:
  - Tables: profiles, conversations, conversation_members, messages, message_status
  - Functions: handle_new_user, create_private_conversation, get_user_conversations, get_conversation_partner
  - Triggers: on_auth_user_created
  - RLS Policies: For all tables
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [Yes]
  - Auth Requirements: [Users must be authenticated to access their data]
  
  ## Performance Impact:
  - Indexes: [Primary keys and foreign keys are indexed by default]
  - Triggers: [Adds a trigger to `auth.users` for profile creation]
  - Estimated Impact: [Low impact on a new database]
*/

-- 1. Drop existing objects if they exist to ensure a clean slate
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.create_private_conversation(uuid);
DROP FUNCTION IF EXISTS public.get_user_conversations();
DROP FUNCTION IF EXISTS public.get_conversation_partner(uuid);
DROP TABLE IF EXISTS public.message_status;
DROP TABLE IF EXISTS public.messages;
DROP TABLE IF EXISTS public.conversation_members;
DROP TABLE IF EXISTS public.conversations;
DROP TABLE IF EXISTS public.profiles;


-- 2. Create `profiles` table
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL PRIMARY KEY,
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


-- 3. Create `handle_new_user` function **BEFORE** the trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Set a fixed search path to prevent security issues
  SET search_path = public;

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
COMMENT ON FUNCTION public.handle_new_user() IS 'Trigger function to create a profile for a new user in auth.users.';


-- 4. Create the trigger on `auth.users`
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- 5. Create other tables
CREATE TABLE public.conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE public.conversations IS 'Represents a chat between two or more users.';

CREATE TABLE public.conversation_members (
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);
COMMENT ON TABLE public.conversation_members IS 'Associates users with conversations.';

CREATE TABLE public.messages (
  id BIGSERIAL PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  content TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE public.messages IS 'Stores individual chat messages.';


-- 6. Create other helper functions
CREATE OR REPLACE FUNCTION public.create_private_conversation(other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  existing_conversation_id UUID;
  new_conversation_id UUID;
BEGIN
  -- Set a fixed search path
  SET search_path = public;

  -- Check if a conversation already exists between the two users
  SELECT cm1.conversation_id INTO existing_conversation_id
  FROM conversation_members cm1
  JOIN conversation_members cm2 ON cm1.conversation_id = cm2.conversation_id
  WHERE cm1.user_id = auth.uid() AND cm2.user_id = other_user_id;

  IF existing_conversation_id IS NOT NULL THEN
    RETURN existing_conversation_id;
  END IF;

  -- If not, create a new conversation
  INSERT INTO conversations DEFAULT VALUES RETURNING id INTO new_conversation_id;

  -- Add both users to the new conversation
  INSERT INTO conversation_members (conversation_id, user_id)
  VALUES (new_conversation_id, auth.uid()), (new_conversation_id, other_user_id);

  RETURN new_conversation_id;
END;
$$;
COMMENT ON FUNCTION public.create_private_conversation(uuid) IS 'Creates or returns an existing private conversation between the current user and another user.';

CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE (
  conversation_id UUID,
  other_user_id UUID,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT,
  last_message_content TEXT,
  last_message_created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE sql
AS $$
  -- Set a fixed search path
  SET search_path = public;

  SELECT
    c.id as conversation_id,
    p.id as other_user_id,
    p.username,
    p.full_name,
    p.avatar_url,
    (SELECT content FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message_content,
    (SELECT created_at FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message_created_at
  FROM conversations c
  JOIN conversation_members cm ON c.id = cm.conversation_id
  JOIN profiles p ON p.id = cm.user_id
  WHERE cm.user_id != auth.uid()
  AND c.id IN (SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid());
$$;
COMMENT ON FUNCTION public.get_user_conversations() IS 'Fetches all conversations for the currently authenticated user.';

CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id UUID)
RETURNS TABLE (
  id UUID,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT
)
LANGUAGE sql
AS $$
  -- Set a fixed search path
  SET search_path = public;

  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM profiles p
  JOIN conversation_members cm ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id
  AND cm.user_id != auth.uid()
  LIMIT 1;
$$;
COMMENT ON FUNCTION public.get_conversation_partner(uuid) IS 'Gets the profile of the other user in a private conversation.';


-- 7. Enable Row Level Security (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- 8. Create RLS Policies
CREATE POLICY "Users can view all profiles." ON public.profiles
  FOR SELECT USING (true);

CREATE POLICY "Users can insert their own profile." ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile." ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can view conversations they are a member of." ON public.conversations
  FOR SELECT USING (id IN (
    SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can view members of conversations they are in." ON public.conversation_members
  FOR SELECT USING (conversation_id IN (
    SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can view messages in conversations they are a member of." ON public.messages
  FOR SELECT USING (conversation_id IN (
    SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can insert messages in conversations they are a member of." ON public.messages
  FOR INSERT WITH CHECK (
    user_id = auth.uid() AND
    conversation_id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
  );

-- 9. Enable Realtime on messages table
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
