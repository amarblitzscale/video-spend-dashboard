// Local preview: serves dist/index.html at http://localhost:8765 (run `node build.mjs` first).
// Re-reads the file on every request, so a rebuild shows up on refresh.
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';

const PORT = +process.env.PORT || 8765;
createServer((req, res) => {
  try {
    res.setHeader('content-type', 'text/html; charset=utf-8');
    res.end(readFileSync(new URL('./dist/index.html', import.meta.url)));
  } catch (e) {
    res.statusCode = 500;
    res.end('dist/index.html not found: run node build.mjs first');
  }
}).listen(PORT, () => console.log(`Preview at http://localhost:${PORT}`));
