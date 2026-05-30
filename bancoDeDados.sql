CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE IF NOT EXISTS public.customers (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT,
  cpf TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS cpf TEXT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS customers_user_id_key
  ON public.customers(user_id)
  WHERE user_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.projects (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  start_date DATE,
  end_date DATE
);

CREATE TABLE IF NOT EXISTS public.project_photos (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  project_id BIGINT REFERENCES public.projects(id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL,
  uploaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS project_photos_project_id_idx
  ON public.project_photos(project_id);

CREATE TABLE IF NOT EXISTS public.reviews (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id BIGINT REFERENCES public.customers(id) ON DELETE CASCADE,
  project_id BIGINT REFERENCES public.projects(id) ON DELETE CASCADE,
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS reviews_customer_id_idx
  ON public.reviews(customer_id);

CREATE INDEX IF NOT EXISTS reviews_project_id_idx
  ON public.reviews(project_id);

CREATE OR REPLACE FUNCTION private.handle_new_user_customer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.customers (user_id, name, email, cpf, phone)
  VALUES (
    NEW.id,
    COALESCE(NULLIF(NEW.raw_user_meta_data ->> 'name', ''), NEW.email, 'Cliente'),
    COALESCE(NEW.email, ''),
    NULLIF(NEW.raw_user_meta_data ->> 'cpf', ''),
    NULLIF(NEW.raw_user_meta_data ->> 'phone', '')
  )
  ON CONFLICT (email) DO UPDATE SET
    user_id = COALESCE(public.customers.user_id, EXCLUDED.user_id),
    name = EXCLUDED.name,
    cpf = COALESCE(EXCLUDED.cpf, public.customers.cpf),
    phone = COALESCE(EXCLUDED.phone, public.customers.phone);

  RETURN NEW;
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

INSERT INTO public.customers (user_id, name, email, cpf, phone)
SELECT
  users.id,
  COALESCE(NULLIF(users.raw_user_meta_data ->> 'name', ''), users.email, 'Cliente'),
  COALESCE(users.email, ''),
  NULLIF(users.raw_user_meta_data ->> 'cpf', ''),
  NULLIF(users.raw_user_meta_data ->> 'phone', '')
FROM auth.users
WHERE users.email IS NOT NULL
ON CONFLICT (email) DO UPDATE SET
  user_id = COALESCE(public.customers.user_id, EXCLUDED.user_id),
  name = EXCLUDED.name,
  cpf = COALESCE(EXCLUDED.cpf, public.customers.cpf),
  phone = COALESCE(EXCLUDED.phone, public.customers.phone);

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.customers FROM anon, authenticated;
REVOKE ALL ON TABLE public.projects FROM anon, authenticated;
REVOKE ALL ON TABLE public.project_photos FROM anon, authenticated;
REVOKE ALL ON TABLE public.reviews FROM anon, authenticated;

GRANT SELECT ON TABLE public.projects TO anon, authenticated;
GRANT SELECT ON TABLE public.project_photos TO anon, authenticated;
GRANT SELECT ON TABLE public.reviews TO anon, authenticated;
GRANT SELECT ON TABLE public.customers TO authenticated;
GRANT INSERT ON TABLE public.reviews TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE public.projects TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE public.project_photos TO authenticated;
GRANT DELETE ON TABLE public.reviews TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

DROP POLICY IF EXISTS "Customers can view their own profile" ON public.customers;
DROP POLICY IF EXISTS "Public projects are readable" ON public.projects;
DROP POLICY IF EXISTS "Admins can manage projects" ON public.projects;
DROP POLICY IF EXISTS "Admins can insert projects" ON public.projects;
DROP POLICY IF EXISTS "Admins can update projects" ON public.projects;
DROP POLICY IF EXISTS "Admins can delete projects" ON public.projects;
DROP POLICY IF EXISTS "Public project photos are readable" ON public.project_photos;
DROP POLICY IF EXISTS "Admins can manage project photos" ON public.project_photos;
DROP POLICY IF EXISTS "Admins can insert project photos" ON public.project_photos;
DROP POLICY IF EXISTS "Admins can update project photos" ON public.project_photos;
DROP POLICY IF EXISTS "Admins can delete project photos" ON public.project_photos;
DROP POLICY IF EXISTS "Public reviews are readable" ON public.reviews;
DROP POLICY IF EXISTS "Authenticated users can create reviews" ON public.reviews;
DROP POLICY IF EXISTS "Admins can delete reviews" ON public.reviews;

CREATE POLICY "Customers can view their own profile"
ON public.customers
FOR SELECT
TO authenticated
USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Public projects are readable"
ON public.projects
FOR SELECT
TO anon, authenticated
USING (true);

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

CREATE POLICY "Authenticated users can create reviews"
ON public.reviews
FOR INSERT
TO authenticated
WITH CHECK (rating BETWEEN 1 AND 5);

CREATE POLICY "Admins can delete reviews"
ON public.reviews
FOR DELETE
TO authenticated
USING (((SELECT auth.jwt()) ->> 'email') = 'admin@edifique.com');

INSERT INTO storage.buckets (id, name, public)
VALUES ('portfolio', 'portfolio', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

DROP POLICY IF EXISTS "Public portfolio photos are visible" ON storage.objects;
DROP POLICY IF EXISTS "Admins can upload portfolio photos" ON storage.objects;
DROP POLICY IF EXISTS "Admins can update portfolio photos" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete portfolio photos" ON storage.objects;

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
