-- =====================================================================
-- FIX-CPF-LOGIN-V3.SQL — Correção com tratamento de duplicatas
-- Edifique Construções — Execute completo no SQL Editor do Supabase
-- =====================================================================

-- -------------------------------------------------------------------
-- PASSO 1 — Ver os duplicados (para entender o problema)
-- -------------------------------------------------------------------
SELECT
  regexp_replace(COALESCE(cpf, ''), '\D', '', 'g') AS cpf_digitos,
  COUNT(*) AS total,
  array_agg(id ORDER BY id)                         AS ids,
  array_agg(name ORDER BY id)                       AS nomes,
  array_agg(email ORDER BY id)                      AS emails,
  array_agg(cpf ORDER BY id)                        AS cpfs_raw,
  array_agg(user_id::text ORDER BY id)              AS user_ids
FROM public.customers
WHERE cpf IS NOT NULL AND cpf <> ''
GROUP BY regexp_replace(COALESCE(cpf, ''), '\D', '', 'g')
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------
-- PASSO 2 — Resolver duplicatas: mesclar no registro mais antigo
--   - Mantém o registro com menor id (mais antigo / mais completo)
--   - Transfere user_id do duplicado para o registro principal se ele não tiver
--   - Transfere customer_condominiums, reviews para o id principal
--   - Deleta o duplicado
-- -------------------------------------------------------------------
DO $$
DECLARE
  rec     RECORD;
  main_id BIGINT;
  dup_id  BIGINT;
BEGIN
  -- Itera sobre cada grupo de CPF duplicado
  FOR rec IN
    SELECT
      regexp_replace(COALESCE(cpf, ''), '\D', '', 'g') AS cpf_digits,
      array_agg(id ORDER BY
        CASE WHEN user_id IS NOT NULL THEN 0 ELSE 1 END,  -- prefere quem tem user_id
        id ASC                                              -- depois o mais antigo
      ) AS ids
    FROM public.customers
    WHERE cpf IS NOT NULL AND cpf <> ''
    GROUP BY regexp_replace(COALESCE(cpf, ''), '\D', '', 'g')
    HAVING COUNT(*) > 1
  LOOP
    main_id := rec.ids[1];  -- registro principal (fica)
    
    -- Para cada duplicado (do índice 2 em diante)
    FOR i IN 2 .. array_length(rec.ids, 1) LOOP
      dup_id := rec.ids[i];
      
      -- Transferir user_id se o principal não tiver
      UPDATE public.customers
      SET user_id = (SELECT user_id FROM public.customers WHERE id = dup_id)
      WHERE id = main_id
        AND user_id IS NULL
        AND (SELECT user_id FROM public.customers WHERE id = dup_id) IS NOT NULL;

      -- Reatribuir customer_condominiums do duplicado para o principal
      UPDATE public.customer_condominiums
      SET customer_id = main_id
      WHERE customer_id = dup_id
        AND NOT EXISTS (
          SELECT 1 FROM public.customer_condominiums
          WHERE customer_id = main_id
            AND condominium_id = (
              SELECT condominium_id FROM public.customer_condominiums
              WHERE customer_id = dup_id AND id = public.customer_condominiums.id
              LIMIT 1
            )
        );

      -- Reatribuir reviews do duplicado para o principal
      UPDATE public.reviews
      SET customer_id = main_id
      WHERE customer_id = dup_id;

      -- Deletar o duplicado
      DELETE FROM public.customer_condominiums WHERE customer_id = dup_id;
      DELETE FROM public.customers WHERE id = dup_id;

      RAISE NOTICE 'Duplicata resolvida: CPF %, manteve id=%, deletou id=%',
        rec.cpf_digits, main_id, dup_id;
    END LOOP;
  END LOOP;
END;
$$;

-- -------------------------------------------------------------------
-- PASSO 3 — Agora normaliza CPFs com segurança (sem duplicatas)
-- -------------------------------------------------------------------
UPDATE public.customers
SET cpf = regexp_replace(COALESCE(cpf, ''), '\D', '', 'g')
WHERE cpf IS NOT NULL
  AND cpf <> ''
  AND cpf !~ '^\d{11}$';

-- Zerar CPFs inválidos que sobraram
UPDATE public.customers
SET cpf = NULL
WHERE cpf IS NOT NULL
  AND (cpf = '' OR length(regexp_replace(cpf, '\D', '', 'g')) <> 11);

-- -------------------------------------------------------------------
-- PASSO 4 — Copiar CPF dos metadados auth → customers onde faltando
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
-- PASSO 5 — Vincular user_id em customers onde está faltando
-- -------------------------------------------------------------------
UPDATE public.customers c
SET user_id = au.id
FROM auth.users au
WHERE lower(trim(au.email)) = lower(trim(c.email))
  AND c.user_id IS NULL;

