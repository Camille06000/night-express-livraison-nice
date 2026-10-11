#!/usr/bin/env bash
# Night Express : titres Google des fiches produits avec degre d'alcool et prix.
set -euo pipefail

APP=${APP:-/root/night-express-app}
WEB=${WEB:-/var/www/night-express}
F="$APP/seo/prerender.mjs"
BK=${BK:-/root/ne-backups/titres-$(date +%Y%m%d-%H%M%S)}

say() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERREUR : %s\033[0m\n' "$*"; exit 1; }

mkdir -p "$BK"
cp -a "$F" "$BK/prerender.mjs"
echo "Sauvegarde : $BK/prerender.mjs"

say "Modification du generateur"
python3 - "$F" <<'PY'
import sys
path = sys.argv[1]
s = open(path, encoding='utf-8').read()
if 'NE-TITRES-V2' in s:
    print('Deja applique.')
    sys.exit(0)
old = """  const t0 = `${p.name} livré à Nice de nuit | Night Express`;
  const title = t0.length <= 65 ? t0 : `${clip(p.name, 40)} livré à Nice | Night Express`;"""
new = """  // NE-TITRES-V2 : degre et prix dans le titre (requetes "degré", "prix")
  const deg = alcoholCat(c) && p.alcohol_percentage != null && Number(p.alcohol_percentage) > 0 && !/\\d\\s*(°|%)/.test(p.name)
    ? ` ${String(Number(p.alcohol_percentage)).replace('.', ',')}°` : '';
  const pr = price > 0 ? ` à ${eur(price)}` : '';
  const title = [
    `${p.name}${deg}${pr} – Livraison Nice | Night Express`,
    `${p.name}${deg}${pr} – Livraison Nice`,
    `${p.name}${deg} – Livraison Nice | Night Express`,
    `${p.name}${pr} – Livraison Nice`,
    `${p.name} – Livraison Nice`,
  ].find((t) => t.length <= 65) || `${clip(p.name, 45)} – Livraison Nice`;"""
if old not in s:
    sys.exit('bloc du titre introuvable (generateur modifie entre-temps)')
open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
print('OK')
PY
node --check "$F" || { cp -a "$BK/prerender.mjs" "$F"; die "generateur invalide, sauvegarde remise"; }

say "Regeneration du site"
if ! ( cd "$APP/seo" && node prerender.mjs ) 2>&1 | tail -3; then
  cp -a "$BK/prerender.mjs" "$F"; ( cd "$APP/seo" && node prerender.mjs ) >/dev/null 2>&1 || true
  die "regeneration en echec, ancien generateur remis"
fi

say "Exemples de nouveaux titres"
for s in biere-amsterdam-maximator-50cl chips-cheetos-gout-fromage-xxl rhum-capitaine-morgane-70cl bieres-en-canettes-desperados-50cl vin-prosecco-extra-dry-allini; do
  f="$WEB/produit/$s.html"
  [ -f "$f" ] && grep -o '<title>[^<]*</title>' "$f" | head -1
done
printf '\n\033[1;32mTERMINE.\033[0m Annuler : cp %s/prerender.mjs %s && (cd %s/seo && node prerender.mjs)\n' "$BK" "$F" "$APP"
