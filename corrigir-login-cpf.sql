-- =====================================================================
-- FIX-CPF-LOGIN-V2.SQL — Reescrita completa e definitiva
-- Edifique Construções — Execute completo no SQL Editor do Supabase
-- =====================================================================
--
-- BUGS IDENTIFICADOS (raiz do problema):
--
-- BUG 1 — get_customer_login_email era LANGUAGE sql.
--   Em LANGUAGE sql o SECURITY DEFINER não garante acesso a auth.users
--   quando chamado por anon no Supabase moderno. Precisa ser plpgsql.
--
-- BUG 2 — CPF salvo com máscara (123.456.789-09) via ensureCustomerProfile
--   mas o índice único customers_cpf_digits_key indexa os dígitos puros.
--   Isso cria CONFLITO: se um cliente tem cpf='123.456.789-09' e outro
--   tenta cadastrar com '12345678909', o índice barra a inserção.
--   Solução: normalizar tudo para dígitos puros no banco.
--
-- BUG 3 — upsert_customer_profile usa formatCpf(cpf) para salvar,
--   mantendo a máscara. Isso significa que o cpf real no banco é
--   '123.456.789-09', não '12345678909'. A RPC de login faz regexp_replace
--   dos dois lados — deveria funcionar — mas o índice único conflita
--   com o formato diferente e pode silenciosamente NÃO salvar o cpf.
--
-- BUG 4 — Clientes cadastrados pelo admin via admin_update_customer
--   podem ter cpf NULL se o admin não preencheu, ou com qualquer formato.
--
-- SOLUÇÃO:
--   1. Normalizar TODOS os CPFs existentes para dígitos puros
--   2. Reescrever get_customer_login_email como plpgsql com SECURITY DEFINER
--   3. Corrigir handle_new_user_customer para salvar CPF normalizado
--   4. Corrigir upsert_customer_profile para salvar CPF normalizado
--   5. Corrigir admin_update_customer para salvar CPF normalizado
--   6. Vincular user_id nos registros customers que estão sem ele
-- =====================================================================

-- -------------------------------------------------------------------
-- PASSO 1 — Diagnóstico: estado atual (execute antes para ver o problema)
-- -------------------------------------------------------------------
SELECT
  c.id,
  c.name,
  c.email                                                            AS email_customer,
  c.cpf                                                              AS cpf_salvo,
  regexp_replace(COALESCE(c.cpf,''), '\D', '', 'g')                  AS cpf_digitos,
  c.user_id,
  au.email                                                           AS email_auth,
  regexp_replace(
    COALESCE(au.raw_user_meta_data->>'cpf',''), '\D', '', 'g'
  )                                                                  AS cpf_meta_digitos,
  CASE
    WHEN c.user_id IS NOT NULL                          THEN '✅ vinculado'
    WHEN au.id IS NOT NULL                              THEN '⚠️  sem user_id'
    ELSE                                                     '❌ sem auth'
  END AS status_vinculo,
  CASE
    WHEN c.cpf IS NULL OR c.cpf = ''                   THEN '❌ sem CPF'
    WHEN c.cpf ~ '^\d{11}$'                            THEN '✅ CPF normalizado'
    ELSE                                                     '⚠️  CPF com máscara'
  END AS status_cpf
FROM public.customers c
LEFT JOIN auth.users au ON lower(trim(au.email)) = lower(trim(c.email))
WHERE lower(c.email) <> 'admin@edifique.com'
ORDER BY c.id DESC
LIMIT 50;

-- -------------------------------------------------------------------
-- PASSO 2 — Normalizar TODOS os CPFs para apenas 11 dígitos
-- -------------------------------------------------------------------
UPDATE public.customers
SET cpf = regexp_replace(COALESCE(cpf, ''), '\D', '', 'g')
WHERE cpf IS NOT NULL
  AND cpf <> ''
  AND cpf !~ '^\d{11}$';   -- só atualiza se não for já 11 dígitos puros

-- Zerar CPFs que ficaram vazios ou inválidos após normalização
UPDATE public.customers
SET cpf = NULL
WHERE cpf IS NOT NULL
  AND regexp_replace(cpf, '\D', '', 'g') = '';

