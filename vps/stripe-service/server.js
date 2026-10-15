'use strict';

const http = require('http');

const KEY = process.env.STRIPE_SECRET_KEY || '';
const PORT = Number(process.env.PORT || 3060);
const SITE = (process.env.SITE_URL || 'https://night-express-livraison-nice.com').replace(/\/$/, '');
const MIN_EUR = 1;
const MAX_EUR = Number(process.env.MAX_EUR || 1500);
const STRIPE_API = process.env.STRIPE_API || 'https://api.stripe.com/v1';
const API = (process.env.API_URL || 'http://127.0.0.1:3000').replace(/\/$/, '');
const TOKEN = process.env.NE_INTERNAL_TOKEN || '';
const STARTED = Math.floor(Date.now() / 1000) - 20 * 60;

if (!/^(sk|rk)_(live|test)_/.test(KEY)) {
  console.error('STRIPE_SECRET_KEY manquante ou invalide');
  process.exit(1);
}

async function stripe(method, path, params) {
  const opts = {
    method,
    headers: {
      Authorization: 'Bearer ' + KEY,
      'Stripe-Version': '2024-06-20',
    },
  };
  if (params) {
    opts.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    opts.body = new URLSearchParams(params).toString();
  }
  const r = await fetch(STRIPE_API + path, opts);
  const data = await r.json();
  if (!r.ok) {
    const err = new Error((data.error && data.error.message) || 'Stripe error');
    err.status = r.status;
    throw err;
  }
  return data;
}

async function api(method, path, body) {
  if (!TOKEN) return { status: 0, error: 'no token' };
  try {
    const r = await fetch(API + path, {
      method,
      headers: { 'x-ne-internal': TOKEN, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000),
    });
    return { status: r.status, data: await r.json().catch(() => null) };
  } catch (e) {
    return { status: 0, error: e.message };
  }
}

// Sessions deja transmises a l'API (l'API est idempotente, ceci evite juste les appels inutiles)
const notified = new Set();
async function notifyPaid(s) {
  const ref = s.client_reference_id || (s.metadata && s.metadata.reference) || '';
  if (!/^NE-/i.test(ref) || notified.has(s.id)) return;
  const r = await api('POST', '/internal/stripe-paid', { orderNumber: ref, amount: (s.amount_total || 0) / 100, session: s.id });
  if (r.status >= 200 && r.status < 500) {
    notified.add(s.id);
    console.log(new Date().toISOString(), 'commande transmise', ref, r.status, JSON.stringify(r.data));
  } else {
    console.error(new Date().toISOString(), 'transmission echouee, nouvel essai dans 1 min', ref, r.status, r.error || '');
  }
}

async function pollPaid() {
  try {
    const since = Math.max(STARTED, Math.floor(Date.now() / 1000) - 3 * 3600);
    const list = await stripe('GET', '/checkout/sessions?limit=100&created%5Bgte%5D=' + since);
    for (const s of list.data || []) {
      if (s.payment_status === 'paid') await notifyPaid(s);
    }
  } catch (e) {
    console.error(new Date().toISOString(), 'poll', e.message);
  }
}

function send(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(obj));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > 10000) { reject(new Error('too large')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString() || '{}')); }
      catch (e) { reject(e); }
    });
    req.on('error', reject);
  });
}

async function createSession(req, res) {
  let body;
  try { body = await readJson(req); } catch { return send(res, 400, { error: 'Requete invalide' }); }

  let amount = Number(body.amount);
  const ref = String(body.reference || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40) || 'direct';
  if (/^NE-/i.test(ref)) {
    const o = await api('GET', '/internal/order/' + encodeURIComponent(ref));
    if (o.status === 200 && o.data) {
      if (o.data.payment_status === 'paid') return send(res, 409, { error: 'Cette commande est deja payee.' });
      if (Number(o.data.total) > 0) amount = Number(o.data.total);
    }
  }
  if (!isFinite(amount) || amount < MIN_EUR || amount > MAX_EUR) {
    return send(res, 400, { error: 'Montant invalide' });
  }
  const cents = Math.round(amount * 100);

  const cancel = SITE + '/commande/payer?amount=' + (cents / 100).toFixed(2) + '&ref=' + encodeURIComponent(ref) + '&cancelled=1';
  const session = await stripe('POST', '/checkout/sessions', {
    mode: 'payment',
    locale: 'fr',
    'line_items[0][quantity]': '1',
    'line_items[0][price_data][currency]': 'eur',
    'line_items[0][price_data][unit_amount]': String(cents),
    'line_items[0][price_data][product_data][name]': 'Commande Night Express' + (ref !== 'direct' ? ' ' + ref : ''),
    client_reference_id: ref,
    'metadata[reference]': ref,
    'payment_intent_data[metadata][reference]': ref,
    'payment_intent_data[description]': 'Night Express Nice - ' + ref,
    success_url: SITE + '/commande/merci?session_id={CHECKOUT_SESSION_ID}',
    cancel_url: cancel,
  });
  send(res, 200, { id: session.id, url: session.url });
}

async function sessionStatus(res, id) {
  if (!/^cs_(test|live)_[A-Za-z0-9]{10,200}$/.test(id)) return send(res, 400, { error: 'Identifiant invalide' });
  const s = await stripe('GET', '/checkout/sessions/' + id);
  const paid = s.payment_status === 'paid' || s.payment_status === 'no_payment_required';
  if (s.payment_status === 'paid') notifyPaid(s).catch(() => {});
  send(res, 200, {
    paid,
    status: paid ? 'PAID' : s.status === 'expired' ? 'EXPIRED' : 'PENDING',
    amount: (s.amount_total || 0) / 100,
    currency: String(s.currency || 'eur').toUpperCase(),
    checkout_reference: s.client_reference_id || '',
    order_number: (s.metadata && s.metadata.reference) || '',
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  try {
    if (req.method === 'GET' && url.pathname === '/api/payment/stripe/health') {
      return send(res, 200, { ok: true, mode: KEY.includes('_live_') ? 'live' : 'test' });
    }
    if (req.method === 'POST' && url.pathname === '/api/payment/stripe/create') {
      return await createSession(req, res);
    }
    const m = url.pathname.match(/^\/api\/payment\/stripe\/status\/([^/]+)$/);
    if (req.method === 'GET' && m) return await sessionStatus(res, decodeURIComponent(m[1]));
    send(res, 404, { error: 'Not found' });
  } catch (e) {
    console.error(new Date().toISOString(), req.method, url.pathname, e.message);
    send(res, e.status === 404 ? 404 : 502, { error: 'Paiement indisponible, reessayez' });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('Night Express Stripe sur 127.0.0.1:' + PORT + ' (' + (KEY.includes('_live_') ? 'LIVE' : 'TEST') + ')' + (TOKEN ? ', notifications actives' : ', notifications INACTIVES'));
  if (TOKEN) {
    setTimeout(pollPaid, 5000);
    setInterval(pollPaid, 60000);
  }
});
