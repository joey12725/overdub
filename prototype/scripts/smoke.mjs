// Boots the real game in headless Chromium and walks title -> campaign -> a level -> one take.
// Usage: node scripts/smoke.mjs [outDir] [levelIndex]
import { chromium } from 'playwright';
import { createServer } from 'vite';
import { mkdirSync } from 'node:fs';

const out = process.argv[2] ?? 'test-results/smoke';
mkdirSync(out, { recursive: true });
const server = await createServer({ server: { port: 5199, strictPort: false }, logLevel: 'error' });
await server.listen();
const url = server.resolvedUrls.local[0];
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
const shot = async (name) => { await page.screenshot({ path: `${out}/${name}.png` }); console.log('shot', name); };
const key = async (k, wait = 400) => { await page.keyboard.press(k); await page.waitForTimeout(wait); };

await page.goto(url);
await page.waitForTimeout(2500);
await shot('01-title');
const info = await page.evaluate(() => Object.keys(window.__overdub ?? {}));
console.log('__overdub keys', info);
await key('Enter', 1200);
await shot('02-after-enter');
await key('Enter', 1500);
await shot('03-after-enter-2');
await key('Enter', 1500);
await shot('04-after-enter-3');
await key('Enter', 3500);
await shot('05-countin-or-recording');
await page.keyboard.down('d');
await page.waitForTimeout(1500);
await page.mouse.click(900, 400);
await shot('06-recording');
await page.keyboard.up('d');
await page.keyboard.down('s');
await page.waitForTimeout(1500);
await page.keyboard.up('s');
await key('Space', 300);
await shot('07-recording-2');
await page.waitForTimeout(7000);
await shot('08-after-take');
await page.waitForTimeout(6000);
await shot('09-later');
console.log('ERRORS', JSON.stringify(errors.slice(0, 20), null, 1));
await browser.close();
await server.close();
