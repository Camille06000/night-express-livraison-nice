#!/usr/bin/env bash
# Ajoute un lien "Livraison d'alcool a Nice" dans le texte d'introduction de l'accueil.
set -euo pipefail
F=${F:-/var/www/night-express/home.html}
BK=${BK:-/root/ne-backups/home-$(date +%Y%m%d-%H%M%S).html}
cp -a "$F" "$BK"
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
if 'href="/livraison-alcool-nice" style="color:inherit' in s:
    print("Lien deja en place."); sys.exit(0)
old = '<p class="lead">Alcool, champagne, vodka, whisky, bières, softs, snacks et dépannage.'
new = ('<p class="lead"><a href="/livraison-alcool-nice" style="color:inherit;text-decoration:underline;'
       'text-decoration-color:#e9c989;text-decoration-thickness:2px;text-underline-offset:4px">'
       "Livraison d'alcool à Nice</a> : champagne, vodka, whisky, bières, mais aussi softs, snacks et dépannage.")
if s.count(old) != 1: sys.exit("texte d'introduction introuvable : rien n'a ete modifie")
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
print("Lien ajoute.")
PY
echo "Sauvegarde : $BK"
curl -s "https://night-express-livraison-nice.com/?x=$RANDOM" | grep -q "alcool à Nice</a> : champagne" && echo "Verification en ligne : OK" || echo "Verification en ligne : lien non visible"
echo "Annuler : cp $BK $F"
