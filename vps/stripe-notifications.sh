#!/usr/bin/env bash
# Night Express : a chaque paiement Stripe, la commande passe "payee" et le livreur
# recoit son SMS + l'e-mail de commande (via confirmOrderPaymentAndNotify de l'API).
# Stripe facture aussi le total enregistre dans la commande, pas le montant de l'URL.
set -euo pipefail

RAW="https://raw.githubusercontent.com/Camille06000/night-express-livraison-nice/claude/analyze-server-prices-fDHII/vps"
APPDIR=${APPDIR:-/root/night-express-app}
IDX="$APPDIR/server/index.js"
# dotenv charge .env.local puis .env (sans ecraser) : on ecrit dans le premier present
if [ -f "$APPDIR/.env.local" ]; then APIENV="$APPDIR/.env.local"; else APIENV="$APPDIR/.env"; fi
SENV=${SENV:-/etc/night-express-stripe.env}
SAPP=${SAPP:-/opt/night-express-stripe}
API_PORT=${API_PORT:-3000}
BK=${BK:-/root/ne-backups/stripe-notif-$(date +%Y%m%d-%H%M%S)}
SKIP_SERVICES=${SKIP_SERVICES:-0}

say() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERREUR : %s\033[0m\n' "$*"; exit 1; }

[ -f "$IDX" ] || die "$IDX introuvable"
grep -q "async function confirmOrderPaymentAndNotify" "$IDX" || die "fonction confirmOrderPaymentAndNotify introuvable"
grep -q "async function sendOrderNotificationEmail" "$IDX" || die "fonction sendOrderNotificationEmail introuvable"
grep -qE "^import express " "$IDX" || die "import express introuvable"
grep -q "^app.listen(PORT" "$IDX" || die "app.listen(PORT introuvable"

mkdir -p "$BK"
cp -a "$IDX" "$BK/index.js"
[ -f "$APIENV" ] && cp -a "$APIENV" "$BK/api.env"
[ -f "$SENV" ] && cp -a "$SENV" "$BK/stripe.env"
[ -f "$SAPP/server.js" ] && cp -a "$SAPP/server.js" "$BK/stripe-server.js"
cat > "$BK/rollback.sh" <<EOF
#!/usr/bin/env bash
cp -a "$BK/index.js" "$IDX"; [ -f "$BK/api.env" ] && cp -a "$BK/api.env" "$APIENV"
[ -f "$BK/stripe.env" ] && cp -a "$BK/stripe.env" "$SENV"
[ -f "$BK/stripe-server.js" ] && cp -a "$BK/stripe-server.js" "$SAPP/server.js"
pm2 restart night-express-api --update-env; systemctl restart night-express-stripe
echo "Retour en arriere effectue."
EOF
chmod 700 "$BK/rollback.sh"
echo "Sauvegarde : $BK"

say "Jeton interne partage entre l'API et le service Stripe"
TOK=$(grep -h "^NE_INTERNAL_TOKEN=" "$APPDIR/.env.local" "$APPDIR/.env" 2>/dev/null | tail -1 | cut -d= -f2- || true)
if [ -z "$TOK" ]; then
  TOK=$(python3 -c "import secrets;print(secrets.token_hex(24))")
  printf '\nNE_INTERNAL_TOKEN=%s\n' "$TOK" >> "$APIENV"
fi
touch "$SENV"; chmod 600 "$SENV"
sed -i '/^NE_INTERNAL_TOKEN=/d; /^API_URL=/d' "$SENV"
printf 'NE_INTERNAL_TOKEN=%s\nAPI_URL=http://127.0.0.1:%s\n' "$TOK" "$API_PORT" >> "$SENV"
echo "OK"

say "Ajout du branchement Stripe dans l'API"
if grep -q "NE-STRIPE-HOOK" "$IDX"; then
  echo "Deja en place."
else
  python3 - "$IDX" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
block = r'''// NE-STRIPE-HOOK : appele uniquement par le service Stripe local (127.0.0.1 + jeton)
const NE_INTERNAL_TOKEN = process.env.NE_INTERNAL_TOKEN || "";
function neInternalOk(req) {
  const ip = (req.socket && req.socket.remoteAddress) || "";
  return Boolean(NE_INTERNAL_TOKEN) && req.get("x-ne-internal") === NE_INTERNAL_TOKEN
    && /^(::ffff:)?127\.0\.0\.1$|^::1$/.test(ip);
}
async function neFindOrder(orderNumber) {
  if (!supabaseAdmin) return null;
  const { data, error } = await supabaseAdmin.from("orders").select("*").eq("order_number", orderNumber).limit(1);
  if (error) throw new Error(error.message);
  return (data || [])[0] || null;
}
const neOrderTotal = (o) => Number(o.total ?? o.total_amount ?? o.amount ?? 0);

app.get("/internal/order/:orderNumber", async (req, res) => {
  if (!neInternalOk(req)) return res.status(403).json({ error: "forbidden" });
  try {
    const o = await neFindOrder(String(req.params.orderNumber));
    if (!o) return res.status(404).json({ error: "not_found" });
    res.json({ order_number: o.order_number, total: neOrderTotal(o), payment_status: o.payment_status });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/internal/stripe-paid", express.json(), async (req, res) => {
  if (!neInternalOk(req)) return res.status(403).json({ error: "forbidden" });
  const orderNumber = String((req.body && req.body.orderNumber) || "");
  const paid = Number((req.body && req.body.amount) || 0);
  try {
    const o = await neFindOrder(orderNumber);
    if (!o) return res.status(404).json({ error: "not_found" });
    const total = neOrderTotal(o);
    if (total > 0 && paid + 0.01 < total) {
      console.error("[stripe] montant insuffisant", orderNumber, paid, "<", total);
      await sendOrderNotificationEmail({
        brand: "Night Express",
        reference: orderNumber,
        textBody: `ALERTE : la commande ${orderNumber} a ete payee ${paid.toFixed(2)} EUR sur Stripe alors que son total est ${total.toFixed(2)} EUR. Ne pas livrer avant verification.`,
        logPrefix: "[stripe-alerte]",
      });
      return res.status(409).json({ error: "amount_mismatch", total, paid });
    }
    const r = await confirmOrderPaymentAndNotify(orderNumber);
    console.log("[stripe] paiement confirme", orderNumber, JSON.stringify(r));
    res.json({ ok: true, ...r });
  } catch (e) {
    console.error("[stripe] confirmation KO", orderNumber, e.message);
    res.status(500).json({ error: e.message });
  }
});

'''
import re
m = re.search(r'^const app = express\(\);?[ \t]*\n', s, re.M)
if m:
    s = s[:m.end()] + "\n" + block + s[m.end():]
    print("OK (juste apres la creation de l'API)")
else:
    anchor = "\napp.listen(PORT"
    if s.count(anchor) != 1:
        sys.exit("point d'insertion introuvable")
    s = s.replace(anchor, "\n" + block + "app.listen(PORT", 1)
    print("OK (avant app.listen)")
open(p, 'w', encoding='utf-8').write(s)
PY
  node --check "$IDX" || { cp -a "$BK/index.js" "$IDX"; die "index.js invalide apres modification, sauvegarde remise"; }
fi

say "Mise a jour du service Stripe"
TMP=$(mktemp)
curl -fsSL -o "$TMP" "${STRIPE_JS_URL:-$RAW/stripe-service/server.js}"
grep -q "internal/stripe-paid" "$TMP" || die "server.js telecharge invalide"
install -m 644 "$TMP" "$SAPP/server.js"; rm -f "$TMP"
echo "OK"

[ "$SKIP_SERVICES" = 1 ] && { echo "(redemarrages ignores : mode test)"; exit 0; }

say "Redemarrage de l'API et du service Stripe"
pm2 restart night-express-api --update-env >/dev/null
sleep 4
code=$(curl -s -o /tmp/ne-int.json -w '%{http_code}' -H "x-ne-internal: $TOK" "http://127.0.0.1:$API_PORT/internal/order/NE-VERIF-INEXISTANTE" || true)
if [ "$code" != 404 ] || ! grep -q not_found /tmp/ne-int.json; then
  echo "Reponse inattendue de l'API ($code) : $(head -c 200 /tmp/ne-int.json 2>/dev/null)"
  bash "$BK/rollback.sh" >/dev/null 2>&1 || true
  die "branchement API non fonctionnel, tout a ete remis comme avant"
fi
echo "API : OK"
systemctl restart night-express-stripe
sleep 2
curl -fsS "http://127.0.0.1:3060/api/payment/stripe/health" >/dev/null || { bash "$BK/rollback.sh" >/dev/null 2>&1 || true; die "service Stripe ne redemarre pas, tout a ete remis comme avant"; }
journalctl -u night-express-stripe -n 3 --no-pager -o cat | grep -i "notifications" || true

printf '\n\033[1;32mTERMINE.\033[0m A chaque paiement Stripe : commande payee + SMS livreur + e-mail.\n'
echo "Annuler : bash $BK/rollback.sh"
