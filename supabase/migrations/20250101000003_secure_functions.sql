/*
  # [SECURITY ENHANCEMENT] Secure Functions
  This migration enhances the security of existing database functions by explicitly setting the `search_path`. This mitigates potential risks associated with search path hijacking and addresses the "Function Search Path Mutable" security advisory.

  ## Query Description: 
  This operation modifies the configuration of existing functions without altering their logic. It ensures that functions only search for objects within the 'public' schema, preventing them from being tricked into executing malicious code from other schemas. There is no impact on existing data.

  ## Metadata:
  - Schema-Category: ["Safe", "Security"]
  - Impact-Level: ["Low"]
  - Requires-Backup: false
  - Reversible: true (by altering the function again to remove the setting)
  
  ## Structure Details:
  - Functions affected:
    - handle_new_user()
    - get_user_conversations()
    - create_private_conversation()
    - get_conversation_partner()
  
  ## Security Implications:
  - RLS Status: Unchanged
  - Policy Changes: No
  - Auth Requirements: Unchanged
  - Mitigates: Search path attacks.
  
  ## Performance Impact:
  - Indexes: Unchanged
  - Triggers: Unchanged
  - Estimated Impact: Negligible. May slightly improve performance by reducing schema lookup paths.
*/

-- Secure the trigger function
ALTER FUNCTION public.handle_new_user()
SET search_path = 'public';

-- Secure the RPC functions
ALTER FUNCTION public.get_user_conversations()
SET search_path = 'public';

ALTER FUNCTION public.create_private_conversation(other_user_id uuid)
SET search_path = 'public';

ALTER FUNCTION public.get_conversation_partner(p_conversation_id uuid)
SET search_path = 'public';
