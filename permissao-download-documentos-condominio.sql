DROP POLICY IF EXISTS "Assigned customers can read condominium documents storage"
ON storage.objects;

DROP POLICY IF EXISTS "Authenticated users can sign condominium documents downloads"
ON storage.objects;

CREATE POLICY "Authenticated users can sign condominium documents downloads"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'condominium-documents'
);
