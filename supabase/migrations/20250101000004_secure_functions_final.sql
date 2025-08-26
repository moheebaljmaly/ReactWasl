/*
          # [Function Security Hardening]
          This script enhances the security of existing PostgreSQL functions by setting a fixed search_path and using the SECURITY DEFINER property. This mitigates potential search path hijacking vulnerabilities as flagged in the security advisory.

          ## Query Description: [This operation re-defines all custom functions to enhance security. It ensures that functions run with the permissions of their owner and with a safe, predefined schema search path. There is no risk to existing data.]
          
          ## Metadata:
          - Schema-Category: ["Structural", "Safe"]
          - Impact-Level: ["Low"]
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Functions being modified:
            - public.handle_new_user()
            - public.create_private_conversation(other_user_id UUID)
            - public.get_conversation_partner(p_conversation_id UUID)
            - public.get_user_conversations()
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [No Change]
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [No Change]
          - Estimated Impact: [Negligible performance impact.]
          */

-- Drop existing trigger to redefine the function it depends on.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 1. Redefine handle_new_user function with security enhancements.
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

-- Recreate the trigger to call the updated function.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. Redefine create_private_conversation function with security enhancements.
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
  FROM conversations c
  JOIN conversation_members cm1 ON c.id = cm1.conversation_id
  JOIN conversation_members cm2 ON c.id = cm2.conversation_id
  WHERE c.type = 'private'
    AND cm1.user_id = auth.uid()
    AND cm2.user_id = other_user_id;

  -- If it exists, return its ID
  IF existing_conversation_id IS NOT NULL THEN
    RETURN existing_conversation_id;
  END IF;

  -- If not, create a new conversation
  INSERT INTO conversations (type, created_by)
  VALUES ('private', auth.uid())
  RETURNING id INTO new_conversation_id;

  -- Add both users as members of the new conversation
  INSERT INTO conversation_members (conversation_id, user_id)
  VALUES (new_conversation_id, auth.uid()), (new_conversation_id, other_user_id);

  RETURN new_conversation_id;
END;
$$;

-- 3. Redefine get_conversation_partner function with security enhancements.
CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id UUID)
RETURNS TABLE(id UUID, username TEXT, full_name TEXT, avatar_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM profiles p
  JOIN conversation_members cm ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id AND cm.user_id != auth.uid();
END;
$$;

-- 4. Redefine get_user_conversations function with security enhancements.
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
      m.conversation_id,
      m.content,
      m.created_at,
      ROW_NUMBER() OVER(PARTITION BY m.conversation_id ORDER BY m.created_at DESC) as rn
    FROM messages m
  )
  SELECT
    c.id AS conversation_id,
    p.id AS user_id,
    p.username,
    p.full_name,
    p.avatar_url,
    lm.content AS last_message_content,
    lm.created_at AS last_message_created_at
  FROM conversations c
  JOIN conversation_members cm_user ON c.id = cm_user.conversation_id AND cm_user.user_id = auth.uid()
  JOIN conversation_members cm_partner ON c.id = cm_partner.conversation_id AND cm_partner.user_id != auth.uid()
  JOIN profiles p ON cm_partner.user_id = p.id
  LEFT JOIN last_messages lm ON c.id = lm.conversation_id AND lm.rn = 1
  WHERE c.type = 'private'
  ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;
