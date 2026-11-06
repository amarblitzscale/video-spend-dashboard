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

// Daily question (day x cohort x class x hit1). Optional: without a URL the daily chart shows "not connected".
const DAILY_URL = process.env.METABASE_DAILY_URL ||
  'https://metabase.kaip.in/api/public/card/bc2471d0-816c-472c-8b55-116daaea11b1/query/json';
let dd = [];
if (process.env.LOCAL_DAILY_JSON) dd = JSON.parse(readFileSync(process.env.LOCAL_DAILY_JSON, 'utf8'));   // local testing only
else if (DAILY_URL) {
  const r2 = await fetch(DAILY_URL);
  if (!r2.ok) throw new Error(`Daily question returned ${r2.status}`);
  dd = await r2.json();
  for (const k of ['day','golive_week','seller_class','hit1','sellers','total_spend','video_spend'])
    if (!dd.length || !(k in dd[0])) throw new Error(`Column missing from daily question: ${k}`);
}
const daily = dd.map(r => [r.day, r.golive_week, r.seller_class, r.hit1, r.sellers, r.total_spend, r.video_spend]);
const clientId = process.env.GOOGLE_CLIENT_ID || '';
if (!clientId) console.warn('GOOGLE_CLIENT_ID is not set: the sign-in page will show "not configured".');
// The template is written to sit inside a page wrapper; add the document head for standalone hosting.
const HEAD = '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n<style>html,body{margin:0}img{max-width:100%}</style>\n';
const html = HEAD + readFileSync('template.html', 'utf8')
  .replace('__ROWS__', JSON.stringify(rows))
  .replace('__DAILY__', JSON.stringify(daily))
  .replace('__GOOGLE_CLIENT_ID__', clientId);
mkdirSync('dist', { recursive: true });
writeFileSync('dist/index.html', html);
console.log(`Built dist/index.html from ${rows.length} rows`);
