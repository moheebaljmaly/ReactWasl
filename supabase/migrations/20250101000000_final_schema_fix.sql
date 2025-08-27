-- 🚀 WASL APP - FINAL & COMPLETE DATABASE SCHEMA
-- This script resets and rebuilds the entire database schema from scratch.
-- It fixes all previous migration errors and includes all necessary tables,
-- functions, policies, and security settings.

-- ==> 1. CLEANUP: Drop existing objects in reverse order of dependency
DROP POLICY IF EXISTS "Users can view conversations they are a member of." ON "public"."conversations";
DROP POLICY IF EXISTS "Users can insert their own messages." ON "public"."messages";
DROP POLICY IF EXISTS "Users can view messages in conversations they are part of." ON "public"."messages";
DROP POLICY IF EXISTS "Users can update their own profile." ON "public"."profiles";
DROP POLICY IF EXISTS "Users can view their own profile." ON "public"."profiles";
DROP POLICY IF EXISTS "Public profiles are viewable by everyone." ON "public"."profiles";
DROP POLICY IF EXISTS "Users can view members of conversations they are in." ON "public"."conversation_members";
DROP POLICY IF EXISTS "Users can insert themselves into conversations." ON "public"."conversation_members";

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_conversation_partner(uuid);
DROP FUNCTION IF EXISTS public.create_private_conversation(uuid);
DROP FUNCTION IF EXISTS public.get_user_conversations();
DROP FUNCTION IF EXISTS public.search_users(text);

DROP TABLE IF EXISTS public.messages;
DROP TABLE IF EXISTS public.conversation_members;
DROP TABLE IF EXISTS public.conversations;
DROP TABLE IF EXISTS public.profiles;

-- ==> 2. SETUP STORAGE: Create avatars bucket
-- Note: We handle bucket deletion/creation manually if needed, but insertion is safe.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/gif'])
ON CONFLICT (id) DO NOTHING;

-- BUCKET: avatars. Stores user avatar images.

-- ==> 3. CREATE TABLES: Rebuild the schema
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  username TEXT UNIQUE,
  avatar_url TEXT,
  status TEXT DEFAULT 'مرحباً، أستخدم وصل!',
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE public.profiles IS 'Stores user profile information.';

CREATE TABLE public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE public.conversations IS 'Represents a chat between two or more users.';

CREATE TABLE public.conversation_members (
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);
COMMENT ON TABLE public.conversation_members IS 'Associates users with conversations.';

CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE public.messages IS 'Stores individual chat messages.';

-- ==> 4. CREATE FUNCTIONS: Define database logic
-- Function to create a profile for a new user.
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

-- Function to get the other user in a private conversation.
CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id UUID)
RETURNS TABLE(user_id UUID, username TEXT, full_name TEXT, avatar_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT p.id, p.username, p.full_name, p.avatar_url
    FROM public.conversation_members cm
    JOIN public.profiles p ON cm.user_id = p.id
    WHERE cm.conversation_id = p_conversation_id AND cm.user_id <> auth.uid();
END;
$$;

-- Function to create a new private conversation or return an existing one.
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
  -- Check if a conversation already exists between the two users
  SELECT c.id INTO existing_conversation_id
  FROM public.conversations c
  WHERE EXISTS (SELECT 1 FROM public.conversation_members cm WHERE cm.conversation_id = c.id AND cm.user_id = auth.uid())
    AND EXISTS (SELECT 1 FROM public.conversation_members cm WHERE cm.conversation_id = c.id AND cm.user_id = other_user_id)
  LIMIT 1;

  IF existing_conversation_id IS NOT NULL THEN
    RETURN existing_conversation_id;
  END IF;

  -- If not, create a new conversation
  INSERT INTO public.conversations DEFAULT VALUES RETURNING id INTO new_conversation_id;
  
  -- Add both users to the new conversation
  INSERT INTO public.conversation_members (conversation_id, user_id)
  VALUES (new_conversation_id, auth.uid()), (new_conversation_id, other_user_id);

  RETURN new_conversation_id;
END;
$$;

-- Function to get all conversations for the current user.
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
  WITH last_messages AS (
    SELECT
      conversation_id,
      MAX(created_at) as max_created_at
    FROM public.messages
    GROUP BY conversation_id
  )
  SELECT
    c.id as conversation_id,
    p.id as user_id,
    p.username,
    p.full_name,
    p.avatar_url,
    m.content as last_message_content,
    m.created_at as last_message_created_at
  FROM public.conversations c
  JOIN public.conversation_members cm ON c.id = cm.conversation_id
  JOIN public.profiles p ON cm.user_id = p.id
  LEFT JOIN last_messages lm ON c.id = lm.conversation_id
  LEFT JOIN public.messages m ON lm.conversation_id = m.conversation_id AND lm.max_created_at = m.created_at
  WHERE c.id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
    AND cm.user_id <> auth.uid()
  ORDER BY m.created_at DESC NULLS LAST;
END;
$$;

-- Function to search for users.
CREATE OR REPLACE FUNCTION public.search_users(search_term TEXT)
RETURNS TABLE(id UUID, username TEXT, full_name TEXT, avatar_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM public.profiles p
  WHERE (p.username ILIKE '%' || search_term || '%' OR p.full_name ILIKE '%' || search_term || '%')
    AND p.id <> auth.uid();
END;
$$;

-- ==> 5. CREATE TRIGGER: Automate profile creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ==> 6. ENABLE RLS: Secure all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- ==> 7. CREATE POLICIES: Define access rules
-- Profiles
CREATE POLICY "Public profiles are viewable by everyone." ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can view their own profile." ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile." ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Conversations
CREATE POLICY "Users can view conversations they are a member of." ON public.conversations FOR SELECT USING (
  id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
);

-- Conversation Members
CREATE POLICY "Users can insert themselves into conversations." ON public.conversation_members FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can view members of conversations they are in." ON public.conversation_members FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
);

-- Messages
CREATE POLICY "Users can view messages in conversations they are part of." ON public.messages FOR SELECT USING (
  conversation_id IN (SELECT conversation_id FROM public.conversation_members WHERE user_id = auth.uid())
);
CREATE POLICY "Users can insert their own messages." ON public.messages FOR INSERT WITH CHECK (user_id = auth.uid());

-- Storage
CREATE POLICY "Avatar images are publicly accessible." ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
CREATE POLICY "Anyone can upload an avatar." ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'avatars');
CREATE POLICY "Anyone can update their own avatar." ON storage.objects FOR UPDATE USING (auth.uid() = owner) WITH CHECK (bucket_id = 'avatars');
