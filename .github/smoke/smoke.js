// Revisión automática (smoke test): abre cada página en un navegador y falla si
// alguna truena con un error de JavaScript al cargar. No inicia sesión ni escribe
// nada: cualquier POST/PATCH/DELETE hacia Supabase se bloquea antes de salir.
// Uso: node .github/smoke/smoke.js index.html [otra.html ...]
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const RAIZ = process.cwd();
const PAGINAS = process.argv.slice(2);
const ESPERA_MS = 6000;
// Errores que no son del código de la app (red de terceros, etc.)
const IGNORAR = [/googletagmanager/i, /gtag/i, /Failed to fetch/i, /NetworkError/i, /Load failed/i];

const TIPOS = { '.html':'text/html', '.js':'application/javascript', '.json':'application/json',
  '.css':'text/css', '.png':'image/png', '.jpg':'image/jpeg', '.svg':'image/svg+xml', '.webp':'image/webp' };

function servidor(){
  return new Promise(res => {
    const srv = http.createServer((req, resp) => {
      const p = decodeURIComponent(req.url.split('?')[0]);
      const f = path.join(RAIZ, p === '/' ? 'index.html' : p);
      if(!f.startsWith(RAIZ) || !fs.existsSync(f) || fs.statSync(f).isDirectory()){ resp.writeHead(404); return resp.end(); }
      resp.writeHead(200, { 'Content-Type': TIPOS[path.extname(f)] || 'application/octet-stream' });
      fs.createReadStream(f).pipe(resp);
    });
    srv.listen(0, '127.0.0.1', () => res(srv));
  });
}

(async () => {
  if(!PAGINAS.length){ console.error('Falta la lista de páginas'); process.exit(2); }
  const srv = await servidor();
  const base = 'http://127.0.0.1:' + srv.address().port + '/';
  const navegador = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
  let fallas = 0;
  for(const pag of PAGINAS){
    const ctx = await navegador.newContext({ serviceWorkers: 'block' });
    const page = await ctx.newPage();
    const errores = [];
    await page.route('**/*', route => {
      const r = route.request();
      if(/supabase\.co/i.test(r.url()) && r.method() !== 'GET' && r.method() !== 'OPTIONS') return route.abort();
      return route.continue();
    });
    page.on('pageerror', e => { const m = String(e && (e.stack || e.message) || e); if(!IGNORAR.some(rx => rx.test(m))) errores.push(m); });
    page.on('dialog', d => d.dismiss().catch(() => {}));
    try{
      await page.goto(base + pag, { waitUntil: 'load', timeout: 60000 });
      await page.waitForTimeout(ESPERA_MS);
    }catch(e){ errores.push('No cargó: ' + e.message); }
    if(errores.length){
      fallas++;
      console.log('❌ ' + pag + ' — ' + errores.length + ' error(es):');
      errores.slice(0, 10).forEach(m => console.log('   • ' + m.split('\n').slice(0, 3).join('\n     ')));
    } else {
      console.log('✅ ' + pag + ' cargó sin errores');
    }
    await ctx.close();
  }
  await navegador.close();
  srv.close();
  process.exit(fallas ? 1 : 0);
})();
