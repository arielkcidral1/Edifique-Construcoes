DROP INDEX IF EXISTS public.customers_cpf_digits_key;
-- PASSO 1 — Limpar CPFs duplicados
UPDATE public.customers
SET cpf = NULL
WHERE cpf IS NOT NULL
  AND id NOT IN (
    SELECT DISTINCT ON (regexp_replace(COALESCE(cpf, ''), '\D', '', 'g')) id
    FROM public.customers
    WHERE cpf IS NOT NULL
      AND regexp_replace(COALESCE(cpf, ''), '\D', '', 'g') <> ''
    ORDER BY
      regexp_replace(COALESCE(cpf, ''), '\D', '', 'g'),
      CASE WHEN user_id IS NOT NULL THEN 0 ELSE 1 END,
      id ASC
  );

-- PASSO 2 — Recriar índice ignorando registros sem user_id
CREATE UNIQUE INDEX customers_cpf_digits_key
ON public.customers (
  (regexp_replace(COALESCE(cpf, ''), '\D', '', 'g'))
)
WHERE
  cpf IS NOT NULL
  AND regexp_replace(COALESCE(cpf, ''), '\D', '', 'g') <> ''
  AND user_id IS NOT NULL;

-- PASSO 3 — Recriar função corrigida
CREATE OR REPLACE FUNCTION public.upsert_customer_profile(
  name_input  TEXT,
  email_input TEXT,
  cpf_input   TEXT,
  phone_input TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := (SELECT auth.uid());
  current_email   TEXT := lower(trim((SELECT (auth.jwt()) ->> 'email')));
  v_cpf           TEXT;
  v_existing_id   BIGINT;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado.' USING ERRCODE = '42501';
  END IF;

  IF current_email IS NULL OR current_email <> lower(trim(email_input)) THEN
    RAISE EXCEPTION 'E-mail não corresponde ao usuário autenticado.' USING ERRCODE = '42501';
  END IF;

  v_cpf := regexp_replace(COALESCE(cpf_input, ''), '\D', '', 'g');
  IF v_cpf = '' OR length(v_cpf) <> 11 THEN v_cpf := NULL; END IF;

  IF v_cpf IS NOT NULL THEN
    SELECT id INTO v_existing_id
    FROM public.customers
    WHERE regexp_replace(COALESCE(cpf, ''), '\D', '', 'g') = v_cpf
      AND lower(trim(email)) <> lower(trim(email_input))
      AND user_id IS NOT NULL
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      UPDATE public.customers SET cpf = NULL WHERE id = v_existing_id;
    END IF;
  END IF;

  INSERT INTO public.customers (user_id, name, email, cpf, phone)
  VALUES (
    current_user_id,
    COALESCE(NULLIF(name_input, ''), email_input, 'Cliente'),
    lower(trim(email_input)),
    v_cpf,
    NULLIF(phone_input, '')
  )
  ON CONFLICT (email) DO UPDATE SET
    user_id = COALESCE(public.customers.user_id, EXCLUDED.user_id),
    name    = EXCLUDED.name,
    cpf     = CASE
                WHEN EXCLUDED.cpf IS NOT NULL THEN EXCLUDED.cpf
                ELSE public.customers.cpf
              END,
    phone   = CASE
                WHEN EXCLUDED.phone IS NOT NULL THEN EXCLUDED.phone
                ELSE public.customers.phone
              END;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_customer_profile(TEXT, TEXT, TEXT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.upsert_customer_profile(TEXT, TEXT, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
-- Testar direto
SELECT public.get_customer_login_email('12417691922');

-- Ver CPF nos metadados dos usuários com CPF NULL no customers
SELECT 
  au.id,
  au.email,
  au.raw_user_meta_data->>'cpf' AS cpf_meta,
  regexp_replace(COALESCE(au.raw_user_meta_data->>'cpf', ''), '\D', '', 'g') AS cpf_digits
FROM auth.users au
JOIN public.customers c ON c.user_id = au.id
WHERE c.cpf IS NULL
  AND au.email <> 'admin@edifique.com';