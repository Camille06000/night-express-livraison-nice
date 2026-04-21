# night-express-livraison-nice

Dépôt de travail pour le site **https://night-express-livraison-nice.com** (épicerie de nuit Nice).

## Contenu

- `admin.html` — page d'administration autonome (login Supabase + édition des prix).
- `supabase-admin-setup.sql` — policies RLS à appliquer une seule fois dans Supabase SQL Editor.

## Déploiement de `admin.html`

Sur le VPS, depuis le Browser Terminal Hostinger :

```bash
cd /var/www/night-express
curl -fsSL -o admin.html https://raw.githubusercontent.com/Camille06000/night-express-livraison-nice/claude/analyze-server-prices-fDHII/admin.html
ls -lh admin.html
```

Puis accéder à `https://night-express-livraison-nice.com/admin.html`.

## Prérequis Supabase

1. Créer (ou vérifier) l'utilisateur admin dans **Dashboard Supabase > Authentication > Users**
   avec l'email `profpromptpro@gmail.com`.
2. Exécuter `supabase-admin-setup.sql` dans **SQL Editor**.
