#!/usr/bin/env bash
# Night Express : remplace SumUp par Stripe Checkout.
# Usage (sur le VPS, en root) :
#   curl -fsSL -o /root/install-stripe.sh https://raw.githubusercontent.com/Camille06000/night-express-livraison-nice/claude/analyze-server-prices-fDHII/vps/install-stripe.sh && bash /root/install-stripe.sh
set -euo pipefail

RAW="https://raw.githubusercontent.com/Camille06000/night-express-livraison-nice/claude/analyze-server-prices-fDHII/vps"
WEB=/var/www/night-express
APP=/opt/night-express-stripe
ENVF=/etc/night-express-stripe.env
UNIT=/etc/systemd/system/night-express-stripe.service
PORT=3060
TS=$(date +%Y%m%d-%H%M%S)
BK=/root/ne-backups/stripe-$TS

say() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERREUR : %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" = 0 ] || die "lance ce script en root"

NODE=$(command -v node || true)
[ -n "$NODE" ] || die "node introuvable"
"$NODE" -e 'process.exit(+process.versions.node.split(".")[0] >= 18 ? 0 : 1)' || die "Node 18+ requis (actuel : $("$NODE" -v))"

NGX=$(readlink -f /etc/nginx/sites-enabled/night-express)
[ -f "$NGX" ] || die "config nginx night-express introuvable"

if ss -ltn | grep -q ":$PORT " && ! systemctl is-active --quiet night-express-stripe; then
  die "le port $PORT est deja utilise par un autre programme"
fi

say "Sauvegarde dans $BK"
mkdir -p "$BK"
for f in payer.html merci.html commande.html; do cp -a "$WEB/$f" "$BK/$f"; done
cp -a "$NGX" "$BK/nginx-night-express.conf"
cat > "$BK/rollback.sh" <<EOF
#!/usr/bin/env bash
set -e
for f in payer.html merci.html commande.html; do cp -a "$BK/\$f" "$WEB/\$f"; done
cp -a "$BK/nginx-night-express.conf" "$NGX"
nginx -t && systemctl reload nginx
systemctl disable --now night-express-stripe 2>/dev/null || true
echo "Retour a SumUp effectue."
EOF
chmod +x "$BK/rollback.sh"

say "Telechargement des fichiers"
TMP=$(mktemp -d)
for f in stripe-service/server.js payer.html merci.html commande.html; do
  curl -fsSL -o "$TMP/$(basename "$f")" "$RAW/$f"
done
grep -q "api/payment/stripe/create" "$TMP/payer.html" || die "payer.html telecharge invalide"

say "Cle Stripe"
if [ -f "$ENVF" ] && grep -q '^STRIPE_SECRET_KEY=sk_' "$ENVF"; then
  echo "Cle deja configuree dans $ENVF (supprime ce fichier pour la changer)."
else
  echo "Dashboard Stripe > Developpeurs > Cles API > Cle secrete."
  echo "Commence par sk_test_ (essai) ou sk_live_ (vrais paiements). Elle ne s'affichera pas quand tu la colles."
  read -rsp "Colle ta cle secrete Stripe puis Entree : " KEY </dev/tty; echo
  KEY=$(printf '%s' "$KEY" | tr -d '[:space:]' | sed 's/^\x1b\[200~//; s/\x1b\[201~$//; s/~$//')
  [[ "$KEY" =~ ^(sk|rk)_(live|test)_[A-Za-z0-9]+$ ]] || die "cle invalide (doit commencer par sk_live_ ou sk_test_)"
  ( umask 077; printf 'STRIPE_SECRET_KEY=%s\nPORT=%s\nSITE_URL=https://night-express-livraison-nice.com\n' "$KEY" "$PORT" > "$ENVF" )
  chmod 600 "$ENVF"
  unset KEY
fi

say "Installation du service"
install -d -m 755 "$APP"
install -m 644 "$TMP/server.js" "$APP/server.js"
case "$NODE" in
  /root/*) RUNAS="User=root" ;;
  *)       RUNAS="DynamicUser=yes" ;;
esac
cat > "$UNIT" <<EOF
[Unit]
Description=Night Express - paiement Stripe
After=network-online.target

[Service]
EnvironmentFile=$ENVF
ExecStart=$NODE $APP/server.js
Restart=always
RestartSec=3
$RUNAS
NoNewPrivileges=yes
ProtectSystem=strict
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now night-express-stripe
systemctl restart night-express-stripe
sleep 2
curl -fsS "http://127.0.0.1:$PORT/api/payment/stripe/health" || { journalctl -u night-express-stripe -n 20 --no-pager; die "le service Stripe ne demarre pas"; }
echo

say "Configuration nginx"
if grep -q "location /api/payment/stripe/" "$NGX"; then
  echo "Deja en place."
else
  python3 - "$NGX" "$PORT" <<'PY'
import sys
path, port = sys.argv[1], sys.argv[2]
conf = open(path).read()
block = (
    "    location /api/payment/stripe/ {\n"
    f"        proxy_pass http://127.0.0.1:{port};\n"
    "        proxy_http_version 1.1;\n"
    "        proxy_set_header Host $host;\n"
    "        proxy_set_header X-Real-IP $remote_addr;\n"
    "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n"
    "        proxy_set_header X-Forwarded-Proto $scheme;\n"
    "    }\n\n"
)
anchor = "    location /api/payment/ {"
if anchor not in conf:
    anchor = "    listen 443 ssl;"
if anchor not in conf:
    sys.exit("point d'insertion introuvable")
conf = conf.replace(anchor, block + anchor, 1)
open(path, "w").write(conf)
PY
  if ! nginx -t; then
    cp -a "$BK/nginx-night-express.conf" "$NGX"
    die "nginx refuse la config, ancienne config remise"
  fi
  systemctl reload nginx
fi

say "Mise en ligne des pages (SumUp retire)"
install -m 644 "$TMP/payer.html" "$WEB/payer.html"
install -m 644 "$TMP/merci.html" "$WEB/merci.html"
install -m 644 "$TMP/commande.html" "$WEB/commande.html"
rm -rf "$TMP"

say "Verification publique"
sleep 1
curl -fsS "https://night-express-livraison-nice.com/api/payment/stripe/health" && echo
grep -c "api/payment/stripe/create" "$WEB/payer.html" >/dev/null && echo "payer.html : Stripe OK"

printf '\n\033[1;32mTERMINE. Stripe est actif.\033[0m\n'
echo "Test : https://night-express-livraison-nice.com/commande/payer?amount=1.00&ref=TEST"
echo "Retour en arriere : bash $BK/rollback.sh"
