-- =============================================================
-- FIX LOGIN CPF — Edifique Construções
-- Execute no SQL Editor do Supabase (Run All)
-- =============================================================

-- 1. Garante que a função get_customer_login_email existe e está correta
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

-- 2. Alias legado
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

-- 3. Sincroniza CPF dos metadados do auth para a tabela customers
UPDATE public.customers c
SET cpf = regexp_replace(au.raw_user_meta_data ->> 'cpf', '\D', '', 'g')
FROM auth.users au
WHERE au.id = c.user_id
  AND (c.cpf IS NULL OR trim(c.cpf) = '')
  AND au.raw_user_meta_data ->> 'cpf' IS NOT NULL
  AND trim(au.raw_user_meta_data ->> 'cpf') <> '';

-- 4. Garante que todos os auth.users têm entrada na tabela customers
INSERT INTO public.customers (user_id, name, email, cpf, phone)
SELECT
  au.id,
  COALESCE(NULLIF(trim(au.raw_user_meta_data ->> 'name'), ''), au.email, 'Cliente'),
  COALESCE(au.email, ''),
  NULLIF(regexp_replace(COALESCE(au.raw_user_meta_data ->> 'cpf', ''), '\D', '', 'g'), ''),
  NULLIF(trim(au.raw_user_meta_data ->> 'phone'), '')
FROM auth.users au
WHERE au.email IS NOT NULL
  AND lower(au.email) <> 'admin@edifique.com'
ON CONFLICT (email) DO UPDATE SET
  user_id = COALESCE(public.customers.user_id, EXCLUDED.user_id),
  name    = CASE
              WHEN public.customers.name IS NULL
                OR public.customers.name = ''
                OR public.customers.name = public.customers.email
              THEN EXCLUDED.name
              ELSE public.customers.name
            END,
  cpf     = COALESCE(EXCLUDED.cpf, public.customers.cpf),
  phone   = COALESCE(EXCLUDED.phone, public.customers.phone);

-- 5. Teste — substitua pelo CPF real de um cliente
-- SELECT public.get_customer_login_email('00000000000');
-- SELECT public.get_customer_login_email('000.000.000-00');

-- 6. Mostra todos os clientes com CPF para conferir
SELECT id, name, email, cpf FROM public.customers WHERE cpf IS NOT NULL ORDER BY id DESC LIMIT 20;
