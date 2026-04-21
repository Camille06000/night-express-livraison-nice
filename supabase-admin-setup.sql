-- Night Express — Admin access setup (v2 : produits + blog + catégories)
-- À exécuter une seule fois dans Supabase SQL Editor
--   Dashboard Supabase > SQL Editor > New query > coller > Run

-- 1) RLS activé
ALTER TABLE public.products    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blog_posts  ENABLE ROW LEVEL SECURITY;

-- 2) Lecture publique (catalogue + blog doivent rester visibles par tous)
DROP POLICY IF EXISTS "public_read_products"   ON public.products;
CREATE POLICY "public_read_products"   ON public.products   FOR SELECT USING (true);

DROP POLICY IF EXISTS "public_read_categories" ON public.categories;
CREATE POLICY "public_read_categories" ON public.categories FOR SELECT USING (true);

DROP POLICY IF EXISTS "public_read_blog" ON public.blog_posts;
CREATE POLICY "public_read_blog" ON public.blog_posts
  FOR SELECT USING (is_published = true);

-- 3) Écriture réservée à l'admin identifié par email
--    (Remplacer l'email ci-dessous si tu en utilises un autre)

-- PRODUITS
DROP POLICY IF EXISTS "admin_update_products" ON public.products;
CREATE POLICY "admin_update_products" ON public.products
  FOR UPDATE USING  ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com')
              WITH CHECK ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

DROP POLICY IF EXISTS "admin_insert_products" ON public.products;
CREATE POLICY "admin_insert_products" ON public.products
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

DROP POLICY IF EXISTS "admin_delete_products" ON public.products;
CREATE POLICY "admin_delete_products" ON public.products
  FOR DELETE USING ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

-- L'admin doit aussi voir les produits inactifs (la policy public_read ne renvoie que is_active si tu en rajoutes une)
DROP POLICY IF EXISTS "admin_read_all_products" ON public.products;
CREATE POLICY "admin_read_all_products" ON public.products
  FOR SELECT USING ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

-- CATEGORIES (toutes écritures admin)
DROP POLICY IF EXISTS "admin_write_categories" ON public.categories;
CREATE POLICY "admin_write_categories" ON public.categories
  FOR ALL USING  ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com')
          WITH CHECK ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

-- BLOG
DROP POLICY IF EXISTS "admin_read_all_blog" ON public.blog_posts;
CREATE POLICY "admin_read_all_blog" ON public.blog_posts
  FOR SELECT USING ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

DROP POLICY IF EXISTS "admin_insert_blog" ON public.blog_posts;
CREATE POLICY "admin_insert_blog" ON public.blog_posts
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

DROP POLICY IF EXISTS "admin_update_blog" ON public.blog_posts;
CREATE POLICY "admin_update_blog" ON public.blog_posts
  FOR UPDATE USING  ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com')
              WITH CHECK ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

DROP POLICY IF EXISTS "admin_delete_blog" ON public.blog_posts;
CREATE POLICY "admin_delete_blog" ON public.blog_posts
  FOR DELETE USING ((auth.jwt() ->> 'email') = 'profpromptpro@gmail.com');

-- 4) Vérification : lister les policies créées
SELECT tablename, policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public' AND tablename IN ('products','categories','blog_posts')
ORDER  BY tablename, policyname;