-- -------------------------------------------------------------------
-- PASSO 3 — Copiar CPF dos metadados auth → customers onde está faltando
-- -------------------------------------------------------------------
UPDATE public.customers c
SET cpf = regexp_replace(
            COALESCE(au.raw_user_meta_data->>'cpf', ''), '\D', '', 'g'
          )
FROM auth.users au
WHERE au.id = c.user_id
  AND (c.cpf IS NULL OR c.cpf = '')
  AND COALESCE(au.raw_user_meta_data->>'cpf', '') <> '';

-- -------------------------------------------------------------------
-- PASSO 4 — Vincular user_id em customers onde está faltando
-- -------------------------------------------------------------------
UPDATE public.customers c
SET user_id = au.id
FROM auth.users au
WHERE lower(trim(au.email)) = lower(trim(c.email))
  AND c.user_id IS NULL;

-- -------------------------------------------------------------------
-- PASSO 5 — Corrigir trigger handle_new_user_customer
--   Normaliza CPF para dígitos puros ANTES de inserir
-- -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.handle_new_user_customer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cpf TEXT;
BEGIN
  -- Normaliza CPF para apenas dígitos
  v_cpf := regexp_replace(
    COALESCE(NEW.raw_user_meta_data ->> 'cpf', ''), '\D', '', 'g'
  );
  IF v_cpf = '' THEN v_cpf := NULL; END IF;

  INSERT INTO public.customers (user_id, name, email, cpf, phone, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NULLIF(NEW.raw_user_meta_data ->> 'name', ''), NEW.email, 'Cliente'),
    COALESCE(NEW.email, ''),
    v_cpf,
    NULLIF(NEW.raw_user_meta_data ->> 'phone', ''),
    NULLIF(NEW.raw_user_meta_data ->> 'avatar_url', '')
  )
  ON CONFLICT (email) DO UPDATE SET
    user_id    = COALESCE(public.customers.user_id, EXCLUDED.user_id),
    name       = EXCLUDED.name,
    cpf        = COALESCE(EXCLUDED.cpf, public.customers.cpf),
    phone      = COALESCE(EXCLUDED.phone, public.customers.phone),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.customers.avatar_url);

  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    -- Conflito de CPF: atualiza user_id no registro existente
    UPDATE public.customers
    SET user_id = COALESCE(public.customers.user_id, NEW.id)
    WHERE lower(trim(email)) = lower(trim(COALESCE(NEW.email, '')));
    RETURN NEW;
END;
$$;

