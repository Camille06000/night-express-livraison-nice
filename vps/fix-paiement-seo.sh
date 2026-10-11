#!/usr/bin/env bash
# Night Express : remplace les mentions SumUp par Stripe et corrige l'info
# "especes / paiement a la livraison" dans les fiches produits, puis regenere le site.
set -euo pipefail

APP=${APP:-/root/night-express-app}
WEB=${WEB:-/var/www/night-express}
SB_URL=https://ifhhfvphrhznislokzxd.supabase.co
TS=$(date +%Y%m%d-%H%M%S)
BK=${BK:-/root/ne-backups/seo-$TS}

say() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERREUR : %s\033[0m\n' "$*"; exit 1; }

[ -f "$APP/seo/prerender.mjs" ] || die "generateur introuvable dans $APP/seo"

say "Sauvegarde dans $BK"
mkdir -p "$BK"
cp -a "$APP/seo" "$BK/seo"
tar czf "$BK/site-html.tgz" --exclude=assets --exclude=lovable-uploads -C "$(dirname "$WEB")" "$(basename "$WEB")"
cat > "$BK/rollback.sh" <<EOF
#!/usr/bin/env bash
set -e
rm -rf "$APP/seo" && cp -a "$BK/seo" "$APP/seo"
tar xzf "$BK/site-html.tgz" -C "$(dirname "$WEB")"
echo "Retour en arriere effectue."
EOF
chmod +x "$BK/rollback.sh"

say "Generateur : SumUp -> Stripe"
for f in "$APP"/seo/*.mjs; do
  if grep -q "SumUp" "$f"; then
    sed -i 's/SumUp/Stripe/g' "$f"
    node --check "$f" || { cp -a "$BK/seo/$(basename "$f")" "$f"; die "$(basename "$f") invalide apres modification, restaure"; }
    echo "corrige : $(basename "$f")"
  fi
done

say "Pages du site : SumUp -> Stripe"
n=0
while IFS= read -r f; do
  sed -i 's/SumUp/Stripe/g' "$f"; n=$((n+1))
done < <(grep -rl --include=*.html "SumUp" "$WEB" || true)
echo "$n page(s) corrigee(s)"

say "Fiches produits : retrait de 'especes / a la livraison'"
node - "$APP" "$SB_URL" <<'JS' || echo "(etape base de donnees ignoree)"
const fs = require('fs'), path = require('path');
const [app, sbUrl] = process.argv.slice(2);
const ref = new URL(sbUrl).hostname.split('.')[0];

function findKey(dir, depth) {
  if (depth > 3) return null;
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return null; }
  for (const e of entries) {
    if (e.name === 'node_modules' || e.name === '.git') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { const k = findKey(p, depth + 1); if (k) return k; continue; }
    if (!/^\.env/.test(e.name) && !/\.env$/.test(e.name)) continue;
    const txt = fs.readFileSync(p, 'utf8');
    for (const tok of txt.match(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g) || []) {
      try {
        const pl = JSON.parse(Buffer.from(tok.split('.')[1], 'base64url').toString());
        if (pl.role === 'service_role' && pl.ref === ref) return tok;
      } catch {}
    }
  }
  return null;
}

(async () => {
  const key = findKey(app, 0);
  if (!key) { console.log('Cle service Supabase introuvable dans', app, '- etape ignoree'); return; }
  const h = { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' };
  const r = await fetch(sbUrl + '/rest/v1/products?select=id,description&description=ilike.*esp%C3%A8ces*', { headers: h });
  if (!r.ok) throw new Error('lecture produits : HTTP ' + r.status);
  const rows = await r.json();
  const fixes = [
    ['Paiement sécurisé par carte, espèces, Apple Pay ou Google Pay à la livraison.', 'Paiement sécurisé en ligne par carte, Apple Pay ou Google Pay.'],
    ['par carte, espèces, Apple Pay ou Google Pay à la livraison', 'en ligne par carte, Apple Pay ou Google Pay'],
  ];
  let ok = 0;
  for (const row of rows) {
    let d = row.description;
    for (const [a, b] of fixes) d = d.split(a).join(b);
    if (d === row.description) continue;
    const u = await fetch(sbUrl + '/rest/v1/products?id=eq.' + row.id, { method: 'PATCH', headers: { ...h, Prefer: 'return=minimal' }, body: JSON.stringify({ description: d }) });
    if (u.ok) ok++; else console.log('echec', row.id, u.status);
  }
  console.log(ok + ' fiche(s) produit corrigee(s) sur ' + rows.length + ' contenant "espèces"');
})().catch(e => { console.log('Erreur :', e.message); process.exit(1); });
JS

say "Regeneration du site"
( cd "$APP/seo" && node prerender.mjs ) | tail -5

say "Verification"
left=$(grep -rl --include=*.html "SumUp" "$WEB" | wc -l || true)
esp=$(grep -rl --include=*.html "espèces, Apple Pay" "$WEB/produit" 2>/dev/null | wc -l || true)
echo "Pages mentionnant encore SumUp : $left"
echo "Fiches produits mentionnant encore les especes : $esp"

printf '\n\033[1;32mTERMINE.\033[0m Retour en arriere possible : bash %s/rollback.sh\n' "$BK"
