-- =============================================================
-- CORREÇÃO DEFINITIVA — Login por CPF
-- Execute completo no SQL Editor do Supabase
-- =============================================================

-- ---------------------------------------------------------------
-- PASSO 1: Diagnóstico — ver o que está salvo para cada cliente
-- ---------------------------------------------------------------
SELECT
  c.id,
  c.name,
  c.email                                              AS email_customers,
  c.cpf                                               AS cpf_customers,
  regexp_replace(COALESCE(c.cpf,''),'\D','','g')       AS cpf_digitos,
  c.user_id,
  au.email                                             AS email_auth,
  au.raw_user_meta_data->>'cpf'                        AS cpf_metadata,
  regexp_replace(COALESCE(au.raw_user_meta_data->>'cpf',''),'\D','','g') AS cpf_metadata_digitos
FROM public.customers c
LEFT JOIN auth.users au ON au.id = c.user_id
ORDER BY c.id DESC
LIMIT 30;

-- ---------------------------------------------------------------
-- PASSO 2: Padroniza CPF na tabela customers para SOMENTE DÍGITOS
--   (resolve divergência entre "123.456.789-09" e "12345678909")
-- ---------------------------------------------------------------
UPDATE public.customers
SET cpf = regexp_replace(COALESCE(cpf,''), '\D', '', 'g')
WHERE cpf IS NOT NULL AND cpf ~ '\D';

-- ---------------------------------------------------------------
-- PASSO 3: Copia CPF dos metadados auth → customers quando faltando
-- ---------------------------------------------------------------
UPDATE public.customers c
SET cpf = regexp_replace(au.raw_user_meta_data->>'cpf', '\D', '', 'g')
FROM auth.users au
WHERE au.id = c.user_id
  AND (c.cpf IS NULL OR trim(c.cpf) = '')
  AND au.raw_user_meta_data->>'cpf' IS NOT NULL
  AND trim(au.raw_user_meta_data->>'cpf') <> '';

-- ---------------------------------------------------------------
-- PASSO 4: Recria a função RPC com SECURITY DEFINER
--   Acessa auth.users diretamente — não depende só da tabela customers
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_login_email(login_input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cpf_digits TEXT;
  v_login      TEXT;
  v_is_email   BOOLEAN;
  v_email      TEXT;
BEGIN
  v_login     := lower(trim(COALESCE(login_input, '')));
  v_cpf_digits:= regexp_replace(COALESCE(login_input, ''), '\D', '', 'g');
  v_is_email  := position('@' IN v_login) > 0;

  -- 1. E-mail exato em auth.users
  IF v_is_email THEN
    SELECT lower(trim(au.email)) INTO v_email
    FROM auth.users au
    WHERE lower(trim(au.email)) = v_login
    LIMIT 1;
    IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;
  END IF;

  -- Só continua se for CPF válido (11 dígitos)
  IF length(v_cpf_digits) <> 11 THEN RETURN NULL; END IF;

  -- 2. CPF nos metadados do auth.users
  SELECT lower(trim(au.email)) INTO v_email
  FROM auth.users au
  WHERE regexp_replace(COALESCE(au.raw_user_meta_data->>'cpf',''), '\D', '', 'g') = v_cpf_digits
  LIMIT 1;
  IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

  -- 3. CPF na tabela customers com user_id vinculado a auth.users
  SELECT lower(trim(au.email)) INTO v_email
  FROM public.customers c
  JOIN auth.users au ON au.id = c.user_id
  WHERE regexp_replace(COALESCE(c.cpf,''), '\D', '', 'g') = v_cpf_digits
  LIMIT 1;
  IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

  -- 4. CPF na tabela customers sem user_id (usa o e-mail do próprio registro)
  SELECT lower(trim(c.email)) INTO v_email
  FROM public.customers c
  WHERE regexp_replace(COALESCE(c.cpf,''), '\D', '', 'g') = v_cpf_digits
    AND c.email IS NOT NULL AND trim(c.email) <> ''
  LIMIT 1;
  IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.get_customer_login_email(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.get_customer_login_email(TEXT) TO anon, authenticated;

-- Alias legado aponta para a nova função
CREATE OR REPLACE FUNCTION public.get_customer_email_by_cpf(cpf_input TEXT)
RETURNS TEXT LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$ SELECT public.get_customer_login_email(cpf_input); $$;

REVOKE ALL ON FUNCTION public.get_customer_email_by_cpf(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.get_customer_email_by_cpf(TEXT) TO anon, authenticated;

-- ---------------------------------------------------------------
-- PASSO 5: Testa a função com CPF real de um cliente
--   Substitua '00000000000' pelo CPF de um cliente cadastrado
-- ---------------------------------------------------------------
-- SELECT public.get_customer_login_email('00000000000');
-- SELECT public.get_customer_login_email('000.000.000-00');

-- ---------------------------------------------------------------
-- PASSO 6: Conferir estado final
-- ---------------------------------------------------------------
SELECT id, name, email, cpf,
  CASE WHEN user_id IS NOT NULL THEN 'vinculado' ELSE 'SEM user_id!' END AS status
FROM public.customers
WHERE cpf IS NOT NULL AND cpf <> ''
ORDER BY id DESC LIMIT 20;
