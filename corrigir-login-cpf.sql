-- =============================================================
-- CORREÇÃO: Login por CPF — Edifique Construções
-- Execute este arquivo no SQL Editor do Supabase (Run All)
-- =============================================================

-- 1. Função principal: busca e-mail pelo CPF em múltiplas fontes
--    Prioridade: auth.users (metadados) > customers (tabela) > email direto
CREATE OR REPLACE FUNCTION public.get_customer_login_email(login_input TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH normalized AS (
    SELECT
      lower(trim(COALESCE(login_input, '')))                         AS login,
      regexp_replace(COALESCE(login_input, ''), '\D', '', 'g')       AS cpf_digits,
      position('@' IN COALESCE(login_input, '')) > 0                 AS is_email
  ),
  candidates AS (

    -- Prioridade 1: email exato em auth.users
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

    -- Prioridade 4: CPF na tabela customers, e-mail buscado pelo registro
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

    -- Prioridade 5: email exato na tabela customers (fallback)
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

-- 2. Mantém compatibilidade com a função antiga (usada como fallback no JS)
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
--    (corrige clientes que se cadastraram antes da tabela customers existir)
UPDATE public.customers c
SET cpf = COALESCE(
            NULLIF(trim(au.raw_user_meta_data ->> 'cpf'), ''),
            c.cpf
          )
FROM auth.users au
WHERE au.id = c.user_id
  AND c.cpf IS NULL
  AND au.raw_user_meta_data ->> 'cpf' IS NOT NULL
  AND trim(au.raw_user_meta_data ->> 'cpf') <> '';

-- 4. Garante que todos os usuários auth têm entrada na tabela customers
INSERT INTO public.customers (user_id, name, email, cpf, phone)
SELECT
  au.id,
  COALESCE(NULLIF(au.raw_user_meta_data ->> 'name', ''), au.email, 'Cliente'),
  COALESCE(au.email, ''),
  NULLIF(trim(au.raw_user_meta_data ->> 'cpf'), ''),
  NULLIF(trim(au.raw_user_meta_data ->> 'phone'), '')
FROM auth.users au
WHERE au.email IS NOT NULL
  AND au.email <> 'admin@edifique.com'
ON CONFLICT (email) DO UPDATE SET
  user_id = COALESCE(public.customers.user_id, EXCLUDED.user_id),
  name    = CASE
              WHEN public.customers.name IS NULL OR public.customers.name = '' OR public.customers.name = public.customers.email
              THEN EXCLUDED.name
              ELSE public.customers.name
            END,
  cpf     = COALESCE(EXCLUDED.cpf, public.customers.cpf),
  phone   = COALESCE(EXCLUDED.phone, public.customers.phone);

-- =============================================================
-- TESTE: substitua pelo CPF real de um cliente cadastrado
-- SELECT public.get_customer_login_email('000.000.000-00');
-- SELECT public.get_customer_login_email('00000000000');
-- =============================================================
