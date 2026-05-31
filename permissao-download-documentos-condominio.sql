DROP POLICY IF EXISTS "Assigned customers can read condominium documents storage"
ON storage.objects;

DROP POLICY IF EXISTS "Authenticated users can sign condominium documents downloads"
ON storage.objects;

DROP POLICY IF EXISTS "Public can read condominium documents storage"
ON storage.objects;

INSERT INTO storage.buckets (id, name, public)
VALUES ('condominium-documents', 'condominium-documents', true)
ON CONFLICT (id) DO UPDATE
SET
  name = EXCLUDED.name,
  public = true;

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('portfolio', 'portfolio', true),
  ('condominium_documents', 'condominium_documents', true),
  ('documents', 'documents', true),
  ('docs', 'docs', true)
ON CONFLICT (id) DO UPDATE
SET
  name = EXCLUDED.name,
  public = true;

UPDATE storage.buckets
SET public = true
WHERE id = 'condominium-documents';

CREATE POLICY "Public can read condominium documents storage"
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (
  bucket_id IN ('portfolio', 'condominium-documents', 'condominium_documents', 'documents', 'docs')
);

SELECT id, name, public
FROM storage.buckets
WHERE id IN ('portfolio', 'condominium-documents', 'condominium_documents', 'documents', 'docs')
ORDER BY id;
