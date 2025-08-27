/*
# [Secure Functions]
This script hardens the security of all database functions by explicitly setting the search_path.
This prevents potential security vulnerabilities related to search path hijacking.

## Query Description: [This operation enhances the security of your database functions by setting a fixed search_path. It does not alter functionality or data but is a crucial security best practice. No backup is required as this is a safe, metadata-only change.]

## Metadata:
- Schema-Category: ["Safe", "Security"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Modifies functions: handle_new_user, search_users, get_conversation_partner, create_private_conversation, get_user_conversations

## Security Implications:
- RLS Status: [Unaffected]
- Policy Changes: [No]
- Auth Requirements: [Admin privileges]

## Performance Impact:
- Indexes: [Unaffected]
- Triggers: [Unaffected]
- Estimated Impact: [None]
*/

-- Secure handle_new_user function
ALTER FUNCTION public.handle_new_user() SET search_path = public;

-- Secure search_users function
ALTER FUNCTION public.search_users(search_term text) SET search_path = public;

-- Secure get_conversation_partner function
ALTER FUNCTION public.get_conversation_partner(p_conversation_id uuid) SET search_path = public;

-- Secure create_private_conversation function
ALTER FUNCTION public.create_private_conversation(other_user_id uuid) SET search_path = public;

-- Secure get_user_conversations function
ALTER FUNCTION public.get_user_conversations() SET search_path = public;
