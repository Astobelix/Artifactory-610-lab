#!/usr/bin/env node
// Validation visuelle ponctuelle sur le runner ephemere, aucune URL publique.
import { chromium } from 'playwright';
import fs from 'node:fs/promises';
import path from 'node:path';

const phase = process.argv[2];
const routes = {
  '6.1.0': ['/artifactory/webapp/#/home', '/artifactory/webapp/', '/artifactory/'],
  '6.23.42': ['/artifactory/webapp/#/home', '/artifactory/webapp/', '/artifactory/'],
  '7.161.26': ['/ui/', '/artifactory/'],
  '7.161.26-restart': ['/ui/', '/artifactory/'],
};
if (!Object.hasOwn(routes, phase)) {
  throw new Error('Usage: node scripts/ci_visual_check.mjs <6.1.0|6.23.42|7.161.26|7.161.26-restart>');
}

const base = 'http://127.0.0.1:8080';
const dir = path.resolve('captures-artifactory');
await fs.mkdir(dir, { recursive: true });
const browser = await chromium.launch({ headless: true });
const results = { phase, checked_at: new Date().toISOString(), base, views: [] };
let valid = true;

async function capture(label, viewport, isMobile) {
  const context = await browser.newContext({
    viewport, deviceScaleFactor: isMobile ? 2 : 1,
    isMobile, hasTouch: isMobile,
    colorScheme: 'light',
    locale: 'fr-FR'
  });
  const page = await context.newPage();
  const messages = [];
  page.on('pageerror', (err) => messages.push('pageerror: ' + err.message.slice(0, 200)));
  page.on('response', (res) => {
    if (res.status() >= 500 && res.url().startsWith(base)) {
      messages.push('HTTP ' + res.status() + ': ' + res.url().slice(0, 160));
    }
  });
  let selected;
  for (const route of routes[phase]) {
    const record = { requested: base + route };
    try {
      const response = await page.goto(base + route, { waitUntil: 'domcontentloaded', timeout: 45000 });
      record.http_status = response?.status() ?? null;
      await page.waitForTimeout(7000);
      record.url = page.url();
      record.title = await page.title();
      const state = await page.evaluate(() => ({
        text: document.body?.innerText?.trim()?.slice(0, 500) ?? '',
        inputCount: document.querySelectorAll('input').length,
        buttonCount: document.querySelectorAll('button').length
      }));
      record.visibleText = state.text.replaceAll(/\s+/g, ' ').slice(0, 250);
      record.inputCount = state.inputCount;
      record.buttonCount = state.buttonCount;
      record.healthy = Boolean(
        record.http_status !== null && record.http_status < 400 &&
        !/\b(404 not found|502 bad gateway|503 service unavailable)\b/i.test(record.visibleText) &&
        (state.text.length >= 12 || state.inputCount > 0 || state.buttonCount > 0)
      );
      if (record.healthy) {
        selected = record;
        break;
      }
      messages.push('Vue insuffisante : ' + JSON.stringify(record));
    } catch (err) {
      messages.push('Navigation ' + route + ': ' + String(err).slice(0, 300));
    }
  }
  const screenshot = phase + '-' + label + '.png';
  await page.screenshot({ path: path.join(dir, screenshot), fullPage: false });
  const info = { label, viewport, screenshot, ...selected, warnings: messages.slice(-12) };
  if (!selected) {
    info.healthy = false;
    info.finalUrl = page.url();
    info.title = await page.title().catch(() => '');
    info.visibleText = await page.locator('body').innerText().then(x => x.slice(0, 250)).catch(() => '');
    valid = false;
  }
  results.views.push(info);
  console.log(label + ' ' + (info.healthy ? 'OK' : 'ECHEC') + ' ' + (info.url || info.finalUrl) +
              ' texte=' + JSON.stringify(info.visibleText ?? ''));
  await context.close();
}

try {
  await capture('desktop', { width: 1440, height: 900 }, false);
  await capture('android', { width: 412, height: 915 }, true);
} finally {
  await fs.writeFile(path.join(dir, phase + '-rapport.json'), JSON.stringify(results, null, 2) + '\n');
  await browser.close();
}
if (!valid) {
  process.exitCode = 1;
  console.error('ECHEC : interface absente ou vide ; consulter captures et rapport JSON.');
} else {
  console.log('SUCCES : capture desktop et Android et interface non vide pour ' + phase);
}
