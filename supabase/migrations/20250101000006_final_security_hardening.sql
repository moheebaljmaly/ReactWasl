/*
          # [FINAL SECURITY HARDENING]
          This script provides the final security hardening for the database functions.

          ## Query Description: [This script explicitly sets the `search_path` for all custom functions to prevent potential security vulnerabilities related to path manipulation. This is a safe, non-destructive operation that enhances security.]
          
          ## Metadata:
          - Schema-Category: ["Safe", "Security"]
          - Impact-Level: ["Low"]
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Functions being modified:
            - `handle_new_user()`
            - `create_private_conversation(uuid)`
            - `get_user_conversations()`
            - `get_conversation_partner(uuid)`
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [No]
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [No Change]
          - Estimated Impact: [None]
          */

-- Secure function: handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
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

-- Secure function: create_private_conversation
CREATE OR REPLACE FUNCTION public.create_private_conversation(other_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    existing_conversation_id uuid;
    new_conversation_id uuid;
BEGIN
    -- Check if a conversation already exists between the two users
    SELECT c.id INTO existing_conversation_id
    FROM conversations c
    JOIN conversation_members cm1 ON c.id = cm1.conversation_id
    JOIN conversation_members cm2 ON c.id = cm2.conversation_id
    WHERE c.type = 'private'
      AND cm1.user_id = auth.uid()
      AND cm2.user_id = other_user_id;

    -- If a conversation exists, return its ID
    IF existing_conversation_id IS NOT NULL THEN
        RETURN existing_conversation_id;
    END IF;

    -- If no conversation exists, create a new one
    INSERT INTO conversations (type, created_by)
    VALUES ('private', auth.uid())
    RETURNING id INTO new_conversation_id;

    -- Add both users as members of the new conversation
    INSERT INTO conversation_members (conversation_id, user_id)
    VALUES (new_conversation_id, auth.uid()), (new_conversation_id, other_user_id);

    RETURN new_conversation_id;
END;
$$;

-- Secure function: get_user_conversations
CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE(
    conversation_id uuid,
    user_id uuid,
    username text,
    full_name text,
    avatar_url text,
    last_message_content text,
    last_message_created_at timestamptz
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
        p.id as user_id,
        p.username,
        p.full_name,
        p.avatar_url,
        m.content as last_message_content,
        m.created_at as last_message_created_at
    FROM conversations c
    JOIN conversation_members cm_self ON c.id = cm_self.conversation_id AND cm_self.user_id = auth.uid()
    JOIN conversation_members cm_other ON c.id = cm_other.conversation_id AND cm_other.user_id != auth.uid()
    JOIN profiles p ON cm_other.user_id = p.id
    LEFT JOIN last_messages lm ON c.id = lm.conversation_id
    LEFT JOIN messages m ON lm.conversation_id = m.conversation_id AND lm.max_created_at = m.created_at
    WHERE c.type = 'private'
    ORDER BY m.created_at DESC NULLS LAST;
END;
$$;

-- Secure function: get_conversation_partner
CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id uuid)
RETURNS TABLE (
  id uuid,
  username text,
  full_name text,
  avatar_url text
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
  WHERE cm.conversation_id = p_conversation_id
    AND cm.user_id != auth.uid()
  LIMIT 1;
END;
$$;
