// Pulls the Metabase public question, injects the rows into template.html, writes dist/index.html.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const URL_ = process.env.METABASE_URL ||
  'https://metabase.kaip.in/api/public/card/69814e4c-a8a1-4022-aa10-92b0201e7593/query/json';

let d;
if (process.env.LOCAL_JSON) d = JSON.parse(readFileSync(process.env.LOCAL_JSON, 'utf8'));   // local testing only
else {
  const res = await fetch(URL_);
  if (!res.ok) throw new Error(`Metabase returned ${res.status}`);
  d = await res.json();
}
if (!Array.isArray(d) || d.length < 50) throw new Error(`Unexpected response: ${Array.isArray(d) ? d.length + ' rows' : typeof d}`);

const need = ['golive_week','week_since_golive','seller_class','golives','sellers_spending','sellers_on_video','total_spend',
  'video_spend','other_spend','video_gmv','other_gmv','video_imp','other_imp','video_clk','other_clk',
  'video_orders','other_orders','partial_week','category'];
for (const k of need) if (!(k in d[0])) throw new Error(`Column missing from question: ${k}`);

const rows = d.map(r => [r.golive_week, +String(r.week_since_golive).slice(1), r.seller_class, r.golives, r.sellers_spending,
  r.sellers_on_video, r.total_spend, r.video_spend, r.other_spend, r.video_gmv, r.other_gmv, r.video_imp, r.other_imp, r.video_clk, r.other_clk,
  r.video_orders, r.other_orders, r.partial_week ? 1 : 0, r.category]);

const clientId = process.env.GOOGLE_CLIENT_ID || '';
if (!clientId) console.warn('GOOGLE_CLIENT_ID is not set: the sign-in page will show "not configured".');
const html = readFileSync('template.html', 'utf8')
  .replace('__ROWS__', JSON.stringify(rows))
  .replace('__GOOGLE_CLIENT_ID__', clientId);
mkdirSync('dist', { recursive: true });
writeFileSync('dist/index.html', html);
console.log(`Built dist/index.html from ${rows.length} rows`);
