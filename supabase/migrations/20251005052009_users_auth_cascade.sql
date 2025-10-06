DELETE FROM public.users u
  WHERE NOT EXISTS (
  SELECT 1 FROM auth.users au WHERE au.id = u.id
);

DO $$
BEGIN
IF NOT EXISTS (
  SELECT 1 FROM pg_constraint WHERE conname = 'users_auth_fk'
) THEN
ALTER TABLE public.users
ADD CONSTRAINT users_auth_fk
FOREIGN KEY (id) REFERENCES auth.users(id)
ON DELETE CASCADE;
END IF;
END $$;