-- -------------------------------------------------------------------
-- PASSO 6 — Corrigir upsert_customer_profile
--   Salva CPF como dígitos puros, nunca com máscara
-- -------------------------------------------------------------------
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
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado.' USING ERRCODE = '42501';
  END IF;

  IF current_email IS NULL OR current_email <> lower(trim(email_input)) THEN
    RAISE EXCEPTION 'E-mail não corresponde ao usuário autenticado.' USING ERRCODE = '42501';
  END IF;

  -- Normaliza CPF para apenas dígitos
  v_cpf := regexp_replace(COALESCE(cpf_input, ''), '\D', '', 'g');
  IF v_cpf = '' THEN v_cpf := NULL; END IF;

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
    cpf     = COALESCE(EXCLUDED.cpf, public.customers.cpf),
    phone   = COALESCE(EXCLUDED.phone, public.customers.phone);
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_customer_profile(TEXT, TEXT, TEXT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.upsert_customer_profile(TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- -------------------------------------------------------------------
-- PASSO 7 — Corrigir admin_update_customer
--   Normaliza CPF para dígitos puros ao atualizar via painel admin
-- -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_customer(
  customer_id_input BIGINT,
  name_input        TEXT,
  email_input       TEXT,
  cpf_input         TEXT,
  phone_input       TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cpf TEXT;
BEGIN
  IF ((SELECT auth.jwt()) ->> 'email') <> 'admin@edifique.com' THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.customers
    WHERE id = customer_id_input
      AND (lower(email) = 'admin@edifique.com'
           OR lower(name) IN ('admin edifique', 'administrador edifique'))
  ) THEN
    RAISE EXCEPTION 'O usuário administrador não pode ser alterado.' USING ERRCODE = '42501';
  END IF;

  -- Normaliza CPF para apenas dígitos
  v_cpf := regexp_replace(COALESCE(cpf_input, ''), '\D', '', 'g');
  IF v_cpf = '' THEN v_cpf := NULL; END IF;

  UPDATE public.customers
  SET
    name  = name_input,
    email = email_input,
    cpf   = v_cpf,
    phone = NULLIF(phone_input, '')
  WHERE id = customer_id_input;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_customer(BIGINT, TEXT, TEXT, TEXT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_update_customer(BIGINT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- -------------------------------------------------------------------
-- PASSO 8 — Reescrever get_customer_login_email como plpgsql
--   LANGUAGE plpgsql + SECURITY DEFINER = acesso garantido a auth.users
--   mesmo quando chamada por anon (usuário não autenticado)
-- -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_login_email(login_input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_login    TEXT  := lower(trim(COALESCE(login_input, '')));
  v_digits   TEXT  := regexp_replace(COALESCE(login_input, ''), '\D', '', 'g');
  v_is_email BOOLEAN := position('@' IN lower(trim(COALESCE(login_input, '')))) > 0;
  v_email    TEXT;
BEGIN
  -- ── E-MAIL ────────────────────────────────────────────────────────
  IF v_is_email THEN
    -- Busca em auth.users (SECURITY DEFINER permite acesso mesmo de anon)
    SELECT lower(trim(au.email)) INTO v_email
    FROM auth.users au
    WHERE lower(trim(au.email)) = v_login
    LIMIT 1;
    RETURN v_email;
  END IF;

  -- ── CPF ───────────────────────────────────────────────────────────
  IF length(v_digits) <> 11 THEN RETURN NULL; END IF;

  -- Tentativa A: CPF nos metadados auth.users
  SELECT lower(trim(au.email)) INTO v_email
  FROM auth.users au
  WHERE regexp_replace(COALESCE(au.raw_user_meta_data->>'cpf', ''), '\D', '', 'g') = v_digits
    AND au.email IS NOT NULL AND trim(au.email) <> ''
  LIMIT 1;
  IF v_email IS NOT NULL THEN RETURN v_email; END IF;

  -- Tentativa B: CPF em customers com user_id vinculado → pega email de auth.users
  SELECT lower(trim(au.email)) INTO v_email
  FROM public.customers c
  JOIN auth.users au ON au.id = c.user_id
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
    AND au.email IS NOT NULL
  LIMIT 1;
  IF v_email IS NOT NULL THEN RETURN v_email; END IF;

  -- Tentativa C: CPF em customers com JOIN por email em auth.users (sem user_id)
  SELECT lower(trim(au.email)) INTO v_email
  FROM public.customers c
  JOIN auth.users au ON lower(trim(au.email)) = lower(trim(c.email))
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
    AND au.email IS NOT NULL
  LIMIT 1;
  IF v_email IS NOT NULL THEN RETURN v_email; END IF;

  -- Tentativa D: CPF em customers sem auth.users (retorna email do cadastro)
  SELECT lower(trim(c.email)) INTO v_email
  FROM public.customers c
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
    AND c.email IS NOT NULL AND trim(c.email) <> ''
  LIMIT 1;
  RETURN v_email;
END;
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

-- Recarrega o schema do PostgREST para expor as funções imediatamente
NOTIFY pgrst, 'reload schema';

-- -------------------------------------------------------------------
-- PASSO 9 — Verificação final
-- -------------------------------------------------------------------
-- 9a. Deve mostrar todos os clientes com CPF normalizado e user_id vinculado
SELECT
  c.id,
  c.name,
  c.email,
  c.cpf                                                        AS cpf_normalizado,
  CASE WHEN c.cpf ~ '^\d{11}$' THEN '✅ ok' ELSE '⚠️ inválido' END AS cpf_status,
  CASE WHEN c.user_id IS NOT NULL THEN '✅ ok' ELSE '❌ faltando' END AS user_id_status
FROM public.customers c
WHERE lower(c.email) <> 'admin@edifique.com'
ORDER BY c.id DESC;

-- 9b. Testar a função (substitua pelo CPF real de um cliente)
-- SELECT public.get_customer_login_email('12345678901');  -- só dígitos
-- SELECT public.get_customer_login_email('123.456.789-01');  -- com máscara