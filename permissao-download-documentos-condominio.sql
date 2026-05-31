DROP POLICY IF EXISTS "Assigned customers can read condominium documents storage"
ON storage.objects;

DROP POLICY IF EXISTS "Authenticated users can sign condominium documents downloads"
ON storage.objects;

DROP POLICY IF EXISTS "Public can read condominium documents storage"
ON storage.objects;

INSERT INTO storage.buckets (id, name, public)
VALUES ('condominium-documents', 'condominium-documents', true)
ON CONFLICT (id) DO UPDATE SET public = true;

UPDATE storage.buckets
SET public = true
WHERE id = 'condominium-documents';

CREATE POLICY "Public can read condominium documents storage"
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (
  bucket_id = 'condominium-documents'
);
