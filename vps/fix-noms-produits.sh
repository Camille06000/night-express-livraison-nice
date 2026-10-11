#!/usr/bin/env bash
# Night Express : corrige les fautes dans les noms de produits et les degres d'alcool errones.
# Les adresses des pages (slugs) ne changent pas, pour ne rien perdre sur Google.
set -euo pipefail

APP=${APP:-/root/night-express-app}
BK=${BK:-/root/ne-backups/noms-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$BK"

printf '\n\033[1;33m==> Correction des produits (sauvegarde dans %s)\033[0m\n' "$BK"
node - "$APP" "$BK" <<'JS'
const fs = require('fs'), path = require('path');
const [app, bk] = process.argv.slice(2);
const SB = process.env.SB_URL || 'https://ifhhfvphrhznislokzxd.supabase.co';

// prefixe d'id -> [nouveau nom | null, { alcool: null } facultatif, tags a ajouter]
const FIX = {
  '888479b8': ['Boisson Énergisante Red Bull Red Edition Watermelon'],
  '31116e09': ['Boisson Énergisante Red Bull Apricot Edition Abricot'],
  'd5bcaf5e': ['Boisson Énergisante Red Bull Myrtille'],
  '3f11e111': ['Boisson Énergisante Red Bull Sea Blue Juneberry'],
  'f247d645': ['Boisson Énergisante Red Bull Winter Fuji Apple Ginger', { alcohol_percentage: null }],
  '25d17f16': ['Boisson Énergisante Monster'],
  '00feaa85': ['Boisson Énergisante Red Bull Zero'],
  '4934208d': ['Boisson Énergisante Monster Bad Apple'],
  'c2a713c2': ['Boisson Énergisante Monster Punch'],
  '4d9be7f3': ['Boisson Énergisante Powerade'],
  '66ddcba2': ['Boisson Énergisante Red Bull Pink Edition Wild Berry'],
  'f73cb227': ['Bonbon Fini Rainbow Pencil'],
  'd1df80e9': ['Champagne – Moët & Chandon Impérial'],
  '80917cd3': ['Champagne Ruinart Rosé', null, ['ruinard', 'ruinard rosé']],
  '9636a9f1': ['Champagne Veuve Clicquot', null, ['veuve cliquot', 'cliquot']],
  '6e9a6a13': ["Gin Hendrick's", null, ['hendricks', 'hendrick']],
  '8314ff0d': ['Energy Red Bull Myrtille'],
  '2ceeebe5': ['Energy Drinks – Red Bull 25cl', null, ['redbull 25cl']],
  '0c9dfa92': ['Energy Drinks – Red Bull 50cl', null, ['redbull 50cl']],
  '69ec8357': ['Energy Red Bull Classic', null, ['redbull classic']],
  '0075db71': ['Soft Rochambeau Jus Multifruit'],
  'c6c2167a': ['Soft Jus Rioba Cranberry'],
  '845ba880': [null, { alcohol_percentage: null }],
};
const FIELDS = 'id,name,description,short_description,meta_title,meta_description,tags,alcohol_percentage';

function findKey(dir, depth) {
  if (depth > 3) return null;
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return null; }
  for (const e of entries) {
    if (e.name === 'node_modules' || e.name === '.git') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { const k = findKey(p, depth + 1); if (k) return k; continue; }
    if (!/^\.env/.test(e.name) && !/\.env$/.test(e.name)) continue;
    for (const tok of fs.readFileSync(p, 'utf8').match(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g) || []) {
      try {
        const pl = JSON.parse(Buffer.from(tok.split('.')[1], 'base64url').toString());
        if (pl.role === 'service_role' && pl.ref === 'ifhhfvphrhznislokzxd') return tok;
      } catch {}
    }
  }
  return null;
}

(async () => {
  const key = findKey(app, 0);
  if (!key) throw new Error('cle service Supabase introuvable dans ' + app);
  const H = { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' };

  const r = await fetch(`${SB}/rest/v1/products?select=${FIELDS}&limit=1000`, { headers: H });
  if (!r.ok) throw new Error('lecture produits HTTP ' + r.status);
  const all = await r.json();
  const byPrefix = Object.fromEntries(all.map((p) => [p.id.slice(0, 8), p]));

  const before = [];
  let ok = 0;
  for (const [prefix, [newName, extra, addTags]] of Object.entries(FIX)) {
    const p = byPrefix[prefix];
    if (!p) { console.log('  introuvable :', prefix); continue; }
    const patch = { ...(extra || {}) };
    if (newName && newName !== p.name) {
      patch.name = newName;
      for (const f of ['description', 'short_description', 'meta_title', 'meta_description']) {
        if (p[f] && p[f].includes(p.name)) patch[f] = p[f].split(p.name).join(newName);
      }
    }
    if (addTags && Array.isArray(p.tags)) {
      const t = [...new Set([...p.tags, ...addTags])];
      if (t.length !== p.tags.length) patch.tags = t;
    } else if (addTags && p.tags == null) {
      patch.tags = addTags;
    }
    if ('alcohol_percentage' in patch && p.alcohol_percentage === patch.alcohol_percentage) delete patch.alcohol_percentage;
    if (!Object.keys(patch).length) { console.log('  deja correct :', p.name); continue; }

    before.push(Object.fromEntries(['id', ...Object.keys(patch)].map((k) => [k, p[k]])));
    const u = await fetch(`${SB}/rest/v1/products?id=eq.${p.id}`, { method: 'PATCH', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify(patch) });
    if (!u.ok) { console.log('  ECHEC', p.name, u.status, await u.text()); continue; }
    ok++;
    const what = [patch.name ? `"${p.name}" -> "${patch.name}"` : p.name, 'alcohol_percentage' in patch ? `(alcool ${p.alcohol_percentage}° -> aucun)` : ''].join(' ');
    console.log('  OK', what.trim());
  }
  fs.writeFileSync(path.join(bk, 'produits-avant.json'), JSON.stringify(before, null, 1));
  fs.writeFileSync(path.join(bk, 'rollback.mjs'), `const key=${JSON.stringify(key)};const rows=${JSON.stringify(before)};
for (const {id,...rest} of rows){const r=await fetch('${SB}/rest/v1/products?id=eq.'+id,{method:'PATCH',headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify(rest)});console.log(id.slice(0,8),r.status);}
`, { mode: 0o600 });
  console.log(`\n${ok} produit(s) corrige(s).`);
})().catch((e) => { console.error('ERREUR :', e.message); process.exit(1); });
JS

printf '\n\033[1;33m==> Regeneration du site\033[0m\n'
( cd "$APP/seo" && node prerender.mjs ) 2>&1 | tail -2

printf '\n\033[1;32mTERMINE.\033[0m Annuler : node %s/rollback.mjs && (cd %s/seo && node prerender.mjs)\n' "$BK" "$APP"
