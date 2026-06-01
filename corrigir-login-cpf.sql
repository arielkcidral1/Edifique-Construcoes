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
