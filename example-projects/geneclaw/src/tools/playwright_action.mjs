#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isPidAlive(pid) {
  if (!pid || Number.isNaN(Number(pid))) return false;
  try {
    process.kill(Number(pid), 0);
    return true;
  } catch {
    return false;
  }
}

function loadState(stateFile) {
  if (!fs.existsSync(stateFile)) return null;
  try {
    return readJson(stateFile);
  } catch {
    return null;
  }
}

function resolveEndpoint(args, state) {
  return args.ws_endpoint || args.endpoint || process.env.PLAYWRIGHT_WS_ENDPOINT || (state ? state.ws_endpoint : '');
}

function resolveHost(args, state) {
  return args.host || process.env.PLAYWRIGHT_HOST || (state ? state.host : '') || '127.0.0.1';
}

function resolvePort(args, state) {
  const raw = args.port || process.env.PLAYWRIGHT_PORT || (state ? state.port : '') || 9333;
  const port = Number(raw);
  return Number.isFinite(port) && port > 0 ? port : 9333;
}

function resolveCdpUrl(args, state) {
  if (args.cdp_url) return args.cdp_url;
  if (process.env.PLAYWRIGHT_CDP_URL) return process.env.PLAYWRIGHT_CDP_URL;
  const host = resolveHost(args, state);
  const port = resolvePort(args, state);
  return `http://${host}:${port}`;
}

async function waitForServerState(stateFile, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const nextState = loadState(stateFile);
    if (nextState && nextState.ws_endpoint) {
      return nextState;
    }
    await sleep(200);
  }
  return null;
}

async function startManagedServer(args, stateFile) {
  const daemonScript = path.join(path.dirname(new URL(import.meta.url).pathname), 'playwright_daemon.mjs');
  const daemonOpts = {
    headless: args.headless !== undefined ? !!args.headless : true,
    channel: args.channel || 'chrome',
    host: resolveHost(args, null),
    port: resolvePort(args, null)
  };

  const child = spawn(process.execPath, [daemonScript, stateFile, JSON.stringify(daemonOpts)], {
    detached: true,
    stdio: 'ignore'
  });
  child.unref();

  const startTimeoutMs = Number(args.start_timeout_ms || 10000);
  const nextState = await waitForServerState(stateFile, startTimeoutMs);
  if (!nextState || !nextState.ws_endpoint) {
    return { ok: false, error: `Playwright server did not start within ${startTimeoutMs}ms` };
  }

  return { ok: true, started: true, state: nextState, ws_endpoint: nextState.ws_endpoint };
}

function output(result) {
  process.stdout.write(JSON.stringify(result));
}

