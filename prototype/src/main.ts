/**
 * Browser entry point. Everything else happens in src/game/app.ts.
 */
import { createApp } from './game/app';

const mount = document.getElementById('overdub');
if (!mount) throw new Error('OVERDUB: #overdub mount element is missing from index.html');
const app = createApp(mount);
app.start();
