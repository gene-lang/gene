#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

async function main() {
  const stateFile = process.argv[2];
  const optsRaw = process.argv[3] || '{}';
  if (!stateFile) {
    process.stderr.write('Usage: node playwright_daemon.mjs <state_file> <json_opts>\n');
    process.exit(1);
    return;
  }

  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (err) {
    process.stderr.write(`Playwright is not installed: ${err.message}\n`);
    process.exit(1);
    return;
  }

  const opts = JSON.parse(optsRaw);
  const launchOptions = {
    channel: opts.channel || 'chrome',
    headless: opts.headless !== undefined ? !!opts.headless : true,
    host: opts.host || '127.0.0.1',
    port: Number(opts.port || 9333)
  };

  const server = await chromium.launchServer(launchOptions);

  const state = {
    pid: process.pid,
    ws_endpoint: server.wsEndpoint(),
    host: launchOptions.host,
    port: launchOptions.port,
    channel: launchOptions.channel,
    headless: launchOptions.headless,
    started_at_ms: Date.now()
  };
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  fs.writeFileSync(stateFile, JSON.stringify(state), 'utf8');

  const cleanup = async () => {
    try {
      fs.unlinkSync(stateFile);
    } catch {
      // ignore
    }
    try {
      await server.close();
    } catch {
      // ignore
    }
    process.exit(0);
  };

  process.on('SIGTERM', cleanup);
  process.on('SIGINT', cleanup);

  // Keep process alive while browser server is running.
  await new Promise(() => {});
}

main().catch((err) => {
  process.stderr.write(`playwright_daemon failed: ${err.message}\n`);
  process.exit(1);
});
