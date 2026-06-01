CREATE OR REPLACE FUNCTION public.get_customer_login_email(login_input TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH normalized AS (
    SELECT
      lower(trim(COALESCE(login_input, ''))) AS login,
      regexp_replace(COALESCE(login_input, ''), '\D', '', 'g') AS cpf_digits,
      position('@' in COALESCE(login_input, '')) > 0 AS is_email
  ),
  candidates AS (
    SELECT au.email, 1 AS priority
    FROM auth.users au
    CROSS JOIN normalized n
    WHERE n.is_email
      AND lower(trim(au.email)) = n.login

    UNION ALL

    SELECT au.email, 2 AS priority
    FROM auth.users au
    CROSS JOIN normalized n
    WHERE NOT n.is_email
      AND n.cpf_digits <> ''
      AND regexp_replace(COALESCE(au.raw_user_meta_data ->> 'cpf', ''), '\D', '', 'g') = n.cpf_digits

    UNION ALL

    SELECT au.email, 3 AS priority
    FROM public.customers c
    JOIN auth.users au ON au.id = c.user_id
    CROSS JOIN normalized n
    WHERE NOT n.is_email
      AND n.cpf_digits <> ''
      AND regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = n.cpf_digits

    UNION ALL

    SELECT au.email, 4 AS priority
    FROM public.customers c
    JOIN auth.users au ON lower(trim(au.email)) = lower(trim(c.email))
    CROSS JOIN normalized n
    WHERE NOT n.is_email
      AND n.cpf_digits <> ''
      AND regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = n.cpf_digits

    UNION ALL

    SELECT c.email, 5 AS priority
    FROM public.customers c
    CROSS JOIN normalized n
    WHERE (
        n.is_email
        AND lower(trim(c.email)) = n.login
      )
      OR (
        NOT n.is_email
        AND n.cpf_digits <> ''
        AND regexp_replace(COALESCE(c.cpf, ''), '\D', '', 'g') = n.cpf_digits
      )
  )
  SELECT lower(trim(email))
  FROM candidates
  WHERE email IS NOT NULL
    AND trim(email) <> ''
  ORDER BY priority
  LIMIT 1;
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

-- Depois de executar, teste com o CPF real:
-- SELECT public.get_customer_login_email('000.000.000-00');
