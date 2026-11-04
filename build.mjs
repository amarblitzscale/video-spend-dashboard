// Pulls the Metabase public question, injects the rows into template.html, writes dist/index.html.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const URL_ = process.env.METABASE_URL ||
  'https://metabase.kaip.in/api/public/card/89a30410-6d20-40b9-9462-f6c46e335fed/query/json';

const res = await fetch(URL_);
if (!res.ok) throw new Error(`Metabase returned ${res.status}`);
const d = await res.json();
if (!Array.isArray(d) || d.length < 50) throw new Error(`Unexpected response: ${Array.isArray(d) ? d.length + ' rows' : typeof d}`);

const need = ['golive_week','week_since_golive','golives','sellers_spending','sellers_on_video','total_spend',
  'video_spend','other_spend','video_sgmv_pct','other_sgmv_pct','partial_week','video_ctr_pct','other_ctr_pct'];
for (const k of need) if (!(k in d[0])) throw new Error(`Column missing from question: ${k}`);

const rows = d.map(r => [r.golive_week, +String(r.week_since_golive).slice(1), r.golives, r.sellers_spending,
  r.sellers_on_video, r.total_spend, r.video_spend, r.other_spend, r.video_sgmv_pct, r.other_sgmv_pct,
  r.partial_week ? 1 : 0, r.video_ctr_pct, r.other_ctr_pct]);

const html = readFileSync('template.html', 'utf8').replace('__ROWS__', JSON.stringify(rows));
mkdirSync('dist', { recursive: true });
writeFileSync('dist/index.html', html);
console.log(`Built dist/index.html from ${rows.length} rows`);
