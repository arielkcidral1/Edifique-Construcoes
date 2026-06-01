-- =============================================================
-- DIAGNÓSTICO E CORREÇÃO — Login por CPF
-- Execute no SQL Editor do Supabase (Run All)
-- =============================================================

-- ---------------------------------------------------------------
-- 1. DIAGNÓSTICO: ver clientes e seus CPFs cadastrados
-- ---------------------------------------------------------------
SELECT
  c.id,
  c.name,
  c.email,
  c.cpf                                           AS cpf_na_tabela,
  regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') AS cpf_somente_digitos,
  au.raw_user_meta_data ->> 'cpf'                AS cpf_nos_metadados,
  c.user_id,
  au.id                                           AS auth_user_id
FROM public.customers c
LEFT JOIN auth.users au ON au.id = c.user_id
ORDER BY c.id DESC
LIMIT 30;

-- ---------------------------------------------------------------
-- 2. CORREÇÃO: padroniza o CPF na tabela customers para só dígitos
--    (evita incompatibilidade entre "000.000.000-00" e "00000000000")
-- ---------------------------------------------------------------
UPDATE public.customers
SET cpf = regexp_replace(COALESCE(cpf, ''), '\D', '', 'g')
WHERE cpf IS NOT NULL
  AND cpf ~ '\D';   -- só atualiza se tiver pontos, traços ou espaços

-- ---------------------------------------------------------------
-- 3. CORREÇÃO: copia CPF dos metadados auth → customers quando faltando
-- ---------------------------------------------------------------
UPDATE public.customers c
SET cpf = regexp_replace(au.raw_user_meta_data ->> 'cpf', '\D', '', 'g')
FROM auth.users au
WHERE au.id = c.user_id
  AND (c.cpf IS NULL OR trim(c.cpf) = '')
  AND au.raw_user_meta_data ->> 'cpf' IS NOT NULL
  AND trim(au.raw_user_meta_data ->> 'cpf') <> '';

-- ---------------------------------------------------------------
-- 4. Garante que a função RPC está correta e recebe CPF em qualquer formato
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_login_email(login_input TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH normalized AS (
    SELECT
      lower(trim(COALESCE(login_input, '')))                   AS login,
      regexp_replace(COALESCE(login_input, ''), '\D', '', 'g') AS cpf_digits,
      position('@' IN COALESCE(login_input, '')) > 0           AS is_email
  ),
  candidates AS (

    -- Prioridade 1: e-mail exato em auth.users
    SELECT au.email, 1 AS priority
    FROM auth.users au
    CROSS JOIN normalized n
    WHERE n.is_email
      AND lower(trim(au.email)) = n.login

    UNION ALL

    -- Prioridade 2: CPF nos metadados do usuário (raw_user_meta_data)
    SELECT au.email, 2 AS priority
    FROM auth.users au
    CROSS JOIN normalized n
    WHERE NOT n.is_email
      AND n.cpf_digits <> ''
      AND length(n.cpf_digits) = 11
      AND regexp_replace(
            COALESCE(au.raw_user_meta_data ->> 'cpf', ''),
            '\D', '', 'g'
          ) = n.cpf_digits

    UNION ALL

    -- Prioridade 3: CPF na tabela customers com user_id vinculado
    SELECT au.email, 3 AS priority
    FROM public.customers c
    JOIN auth.users au ON au.id = c.user_id
    CROSS JOIN normalized n
    WHERE NOT n.is_email
      AND n.cpf_digits <> ''
      AND length(n.cpf_digits) = 11
      AND regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = n.cpf_digits

    UNION ALL

    -- Prioridade 4: CPF na tabela customers, e-mail pelo registro
    SELECT c.email, 4 AS priority
    FROM public.customers c
    CROSS JOIN normalized n
    WHERE NOT n.is_email
      AND n.cpf_digits <> ''
      AND length(n.cpf_digits) = 11
      AND regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = n.cpf_digits
      AND c.email IS NOT NULL
      AND trim(c.email) <> ''

    UNION ALL

    -- Prioridade 5: e-mail exato na tabela customers (fallback)
    SELECT c.email, 5 AS priority
    FROM public.customers c
    CROSS JOIN normalized n
    WHERE n.is_email
      AND lower(trim(c.email)) = n.login

  )
  SELECT lower(trim(email))
  FROM candidates
  WHERE email IS NOT NULL
    AND trim(email) <> ''
  ORDER BY priority
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_customer_login_email(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.get_customer_login_email(TEXT) TO anon, authenticated;

-- Alias legado
CREATE OR REPLACE FUNCTION public.get_customer_email_by_cpf(cpf_input TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_customer_login_email(cpf_input);
$$;

REVOKE ALL ON FUNCTION public.get_customer_email_by_cpf(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.get_customer_email_by_cpf(TEXT) TO anon, authenticated;

-- ---------------------------------------------------------------
-- 5. TESTE — substitua pelo CPF real de um cliente e verifique o retorno
-- ---------------------------------------------------------------
-- SELECT public.get_customer_login_email('00000000000');   -- só dígitos
-- SELECT public.get_customer_login_email('000.000.000-00'); -- formatado

-- ---------------------------------------------------------------
-- 6. Conferir resultado final
-- ---------------------------------------------------------------
SELECT id, name, email, cpf FROM public.customers
WHERE cpf IS NOT NULL AND cpf <> ''
ORDER BY id DESC
LIMIT 20;
