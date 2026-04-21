-- Night Express — Admin access setup
-- À exécuter une seule fois dans Supabase SQL Editor
-- (Dashboard Supabase > SQL Editor > New query > coller > Run)

-- 1) S'assurer que RLS est activé sur les tables exposées
ALTER TABLE public.products   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

-- 2) Lecture publique (le site doit rester visible par tous)
DROP POLICY IF EXISTS "public_read_products"   ON public.products;
CREATE POLICY "public_read_products"   ON public.products   FOR SELECT USING (true);

DROP POLICY IF EXISTS "public_read_categories" ON public.categories;
CREATE POLICY "public_read_categories" ON public.categories FOR SELECT USING (true);

-- 3) Écriture réservée à l'admin identifié par email
--    Remplacer l'email ci-dessous si tu en utilises un autre
DROP POLICY IF EXISTS "admin_update_products" ON public.products;
CREATE POLICY "admin_update_products" ON public.products
  FOR UPDATE
  USING  ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com')
  WITH CHECK ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

DROP POLICY IF EXISTS "admin_insert_products" ON public.products;
CREATE POLICY "admin_insert_products" ON public.products
  FOR INSERT
  WITH CHECK ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

DROP POLICY IF EXISTS "admin_delete_products" ON public.products;
CREATE POLICY "admin_delete_products" ON public.products
  FOR DELETE
  USING ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

DROP POLICY IF EXISTS "admin_write_categories" ON public.categories;
CREATE POLICY "admin_write_categories" ON public.categories
  FOR ALL
  USING  ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com')
  WITH CHECK ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

-- Vérification : lister les policies créées
SELECT schemaname, tablename, policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public' AND tablename IN ('products','categories')
ORDER  BY tablename, policyname;
