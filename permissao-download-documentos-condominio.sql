DROP POLICY IF EXISTS "Assigned customers can read condominium documents storage"
ON storage.objects;

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

GRANT USAGE ON SCHEMA private TO authenticated;
REVOKE ALL ON FUNCTION private.can_read_condominium_document_storage(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION private.can_read_condominium_document_storage(TEXT) TO authenticated;

CREATE POLICY "Assigned customers can read condominium documents storage"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'condominium-documents'
  AND private.can_read_condominium_document_storage(storage.objects.name)
);
