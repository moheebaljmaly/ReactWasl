/*
          # [Final Hardening]
          This script provides the final security hardening for all database functions. It ensures that all functions have a fixed `search_path` to mitigate security risks, addressing the "Function Search Path Mutable" warning. It also re-creates functions in a safe, idempotent way.

          ## Query Description: [This operation will safely drop and recreate all server-side functions to apply final security settings. It ensures the application's backend logic is secure and robust. No data will be lost.]
          
          ## Metadata:
          - Schema-Category: ["Safe", "Structural"]
          - Impact-Level: ["Low"]
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Drops and recreates the following functions with security settings:
            - handle_new_user()
            - search_users(text)
            - create_private_conversation(uuid)
            - get_user_conversations()
            - get_conversation_partner(uuid)
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [No Change]
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [No Change]
          - Estimated Impact: [Negligible performance impact. This is a one-time structural change.]
          */

-- Drop existing functions safely before recreating them
DROP FUNCTION IF EXISTS public.get_conversation_partner(p_conversation_id uuid);
DROP FUNCTION IF EXISTS public.get_user_conversations();
DROP FUNCTION IF EXISTS public.create_private_conversation(other_user_id uuid);
DROP FUNCTION IF EXISTS public.search_users(search_term text);
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();


-- 1. Function to create a profile for a new user.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
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
-- Set a secure search path for the function
ALTER FUNCTION public.handle_new_user() SET search_path = '';

-- 2. Trigger to call the function when a new user signs up.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- 3. Function to search for users by username or email.
CREATE OR REPLACE FUNCTION public.search_users(search_term TEXT)
RETURNS TABLE(id UUID, username TEXT, full_name TEXT, avatar_url TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM public.profiles p
  WHERE
    (p.username ILIKE '%' || search_term || '%' OR p.full_name ILIKE '%' || search_term || '%')
    AND p.id <> auth.uid();
END;
$$;
-- Set a secure search path for the function
ALTER FUNCTION public.search_users(text) SET search_path = '';


-- 4. Function to create a new private conversation or return an existing one.
CREATE OR REPLACE FUNCTION public.create_private_conversation(other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  convo_id UUID;
BEGIN
  -- Check if a private conversation between these two users already exists
  SELECT c.id INTO convo_id
  FROM conversations c
  JOIN conversation_members cm1 ON c.id = cm1.conversation_id
  JOIN conversation_members cm2 ON c.id = cm2.conversation_id
  WHERE c.type = 'private'
    AND cm1.user_id = auth.uid()
    AND cm2.user_id = other_user_id;

  -- If a conversation exists, return its ID
  IF convo_id IS NOT NULL THEN
    RETURN convo_id;
  END IF;

  -- If no conversation exists, create a new one
  INSERT INTO conversations (type, created_by)
  VALUES ('private', auth.uid())
  RETURNING id INTO convo_id;

  -- Add both users as members of the new conversation
  INSERT INTO conversation_members (conversation_id, user_id)
  VALUES (convo_id, auth.uid()), (convo_id, other_user_id);

  RETURN convo_id;
END;
$$;
-- Set a secure search path for the function
ALTER FUNCTION public.create_private_conversation(uuid) SET search_path = '';


-- 5. Function to get all conversations for the current user with last message details.
CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE(
  conversation_id UUID,
  type TEXT,
  full_name TEXT,
  username TEXT,
  avatar_url TEXT,
  last_message_content TEXT,
  last_message_created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
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
    c.id AS conversation_id,
    c.type,
    p.full_name,
    p.username,
    p.avatar_url,
    lm.content AS last_message_content,
    lm.created_at AS last_message_created_at
  FROM conversations c
  JOIN conversation_members self_cm ON c.id = self_cm.conversation_id
  JOIN conversation_members other_cm ON c.id = other_cm.conversation_id
  JOIN profiles p ON other_cm.user_id = p.id
  LEFT JOIN last_messages lm ON c.id = lm.conversation_id AND lm.rn = 1
  WHERE self_cm.user_id = auth.uid()
    AND other_cm.user_id <> auth.uid()
    AND c.type = 'private'
  ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;
-- Set a secure search path for the function
ALTER FUNCTION public.get_user_conversations() SET search_path = '';


-- 6. Function to get the other participant's profile in a private conversation.
CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id UUID)
RETURNS TABLE(id UUID, username TEXT, full_name TEXT, avatar_url TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM profiles p
  JOIN conversation_members cm ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id
    AND cm.user_id <> auth.uid();
END;
$$;
-- Set a secure search path for the function
ALTER FUNCTION public.get_conversation_partner(uuid) SET search_path = '';
