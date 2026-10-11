#!/usr/bin/env bash
# Remet le squelette d'origine de l'application (index.html) a la place de la landing,
# puis relance le generateur de pages.
set -uo pipefail

WEB=${WEB:-/var/www/night-express}
APP=${APP:-/root/night-express-app}
TS=$(date +%Y%m%d-%H%M%S)
BK=${BK:-/root/ne-backups/index-$TS}

say() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }

mkdir -p "$BK"
cp -a "$WEB/index.html" "$BK/index-landing.html"
echo "Landing actuelle sauvegardee : $BK/index-landing.html"

say "Recherche de l'index.html d'origine sur le serveur"
CAND=$(python3 - "$WEB" <<'PY'
import os, re, sys
web = os.path.realpath(sys.argv[1])
skip_dirs = {'node_modules', '.git', 'produit', 'catalogue', 'blog', 'assets', 'lovable-uploads', 'proc', 'sys', '.venv', 'venv', '__pycache__', '.cache', '.npm', 'docker'}
found = []
for root in os.environ.get('SEARCH', '/root /var/www /opt /srv /home').split():
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in skip_dirs]
        for f in files:
            if '.html' not in f or f.startswith('home.html'):
                continue
            p = os.path.join(d, f)
            try:
                if os.path.getsize(p) > 400_000:
                    continue
                s = open(p, encoding='utf-8', errors='ignore').read()
            except OSError:
                continue
            if 'id="root"' not in s or '/assets/index-' not in s or 'La nuit niçoise' in s or 'night express' not in s.lower():
                continue
            can = re.search(r'rel="canonical"\s+href="([^"]+)"', s)
            if can and not re.fullmatch(r'https://night-express-livraison-nice\.com/?', can.group(1)):
                continue
            score = (('ne-seo-spa.js' in s) * 4 + f.startswith('index.html') * 2 + (os.path.dirname(os.path.realpath(p)) == web))
            found.append((score, os.path.getmtime(p), p))
found.sort(reverse=True)
for sc, mt, p in found[:8]:
    print(f"{sc}\t{int(mt)}\t{p}")
PY
)

if [ -z "$CAND" ]; then
  echo "Aucune copie d'origine trouvee."
  say "Infos pour Claude (copie tout ce qui suit)"
  grep -n -E "index\.html|indexOf|start|end" "$APP/seo/prerender.mjs" | head -30
  sed -n '100,125p' "$APP/seo/prerender.mjs"
  exit 1
fi

echo "Copies trouvees (score, date, chemin) :"
while IFS=$'\t' read -r sc mt p; do echo "  $sc  $(date -d @"$mt" '+%Y-%m-%d %H:%M')  $p"; done <<< "$CAND"
BEST=$(head -1 <<< "$CAND" | cut -f3)

say "Restauration de $BEST"
cp -a "$BEST" "$BK/index-restaure.html"
install -m 644 "$BEST" "$WEB/index.html"

say "Regeneration du site"
if ( cd "$APP/seo" && node prerender.mjs ) 2>&1 | tail -5; then
  if grep -q "La nuit niçoise" "$WEB/index.html"; then echo "ATTENTION : la landing est toujours la"; fi
fi

say "Verification"
for p in contact panier page-test-inexistante; do
  code=$(curl -s -o /tmp/ne-check.html -w '%{http_code}' "https://night-express-livraison-nice.com/$p?x=$RANDOM")
  if grep -q "La nuit niçoise" /tmp/ne-check.html; then echo "/$p : $code  -> encore la landing"; else echo "/$p : $code  -> application OK"; fi
done
grep -rl --include=*.html "SumUp" "$WEB" | wc -l | sed 's/^/Pages mentionnant encore SumUp : /'

printf '\n\033[1;32mTERMINE.\033[0m Pour annuler : cp %s/index-landing.html %s/index.html\n' "$BK" "$WEB"
