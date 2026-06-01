CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE IF NOT EXISTS public.customers (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT,
  cpf TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS cpf TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS customers_user_id_key
  ON public.customers(user_id)
  WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS customers_cpf_digits_key
  ON public.customers ((regexp_replace(COALESCE(cpf, ''), '\D', '', 'g')))
  WHERE cpf IS NOT NULL AND regexp_replace(COALESCE(cpf, ''), '\D', '', 'g') <> '';

CREATE TABLE IF NOT EXISTS public.projects (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  start_date DATE,
  end_date DATE
);

CREATE TABLE IF NOT EXISTS public.condominiums (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS condominium_id BIGINT REFERENCES public.condominiums(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.customer_condominiums (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  condominium_id BIGINT NOT NULL REFERENCES public.condominiums(id) ON DELETE CASCADE,
  assigned_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (customer_id, condominium_id)
);

CREATE TABLE IF NOT EXISTS public.condominium_documents (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  condominium_id BIGINT NOT NULL REFERENCES public.condominiums(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  document_type TEXT NOT NULL,
  file_path TEXT NOT NULL,
  file_name TEXT,
  uploaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.project_photos (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  project_id BIGINT REFERENCES public.projects(id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL,
  uploaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS project_photos_project_id_idx
  ON public.project_photos(project_id);

CREATE INDEX IF NOT EXISTS projects_condominium_id_idx
  ON public.projects(condominium_id);

CREATE INDEX IF NOT EXISTS customer_condominiums_customer_id_idx
  ON public.customer_condominiums(customer_id);

CREATE INDEX IF NOT EXISTS customer_condominiums_condominium_id_idx
  ON public.customer_condominiums(condominium_id);

CREATE INDEX IF NOT EXISTS condominium_documents_condominium_id_idx
  ON public.condominium_documents(condominium_id);

CREATE TABLE IF NOT EXISTS public.reviews (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id BIGINT REFERENCES public.customers(id) ON DELETE CASCADE,
  project_id BIGINT REFERENCES public.projects(id) ON DELETE CASCADE,
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  reviewer_name TEXT,
  reviewer_avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS reviewer_name TEXT,
  ADD COLUMN IF NOT EXISTS reviewer_avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();

CREATE INDEX IF NOT EXISTS reviews_customer_id_idx
  ON public.reviews(customer_id);

CREATE INDEX IF NOT EXISTS reviews_project_id_idx
  ON public.reviews(project_id);

UPDATE public.reviews r
SET
  reviewer_name = COALESCE(NULLIF(r.reviewer_name, ''), c.name),
  reviewer_avatar_url = COALESCE(NULLIF(r.reviewer_avatar_url, ''), c.avatar_url)
FROM public.customers c
WHERE r.customer_id = c.id;

CREATE OR REPLACE FUNCTION private.handle_new_user_customer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.customers (user_id, name, email, cpf, phone, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NULLIF(NEW.raw_user_meta_data ->> 'name', ''), NEW.email, 'Cliente'),
    COALESCE(NEW.email, ''),
    NULLIF(NEW.raw_user_meta_data ->> 'cpf', ''),
    NULLIF(NEW.raw_user_meta_data ->> 'phone', ''),
    NULLIF(NEW.raw_user_meta_data ->> 'avatar_url', '')
  )
  ON CONFLICT (email) DO UPDATE SET
    user_id = COALESCE(public.customers.user_id, EXCLUDED.user_id),
    name = EXCLUDED.name,
    cpf = COALESCE(EXCLUDED.cpf, public.customers.cpf),
    phone = COALESCE(EXCLUDED.phone, public.customers.phone),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.customers.avatar_url);

  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'CPF ou e-mail já cadastrado.' USING ERRCODE = '23505';
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_create_customer ON auth.users;
CREATE TRIGGER on_auth_user_created_create_customer
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION private.handle_new_user_customer();

CREATE OR REPLACE FUNCTION private.confirm_new_user_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth
AS $$
BEGIN
  NEW.email_confirmed_at = COALESCE(NEW.email_confirmed_at, now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_confirm_email ON auth.users;
CREATE TRIGGER on_auth_user_created_confirm_email
BEFORE INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION private.confirm_new_user_email();

UPDATE auth.users
SET email_confirmed_at = COALESCE(email_confirmed_at, now())
WHERE email_confirmed_at IS NULL;

CREATE OR REPLACE FUNCTION public.get_customer_email_by_cpf(cpf_input TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT lower(trim(COALESCE(au.email, c.email)))
  FROM public.customers c
  LEFT JOIN auth.users au ON au.id = c.user_id
  WHERE regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = regexp_replace(COALESCE(cpf_input, ''), '\D', '', 'g')
    AND regexp_replace(COALESCE(cpf_input, ''), '\D', '', 'g') <> ''
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_customer_email_by_cpf(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.get_customer_email_by_cpf(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_customer_login_email(login_input TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT lower(trim(COALESCE(au.email, c.email)))
  FROM public.customers c
  LEFT JOIN auth.users au ON au.id = c.user_id
  WHERE (
      position('@' in COALESCE(login_input, '')) > 0
      AND (
        lower(trim(c.email)) = lower(trim(login_input))
        OR lower(trim(au.email)) = lower(trim(login_input))
      )
    )
    OR (
      position('@' in COALESCE(login_input, '')) = 0
      AND regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = regexp_replace(COALESCE(login_input, ''), '\D', '', 'g')
      AND regexp_replace(COALESCE(login_input, ''), '\D', '', 'g') <> ''
    )
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_customer_login_email(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.get_customer_login_email(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.upsert_customer_profile(
  name_input TEXT,
  email_input TEXT,
  cpf_input TEXT,
  phone_input TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := (SELECT auth.uid());
  current_email TEXT := (SELECT (auth.jwt()) ->> 'email');
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado.' USING ERRCODE = '42501';
  END IF;

  IF current_email IS NULL OR lower(current_email) <> lower(email_input) THEN
    RAISE EXCEPTION 'E-mail do cadastro não corresponde ao usuário autenticado.' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.customers (user_id, name, email, cpf, phone)
  VALUES (
    current_user_id,
    COALESCE(NULLIF(name_input, ''), email_input, 'Cliente'),
    email_input,
    NULLIF(cpf_input, ''),
    NULLIF(phone_input, '')
  )
  ON CONFLICT (email) DO UPDATE SET
    user_id = COALESCE(public.customers.user_id, EXCLUDED.user_id),
    name = EXCLUDED.name,
    cpf = COALESCE(EXCLUDED.cpf, public.customers.cpf),
    phone = COALESCE(EXCLUDED.phone, public.customers.phone);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_condominiums()
RETURNS TABLE (
  id BIGINT,
  name TEXT,
  address TEXT,
  notes TEXT,
  assigned_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT condo_result.id, condo_result.name, condo_result.address, condo_result.notes, condo_result.assigned_at
  FROM (
    SELECT DISTINCT ON (condo.id)
      condo.id,
      condo.name,
      condo.address,
      condo.notes,
      cc.assigned_at
    FROM public.customer_condominiums cc
    JOIN public.customers c ON c.id = cc.customer_id
    JOIN public.condominiums condo ON condo.id = cc.condominium_id
    WHERE (SELECT auth.uid()) IS NOT NULL
      AND (
        c.user_id = (SELECT auth.uid())
        OR lower(c.email) = lower(COALESCE((SELECT auth.jwt()) ->> 'email', ''))
      )
    ORDER BY condo.id, cc.assigned_at DESC
  ) condo_result
  ORDER BY condo_result.assigned_at DESC, condo_result.name ASC;
$$;

CREATE OR REPLACE FUNCTION private.can_read_condominium_document_storage(object_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.condominium_documents doc
    JOIN public.customer_condominiums cc ON cc.condominium_id = doc.condominium_id
    JOIN public.customers c ON c.id = cc.customer_id
    WHERE doc.file_path = object_name
      AND c.user_id = (SELECT auth.uid())
  );
$$;

DROP FUNCTION IF EXISTS public.admin_list_customers();

CREATE FUNCTION public.admin_list_customers()
RETURNS TABLE (
  id BIGINT,
  name TEXT,
  email TEXT,
  phone TEXT,
  cpf TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF ((SELECT auth.jwt()) ->> 'email') <> 'admin@edifique.com' THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT c.id, c.name, c.email, c.phone, c.cpf, c.avatar_url, c.created_at
  FROM public.customers c
  WHERE lower(c.email) <> 'admin@edifique.com'
    AND lower(c.name) <> lower('Admin Edifique')
    AND lower(c.name) <> lower('Administrador Edifique')
  ORDER BY c.created_at DESC NULLS LAST, c.id DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_customer(
  customer_id_input BIGINT,
  name_input TEXT,
  email_input TEXT,
  cpf_input TEXT,
  phone_input TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF ((SELECT auth.jwt()) ->> 'email') <> 'admin@edifique.com' THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.customers
    WHERE id = customer_id_input
      AND (
        lower(email) = 'admin@edifique.com'
        OR lower(name) IN ('admin edifique', 'administrador edifique')
      )
  ) THEN
    RAISE EXCEPTION 'O usuario administrador nao pode ser alterado.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.customers
  SET
    name = name_input,
    email = email_input,
    cpf = NULLIF(cpf_input, ''),
    phone = NULLIF(phone_input, '')
  WHERE id = customer_id_input;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_customer(customer_id_input BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF ((SELECT auth.jwt()) ->> 'email') <> 'admin@edifique.com' THEN
    RAISE EXCEPTION 'Acesso negado.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.customers
    WHERE id = customer_id_input
      AND (
        lower(email) = 'admin@edifique.com'
        OR lower(name) IN ('admin edifique', 'administrador edifique')
      )
  ) THEN
    RAISE EXCEPTION 'O usuario administrador nao pode ser apagado.' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.customers
  WHERE id = customer_id_input
    AND lower(email) <> 'admin@edifique.com'
    AND lower(name) NOT IN ('admin edifique', 'administrador edifique');
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_customer_profile(TEXT, TEXT, TEXT, TEXT) FROM public;
REVOKE ALL ON FUNCTION public.get_my_condominiums() FROM public;
REVOKE ALL ON FUNCTION public.admin_list_customers() FROM public;
REVOKE ALL ON FUNCTION public.admin_update_customer(BIGINT, TEXT, TEXT, TEXT, TEXT) FROM public;
REVOKE ALL ON FUNCTION public.admin_delete_customer(BIGINT) FROM public;

GRANT EXECUTE ON FUNCTION public.upsert_customer_profile(TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_condominiums() TO authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;
REVOKE ALL ON FUNCTION private.can_read_condominium_document_storage(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION private.can_read_condominium_document_storage(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_customers() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_customer(BIGINT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_customer(BIGINT) TO authenticated;

INSERT INTO public.customers (user_id, name, email, cpf, phone, avatar_url)
SELECT
  users.id,
  COALESCE(NULLIF(users.raw_user_meta_data ->> 'name', ''), users.email, 'Cliente'),
  COALESCE(users.email, ''),
  NULLIF(users.raw_user_meta_data ->> 'cpf', ''),
  NULLIF(users.raw_user_meta_data ->> 'phone', ''),
  NULLIF(users.raw_user_meta_data ->> 'avatar_url', '')
FROM auth.users
WHERE users.email IS NOT NULL
ON CONFLICT (email) DO UPDATE SET
  user_id = COALESCE(public.customers.user_id, EXCLUDED.user_id),
  name = EXCLUDED.name,
  cpf = COALESCE(EXCLUDED.cpf, public.customers.cpf),
  phone = COALESCE(EXCLUDED.phone, public.customers.phone),
  avatar_url = COALESCE(EXCLUDED.avatar_url, public.customers.avatar_url);

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.condominiums ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_condominiums ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.condominium_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.customers FROM anon, authenticated;
REVOKE ALL ON TABLE public.condominiums FROM anon, authenticated;
REVOKE ALL ON TABLE public.customer_condominiums FROM anon, authenticated;
REVOKE ALL ON TABLE public.condominium_documents FROM anon, authenticated;
REVOKE ALL ON TABLE public.projects FROM anon, authenticated;
REVOKE ALL ON TABLE public.project_photos FROM anon, authenticated;
REVOKE ALL ON TABLE public.reviews FROM anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.condominiums TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.customer_condominiums TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.condominium_documents TO authenticated;
GRANT SELECT ON TABLE public.projects TO anon, authenticated;
GRANT SELECT ON TABLE public.project_photos TO anon, authenticated;
GRANT SELECT ON TABLE public.reviews TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.customers TO authenticated;
GRANT INSERT, UPDATE ON TABLE public.reviews TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE public.projects TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE public.project_photos TO authenticated;
GRANT DELETE ON TABLE public.reviews TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.customers TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.projects TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.project_photos TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.reviews TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

DROP POLICY IF EXISTS "Customers can view their own profile" ON public.customers;
DROP POLICY IF EXISTS "Customers can insert their own profile" ON public.customers;
DROP POLICY IF EXISTS "Customers can update their own profile" ON public.customers;
DROP POLICY IF EXISTS "Admins can view customers" ON public.customers;
DROP POLICY IF EXISTS "Admins can update customers" ON public.customers;
DROP POLICY IF EXISTS "Admins can delete customers" ON public.customers;
DROP POLICY IF EXISTS "Admins have full access to customers" ON public.customers;
DROP POLICY IF EXISTS "Assigned customers can view condominiums" ON public.condominiums;
DROP POLICY IF EXISTS "Admins have full access to condominiums" ON public.condominiums;
DROP POLICY IF EXISTS "Assigned customers can view condominium links" ON public.customer_condominiums;
DROP POLICY IF EXISTS "Admins have full access to condominium links" ON public.customer_condominiums;
DROP POLICY IF EXISTS "Assigned customers can view condominium documents" ON public.condominium_documents;
DROP POLICY IF EXISTS "Admins have full access to condominium documents" ON public.condominium_documents;
DROP POLICY IF EXISTS "Public projects are readable" ON public.projects;
DROP POLICY IF EXISTS "Admins can manage projects" ON public.projects;
DROP POLICY IF EXISTS "Admins can insert projects" ON public.projects;
DROP POLICY IF EXISTS "Admins can update projects" ON public.projects;
DROP POLICY IF EXISTS "Admins can delete projects" ON public.projects;
DROP POLICY IF EXISTS "Admins have full access to projects" ON public.projects;
DROP POLICY IF EXISTS "Public project photos are readable" ON public.project_photos;
DROP POLICY IF EXISTS "Admins can manage project photos" ON public.project_photos;
DROP POLICY IF EXISTS "Admins can insert project photos" ON public.project_photos;
DROP POLICY IF EXISTS "Admins can update project photos" ON public.project_photos;
DROP POLICY IF EXISTS "Admins can delete project photos" ON public.project_photos;
DROP POLICY IF EXISTS "Admins have full access to project photos" ON public.project_photos;
DROP POLICY IF EXISTS "Public reviews are readable" ON public.reviews;
DROP POLICY IF EXISTS "Authenticated users can create reviews" ON public.reviews;
DROP POLICY IF EXISTS "Customers can update their own review identity" ON public.reviews;
DROP POLICY IF EXISTS "Admins can delete reviews" ON public.reviews;
DROP POLICY IF EXISTS "Admins have full access to reviews" ON public.reviews;

CREATE POLICY "Customers can view their own profile"
ON public.customers
FOR SELECT
TO authenticated
USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Customers can insert their own profile"
ON public.customers
FOR INSERT
TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Customers can update their own profile"
ON public.customers
FOR UPDATE
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

-- Admin tem acesso completo aos cadastros de clientes do site.
CREATE POLICY "Admins have full access to customers"
ON public.customers
FOR ALL
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can view customers"
ON public.customers
FOR SELECT
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can update customers"
ON public.customers
FOR UPDATE
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can delete customers"
ON public.customers
FOR DELETE
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Assigned customers can view condominiums"
ON public.condominiums
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.customer_condominiums cc
    JOIN public.customers c ON c.id = cc.customer_id
    WHERE cc.condominium_id = condominiums.id
      AND c.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY "Admins have full access to condominiums"
ON public.condominiums
FOR ALL
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Assigned customers can view condominium links"
ON public.customer_condominiums
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = customer_condominiums.customer_id
      AND c.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY "Admins have full access to condominium links"
ON public.customer_condominiums
FOR ALL
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Assigned customers can view condominium documents"
ON public.condominium_documents
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.customer_condominiums cc
    JOIN public.customers c ON c.id = cc.customer_id
    WHERE cc.condominium_id = condominium_documents.condominium_id
      AND c.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY "Admins have full access to condominium documents"
ON public.condominium_documents
FOR ALL
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Public projects are readable"
ON public.projects
FOR SELECT
TO anon, authenticated
USING (true);

CREATE POLICY "Admins have full access to projects"
ON public.projects
FOR ALL
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can insert projects"
ON public.projects
FOR INSERT
TO authenticated
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can update projects"
ON public.projects
FOR UPDATE
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can delete projects"
ON public.projects
FOR DELETE
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Public project photos are readable"
ON public.project_photos
FOR SELECT
TO anon, authenticated
USING (true);

CREATE POLICY "Admins have full access to project photos"
ON public.project_photos
FOR ALL
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can insert project photos"
ON public.project_photos
FOR INSERT
TO authenticated
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can update project photos"
ON public.project_photos
FOR UPDATE
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can delete project photos"
ON public.project_photos
FOR DELETE
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Public reviews are readable"
ON public.reviews
FOR SELECT
TO anon, authenticated
USING (true);

CREATE POLICY "Admins have full access to reviews"
ON public.reviews
FOR ALL
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Authenticated users can create reviews"
ON public.reviews
FOR INSERT
TO authenticated
WITH CHECK (
  rating BETWEEN 1 AND 5
  AND EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = customer_id
      AND c.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY "Customers can update their own review identity"
ON public.reviews
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = customer_id
      AND c.user_id = (SELECT auth.uid())
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = customer_id
      AND c.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY "Admins can delete reviews"
ON public.reviews
FOR DELETE
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

INSERT INTO storage.buckets (id, name, public)
VALUES ('portfolio', 'portfolio', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

INSERT INTO storage.buckets (id, name, public)
VALUES ('condominium-documents', 'condominium-documents', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

DROP POLICY IF EXISTS "Public portfolio photos are visible" ON storage.objects;
DROP POLICY IF EXISTS "Admins can upload portfolio photos" ON storage.objects;
DROP POLICY IF EXISTS "Admins can update portfolio photos" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete portfolio photos" ON storage.objects;
DROP POLICY IF EXISTS "Admins have full access to portfolio photos" ON storage.objects;
DROP POLICY IF EXISTS "Public avatars are visible" ON storage.objects;
DROP POLICY IF EXISTS "Customers can upload own avatars" ON storage.objects;
DROP POLICY IF EXISTS "Customers can update own avatars" ON storage.objects;
DROP POLICY IF EXISTS "Customers can delete own avatars" ON storage.objects;
DROP POLICY IF EXISTS "Admins have full access to condominium documents storage" ON storage.objects;
DROP POLICY IF EXISTS "Assigned customers can read condominium documents storage" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can sign condominium documents downloads" ON storage.objects;
DROP POLICY IF EXISTS "Public can read condominium documents storage" ON storage.objects;

CREATE POLICY "Admins have full access to portfolio photos"
ON storage.objects
FOR ALL
TO authenticated
USING (bucket_id = 'portfolio' AND ((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (bucket_id = 'portfolio' AND ((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can upload portfolio photos"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'portfolio' AND ((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can update portfolio photos"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'portfolio' AND ((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (bucket_id = 'portfolio' AND ((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Admins can delete portfolio photos"
ON storage.objects
FOR DELETE
TO authenticated
USING (bucket_id = 'portfolio' AND ((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Public avatars are visible"
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (bucket_id = 'avatars');

CREATE POLICY "Customers can upload own avatars"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);

CREATE POLICY "Customers can update own avatars"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
)
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);

CREATE POLICY "Customers can delete own avatars"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);

CREATE POLICY "Admins have full access to condominium documents storage"
ON storage.objects
FOR ALL
TO authenticated
USING (bucket_id = 'condominium-documents' AND ((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com')
WITH CHECK (bucket_id = 'condominium-documents' AND ((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

CREATE POLICY "Public can read condominium documents storage"
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (
  bucket_id IN ('portfolio', 'condominium-documents', 'condominium_documents', 'documents', 'docs')
);