async function run() {
  const reqFile = process.argv[2];
  const stateFile = process.argv[3];
  if (!reqFile || !stateFile) {
    output({ ok: false, error: 'Usage: node playwright_action.mjs <req_file> <state_file>' });
    process.exit(1);
  }

  const args = readJson(reqFile);
  const action = args.action || '';
  const state = loadState(stateFile);

  if (action === 'server_status') {
    if (!state) {
      output({ ok: true, running: false, state: null });
      return;
    }
    output({ ok: true, running: isPidAlive(state.pid), state });
    return;
  }

  if (action === 'server_stop') {
    if (!state) {
      output({ ok: true, stopped: false, message: 'No server state found' });
      return;
    }
    const running = isPidAlive(state.pid);
    if (running) {
      try {
        process.kill(Number(state.pid), 'SIGTERM');
      } catch {
        // ignore
      }
    }
    output({ ok: true, stopped: running, state });
    return;
  }

  if (action === 'server_start') {
    if (state && isPidAlive(state.pid)) {
      output({ ok: true, started: false, state, ws_endpoint: state.ws_endpoint });
      return;
    }
    const started = await startManagedServer(args, stateFile);
    if (!started.ok) {
      output(started);
      process.exit(1);
      return;
    }
    output(started);
    return;
  }

  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (err) {
    output({ ok: false, error: `Playwright is not installed: ${err.message}` });
    process.exit(1);
    return;
  }

  const timeout = Number(args.timeout_ms || 30000);
  const pageIndex = Number(args.page_index || 0);
  const connectTimeout = Number(args.connect_timeout_ms || Math.min(timeout, 7000));
  const autoStart = args.auto_start !== undefined ? !!args.auto_start : true;

  let browser;
  try {
    let connectedVia = '';
    const endpoint = resolveEndpoint(args, state);

    if (endpoint) {
      browser = await chromium.connect(endpoint, { timeout: connectTimeout });
      connectedVia = 'playwright_ws';
    } else {
      const cdpUrl = resolveCdpUrl(args, state);
      let cdpError = '';
      try {
        browser = await chromium.connectOverCDP(cdpUrl, { timeout: connectTimeout });
        connectedVia = 'cdp';
      } catch (err) {
        cdpError = err.message || String(err);
      }

      if (!browser && autoStart) {
        const started = await startManagedServer(args, stateFile);
        if (!started.ok) {
          const detail = cdpError ? ` CDP attach failed: ${cdpError}` : '';
          throw new Error(`Could not attach to existing browser or start managed browser.${detail} Start error: ${started.error}`);
        }
        browser = await chromium.connect(started.ws_endpoint, { timeout: connectTimeout });
        connectedVia = 'playwright_ws_started';
      }

      if (!browser) {
        const detail = cdpError ? ` ${cdpError}` : '';
        throw new Error(`No ws endpoint available and could not attach via CDP at ${cdpUrl}.${detail}`);
      }
    }

    let context = browser.contexts()[0];
    if (!context) {
      context = await browser.newContext();
    }

    async function getPage() {
      const pages = context.pages();
      if (pages.length === 0) {
        return await context.newPage();
      }
      if (pageIndex < 0 || pageIndex >= pages.length) {
        throw new Error(`page_index ${pageIndex} out of range (pages=${pages.length})`);
      }
      return pages[pageIndex];
    }

    if (action === 'list_pages') {
      const pages = context.pages();
      const data = [];
      for (let i = 0; i < pages.length; i++) {
        const p = pages[i];
        data.push({ index: i, url: p.url(), title: await p.title() });
      }
      output({ ok: true, connection: connectedVia, pages: data });
      return;
    }

    if (action === 'new_page') {
      const page = await context.newPage();
      if (args.url) {
        await page.goto(args.url, { timeout, waitUntil: args.wait_until || 'domcontentloaded' });
      }
      output({ ok: true, page_index: context.pages().length - 1, url: page.url(), title: await page.title() });
      return;
    }

    if (action === 'close_page') {
      const page = await getPage();
      await page.close();
      output({ ok: true, closed: true });
      return;
    }

    const page = await getPage();

    if (action === 'navigate') {
      if (!args.url) throw new Error('navigate requires url');
      await page.goto(args.url, { timeout, waitUntil: args.wait_until || 'domcontentloaded' });
      output({ ok: true, url: page.url(), title: await page.title() });
      return;
    }

    if (action === 'click') {
      if (!args.selector) throw new Error('click requires selector');
      await page.click(args.selector, { timeout });
      output({ ok: true, clicked: args.selector });
      return;
    }

    if (action === 'fill') {
      if (!args.selector) throw new Error('fill requires selector');
      await page.fill(args.selector, args.value || '', { timeout });
      output({ ok: true, filled: args.selector, value_length: (args.value || '').length });
      return;
    }

    if (action === 'press') {
      if (!args.selector) throw new Error('press requires selector');
      if (!args.key) throw new Error('press requires key');
      await page.press(args.selector, args.key, { timeout });
      output({ ok: true, pressed: args.key, selector: args.selector });
      return;
    }

    if (action === 'text') {
      if (!args.selector) throw new Error('text requires selector');
      const value = await page.textContent(args.selector, { timeout });
      output({ ok: true, text: value || '' });
      return;
    }

    if (action === 'content') {
      const html = await page.content();
      output({ ok: true, html });
      return;
    }

    if (action === 'screenshot') {
      const outPath = args.path || path.join('/tmp', `geneclaw-shot-${Date.now()}.png`);
      await page.screenshot({ path: outPath, fullPage: !!args.full_page, timeout });
      output({ ok: true, path: outPath });
      return;
    }

    if (action === 'evaluate') {
      if (!args.script) throw new Error('evaluate requires script');
      const value = await page.evaluate((code) => {
        // eslint-disable-next-line no-eval
        return eval(code);
      }, args.script);
      output({ ok: true, value });
      return;
    }

    output({ ok: false, error: `Unknown action: ${action}` });
    process.exit(1);
  } catch (err) {
    output({ ok: false, error: err.message });
    process.exit(1);
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch {
        // ignore close errors
      }
    }
  }
}

run().catch((err) => {
  output({ ok: false, error: err.message || String(err) });
  process.exit(1);
});