-- -------------------------------------------------------------------
-- PASSO 6 — Corrigir trigger handle_new_user_customer
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
  v_cpf := regexp_replace(
    COALESCE(NEW.raw_user_meta_data ->> 'cpf', ''), '\D', '', 'g'
  );
  IF v_cpf = '' OR length(v_cpf) <> 11 THEN v_cpf := NULL; END IF;

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
    UPDATE public.customers
    SET user_id = COALESCE(public.customers.user_id, NEW.id)
    WHERE lower(trim(email)) = lower(trim(COALESCE(NEW.email, '')));
    RETURN NEW;
END;
$$;

-- -------------------------------------------------------------------
-- PASSO 7 — Corrigir upsert_customer_profile (salva CPF normalizado)
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

  v_cpf := regexp_replace(COALESCE(cpf_input, ''), '\D', '', 'g');
  IF v_cpf = '' OR length(v_cpf) <> 11 THEN v_cpf := NULL; END IF;

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
-- PASSO 8 — Corrigir admin_update_customer (salva CPF normalizado)
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

  v_cpf := regexp_replace(COALESCE(cpf_input, ''), '\D', '', 'g');
  IF v_cpf = '' OR length(v_cpf) <> 11 THEN v_cpf := NULL; END IF;

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
-- PASSO 9 — Reescrever get_customer_login_email como plpgsql
-- -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_login_email(login_input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_login    TEXT    := lower(trim(COALESCE(login_input, '')));
  v_digits   TEXT    := regexp_replace(COALESCE(login_input, ''), '\D', '', 'g');
  v_is_email BOOLEAN := position('@' IN lower(trim(COALESCE(login_input, '')))) > 0;
  v_email    TEXT;
BEGIN
  -- ── E-MAIL ────────────────────────────────────────────────────────
  IF v_is_email THEN
    SELECT lower(trim(au.email)) INTO v_email
    FROM auth.users au
    WHERE lower(trim(au.email)) = v_login
    LIMIT 1;
    RETURN v_email;
  END IF;

  -- ── CPF ───────────────────────────────────────────────────────────
  IF length(v_digits) <> 11 THEN RETURN NULL; END IF;

  -- A: CPF nos metadados auth.users
  SELECT lower(trim(au.email)) INTO v_email
  FROM auth.users au
  WHERE regexp_replace(COALESCE(au.raw_user_meta_data->>'cpf', ''), '\D', '', 'g') = v_digits
    AND au.email IS NOT NULL AND trim(au.email) <> ''
  LIMIT 1;
  IF v_email IS NOT NULL THEN RETURN v_email; END IF;

  -- B: CPF em customers com user_id vinculado
  SELECT lower(trim(au.email)) INTO v_email
  FROM public.customers c
  JOIN auth.users au ON au.id = c.user_id
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
    AND au.email IS NOT NULL
  LIMIT 1;
  IF v_email IS NOT NULL THEN RETURN v_email; END IF;

  -- C: CPF em customers com JOIN por email
  SELECT lower(trim(au.email)) INTO v_email
  FROM public.customers c
  JOIN auth.users au ON lower(trim(au.email)) = lower(trim(c.email))
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = v_digits
    AND au.email IS NOT NULL
  LIMIT 1;
  IF v_email IS NOT NULL THEN RETURN v_email; END IF;

  -- D: CPF em customers sem auth (retorna email do cadastro)
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

NOTIFY pgrst, 'reload schema';

-- -------------------------------------------------------------------
-- PASSO 10 — Verificação final
-- -------------------------------------------------------------------
SELECT
  c.id,
  c.name,
  c.email,
  c.cpf,
  CASE WHEN c.cpf ~ '^\d{11}$' THEN '✅ ok'
       WHEN c.cpf IS NULL       THEN '⚠️  sem CPF'
       ELSE                          '❌ formato errado'
  END AS cpf_status,
  CASE WHEN c.user_id IS NOT NULL THEN '✅ ok' ELSE '❌ faltando' END AS user_id_status
FROM public.customers c
WHERE lower(c.email) <> 'admin@edifique.com'
ORDER BY c.id DESC;

-- Confirmar que não há mais duplicatas
SELECT
  regexp_replace(COALESCE(cpf, ''), '\D', '', 'g') AS cpf_digitos,
  COUNT(*) AS total
FROM public.customers
WHERE cpf IS NOT NULL AND cpf <> ''
GROUP BY regexp_replace(COALESCE(cpf, ''), '\D', '', 'g')
HAVING COUNT(*) > 1;
-- ^ deve retornar 0 linhas se tudo estiver certo