// npm install playwright
// node scripts/playwright-server.mjs
import { chromium } from 'playwright';
import crypto from 'node:crypto';
import fs from 'node:fs';

const wsPath = `pw-${crypto.randomUUID()}`;
const server = await chromium.launchServer({
  channel: 'chrome',      // launches branded Chrome
  headless: false,        // or true
  host: '127.0.0.1',
  port: 9333,
  wsPath,                 // keep unguessable
});

const endpoint = server.wsEndpoint();
fs.writeFileSync('/tmp/pw-ws-endpoint', endpoint);
console.log(endpoint);

process.on('SIGINT', async () => { await server.close(); process.exit(0); });
process.on('SIGTERM', async () => { await server.close(); process.exit(0); });
