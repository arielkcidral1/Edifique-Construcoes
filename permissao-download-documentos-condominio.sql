DROP POLICY IF EXISTS "Assigned customers can read condominium documents storage"
ON storage.objects;

DROP POLICY IF EXISTS "Authenticated users can sign condominium documents downloads"
ON storage.objects;

DROP POLICY IF EXISTS "Public can read condominium documents storage"
ON storage.objects;

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
