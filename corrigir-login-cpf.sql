-- =====================================================================
-- FIX-CPF-LOGIN.SQL — Correção definitiva do login por CPF
-- Edifique Construções — Execute completo no SQL Editor do Supabase
-- =====================================================================
-- PROBLEMA RAIZ:
--   1. A RPC get_customer_login_email é LANGUAGE sql sem acesso garantido
--      a auth.users quando chamada por anon (role anon não acessa auth.*).
--   2. Clientes cadastrados pelo admin podem ter CPF somente na tabela
--      customers sem user_id vinculado, e a RLS bloqueia SELECT para anon.
--   3. CPF pode estar salvo com máscara (123.456.789-09) ou só dígitos.
-- SOLUÇÃO:
--   - Nova RPC find_email_by_cpf_digits com SECURITY DEFINER que contorna
--     RLS e acessa auth.users diretamente (acesso garantido mesmo para anon).
--   - Reescrita da get_customer_login_email como LANGUAGE plpgsql robusta.
--   - Normalização do CPF na tabela customers para apenas dígitos.
--   - Vinculação user_id em customers quando possível.
-- =====================================================================

-- -------------------------------------------------------------------
-- PASSO 1 — Diagnóstico: ver estado atual de cada cliente
-- -------------------------------------------------------------------
SELECT
  c.id,
  c.name,
  c.email                                                    AS email_customers,
  c.cpf                                                      AS cpf_raw,
  regexp_replace(COALESCE(c.cpf,''), '\D', '', 'g')          AS cpf_digitos,
  c.user_id,
  au.email                                                   AS email_auth,
  au.raw_user_meta_data->>'cpf'                              AS cpf_meta_raw,
  regexp_replace(
    COALESCE(au.raw_user_meta_data->>'cpf',''), '\D', '', 'g'
  )                                                          AS cpf_meta_digitos,
  CASE
    WHEN c.user_id IS NOT NULL THEN 'OK — vinculado'
    WHEN au.id IS NOT NULL     THEN 'AVISO — auth existe, user_id ausente'
    ELSE                            'ERRO — sem auth.users'
  END AS status
FROM public.customers c
LEFT JOIN auth.users au
       ON lower(trim(au.email)) = lower(trim(c.email))
ORDER BY c.id DESC
LIMIT 50;

-- -------------------------------------------------------------------
-- PASSO 2 — Normaliza CPF na tabela customers para SOMENTE DÍGITOS
-- -------------------------------------------------------------------
UPDATE public.customers
SET cpf = regexp_replace(COALESCE(cpf, ''), '\D', '', 'g')
WHERE cpf IS NOT NULL
  AND cpf ~ '\D';   -- só atualiza se tiver caracteres não-dígitos

-- -------------------------------------------------------------------
-- PASSO 3 — Preenche CPF faltando em customers com dado do auth.users
-- -------------------------------------------------------------------
UPDATE public.customers c
SET cpf = regexp_replace(
            COALESCE(au.raw_user_meta_data->>'cpf', ''), '\D', '', 'g'
          )
FROM auth.users au
WHERE au.id = c.user_id
  AND (c.cpf IS NULL OR trim(c.cpf) = '')
  AND au.raw_user_meta_data->>'cpf' IS NOT NULL
  AND trim(au.raw_user_meta_data->>'cpf') <> '';

-- -------------------------------------------------------------------
-- PASSO 4 — Vincula user_id em customers quando está faltando
-- -------------------------------------------------------------------
UPDATE public.customers c
SET user_id = au.id
FROM auth.users au
WHERE lower(trim(au.email)) = lower(trim(c.email))
  AND c.user_id IS NULL
  AND au.id IS NOT NULL;

