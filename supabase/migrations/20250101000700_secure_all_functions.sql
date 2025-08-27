/*
# [Secure All Functions]
This script hardens all previously created database functions by explicitly setting the `search_path`. This is a security best practice that prevents potential hijacking attacks and resolves the "Function Search Path Mutable" warning from Supabase security advisor.

## Query Description: [This operation updates existing function definitions to enhance security. It does not alter data or table structures and is safe to run on the existing database. It ensures all functions operate in a controlled and secure environment.]

## Metadata:
- Schema-Category: ["Safe"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Functions being affected:
  - public.handle_new_user()
  - public.create_private_conversation(uuid)
  - public.get_user_conversations()
  - public.get_conversation_partner(uuid)

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [No]
- Auth Requirements: [None]

## Performance Impact:
- Indexes: [Not Affected]
- Triggers: [Not Affected]
- Estimated Impact: [None. This is a security definition change.]
*/

-- Secure Function 1: handle_new_user
-- This function creates a user profile after signup.
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

-- Secure Function 2: create_private_conversation
-- This function creates a new private conversation between two users if one doesn't already exist.
CREATE OR REPLACE FUNCTION public.create_private_conversation(other_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  convo_id uuid;
BEGIN
  -- Check if a conversation already exists
  SELECT c.id INTO convo_id
  FROM conversations c
  WHERE c.type = 'private'
    AND EXISTS (
      SELECT 1 FROM conversation_members cm
      WHERE cm.conversation_id = c.id AND cm.user_id = auth.uid()
    )
    AND EXISTS (
      SELECT 1 FROM conversation_members cm
      WHERE cm.conversation_id = c.id AND cm.user_id = other_user_id
    );

  -- If no conversation exists, create a new one
  IF convo_id IS NULL THEN
    INSERT INTO conversations (type) VALUES ('private') RETURNING id INTO convo_id;
    INSERT INTO conversation_members (conversation_id, user_id) VALUES (convo_id, auth.uid());
    INSERT INTO conversation_members (conversation_id, user_id) VALUES (convo_id, other_user_id);
  END IF;

  RETURN convo_id;
END;
$$;

-- Secure Function 3: get_user_conversations
-- This function retrieves all conversations for the currently authenticated user.
CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE(
    conversation_id uuid,
    full_name text,
    username text,
    avatar_url text,
    last_message_content text,
    last_message_created_at timestamp with time zone
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    c.id as conversation_id,
    p.full_name,
    p.username,
    p.avatar_url,
    lm.content as last_message_content,
    lm.created_at as last_message_created_at
  FROM conversations c
  JOIN conversation_members cm ON c.id = cm.conversation_id
  JOIN profiles p ON p.id = (
    SELECT user_id FROM conversation_members
    WHERE conversation_id = c.id AND user_id != auth.uid()
    LIMIT 1
  )
  LEFT JOIN LATERAL (
    SELECT content, created_at
    FROM messages
    WHERE conversation_id = c.id
    ORDER BY created_at DESC
    LIMIT 1
  ) lm ON true
  WHERE cm.user_id = auth.uid() AND c.type = 'private'
  ORDER BY lm.created_at DESC NULLS LAST;
$$;

-- Secure Function 4: get_conversation_partner
-- This function gets the profile of the other user in a private conversation.
CREATE OR REPLACE FUNCTION public.get_conversation_partner(p_conversation_id uuid)
RETURNS TABLE(
    id uuid,
    full_name text,
    username text,
    avatar_url text
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    p.id,
    p.full_name,
    p.username,
    p.avatar_url
  FROM profiles p
  JOIN conversation_members cm ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id AND cm.user_id != auth.uid()
  LIMIT 1;
$$;
