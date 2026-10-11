#!/usr/bin/env bash
# Redirige /pack-alcool (page fantome indexee par Google) vers la vraie page des packs.
set -euo pipefail
NGX=$(readlink -f /etc/nginx/sites-enabled/night-express)
BK=/root/ne-backups/nginx-$(date +%Y%m%d-%H%M%S).conf
if grep -q "location = /pack-alcool" "$NGX"; then echo "Redirection deja en place."; else
  cp -a "$NGX" "$BK"
  python3 - "$NGX" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "    location / {"
if anchor not in s: sys.exit("point d'insertion introuvable")
s = s.replace(anchor, "    location = /pack-alcool { return 301 /catalogue/packs-coffrets; }\n\n" + anchor, 1)
open(p, "w").write(s)
PY
  if ! nginx -t 2>&1 | tail -2; then cp -a "$BK" "$NGX"; echo "ERREUR nginx : ancienne config remise"; exit 1; fi
  systemctl reload nginx
  echo "Sauvegarde nginx : $BK"
fi
sleep 1
curl -s -o /dev/null -w "Verification : /pack-alcool -> %{http_code} vers %{redirect_url}\n" https://night-express-livraison-nice.com/pack-alcool