-- -------------------------------------------------------------------
-- PASSO 5 — Nova RPC simples e direta: find_email_by_cpf_digits
--   SECURITY DEFINER → acessa auth.users sem precisar de permissão anon
--   Usada como fallback extra no script.js
-- -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.find_email_by_cpf_digits(cpf_digits_input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_digits TEXT;
  v_email  TEXT;
BEGIN
  -- Normaliza: remove tudo que não é dígito
  v_digits := regexp_replace(COALESCE(cpf_digits_input, ''), '\D', '', 'g');

  IF length(v_digits) <> 11 THEN
    RETURN NULL;
  END IF;

  -- Busca 1: CPF nos metadados do auth.users (SECURITY DEFINER permite acesso)
  SELECT lower(trim(au.email)) INTO v_email
  FROM auth.users au
  WHERE regexp_replace(
          COALESCE(au.raw_user_meta_data->>'cpf', ''), '\D', '', 'g'
        ) = v_digits
    AND au.email IS NOT NULL
    AND trim(au.email) <> ''
  LIMIT 1;
  IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

  -- Busca 2: CPF na tabela customers com user_id → pega email do auth.users
  SELECT lower(trim(au.email)) INTO v_email
  FROM public.customers c
  JOIN auth.users au ON au.id = c.user_id
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
    AND au.email IS NOT NULL
  LIMIT 1;
  IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

  -- Busca 3: CPF na tabela customers sem user_id → usa email do próprio registro
  SELECT lower(trim(c.email)) INTO v_email
  FROM public.customers c
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
    AND c.email IS NOT NULL
    AND trim(c.email) <> ''
  LIMIT 1;
  IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL  ON FUNCTION public.find_email_by_cpf_digits(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.find_email_by_cpf_digits(TEXT) TO anon, authenticated;

-- -------------------------------------------------------------------
-- PASSO 6 — Reescreve get_customer_login_email como plpgsql robusto
--   Mantém compatibilidade com o script.js existente
-- -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_login_email(login_input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_login      TEXT;
  v_digits     TEXT;
  v_is_email   BOOLEAN;
  v_email      TEXT;
BEGIN
  v_login    := lower(trim(COALESCE(login_input, '')));
  v_digits   := regexp_replace(COALESCE(login_input, ''), '\D', '', 'g');
  v_is_email := position('@' IN v_login) > 0;

  -- 1. É e-mail → busca direto em auth.users
  IF v_is_email THEN
    SELECT lower(trim(au.email)) INTO v_email
    FROM auth.users au
    WHERE lower(trim(au.email)) = v_login
    LIMIT 1;
    IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

    -- fallback: busca em customers pelo email
    SELECT lower(trim(c.email)) INTO v_email
    FROM public.customers c
    WHERE lower(trim(c.email)) = v_login
    LIMIT 1;
    RETURN v_email;
  END IF;

  -- 2. Não é e-mail → trata como CPF
  IF length(v_digits) <> 11 THEN RETURN NULL; END IF;

  -- 2a. CPF nos metadados do auth.users
  SELECT lower(trim(au.email)) INTO v_email
  FROM auth.users au
  WHERE regexp_replace(
          COALESCE(au.raw_user_meta_data->>'cpf', ''), '\D', '', 'g'
        ) = v_digits
  LIMIT 1;
  IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

  -- 2b. CPF em customers com user_id vinculado
  SELECT lower(trim(au.email)) INTO v_email
  FROM public.customers c
  JOIN auth.users au ON au.id = c.user_id
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
  LIMIT 1;
  IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

  -- 2c. CPF em customers via JOIN por email (sem user_id)
  SELECT lower(trim(au.email)) INTO v_email
  FROM public.customers c
  JOIN auth.users au ON lower(trim(au.email)) = lower(trim(c.email))
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
  LIMIT 1;
  IF v_email IS NOT NULL AND v_email <> '' THEN RETURN v_email; END IF;

  -- 2d. CPF em customers sem auth.users (retorna email do próprio cadastro)
  SELECT lower(trim(c.email)) INTO v_email
  FROM public.customers c
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
    AND c.email IS NOT NULL
    AND trim(c.email) <> ''
  LIMIT 1;
  RETURN v_email;
END;
$$;

REVOKE ALL  ON FUNCTION public.get_customer_login_email(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.get_customer_login_email(TEXT) TO anon, authenticated;

-- Alias legado aponta para a mesma lógica
CREATE OR REPLACE FUNCTION public.get_customer_email_by_cpf(cpf_input TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_customer_login_email(cpf_input);
$$;

REVOKE ALL  ON FUNCTION public.get_customer_email_by_cpf(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.get_customer_email_by_cpf(TEXT) TO anon, authenticated;

-- Recarrega o schema do PostgREST para expor as novas funções imediatamente
NOTIFY pgrst, 'reload schema';

-- -------------------------------------------------------------------
-- PASSO 7 — Verificação final
-- -------------------------------------------------------------------

-- 7a. Conferir clientes com CPF preenchido e status de vínculo
SELECT
  c.id,
  c.name,
  c.email,
  c.cpf                                                    AS cpf_normalizado,
  CASE
    WHEN c.user_id IS NOT NULL THEN 'OK'
    ELSE 'SEM user_id'
  END AS vinculo
FROM public.customers c
WHERE c.cpf IS NOT NULL AND c.cpf <> ''
ORDER BY c.id DESC
LIMIT 30;

-- 7b. Testar as funções manualmente (substitua pelo CPF de um cliente real)
-- SELECT public.get_customer_login_email('00000000000');
-- SELECT public.get_customer_login_email('000.000.000-00');
-- SELECT public.find_email_by_cpf_digits('00000000000');