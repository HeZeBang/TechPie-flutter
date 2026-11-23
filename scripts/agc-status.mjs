#!/usr/bin/env node
// Query AppGallery Connect for the state of a TechPie release.
//
//   node scripts/agc-status.mjs
//
// Credentials come from the environment, or from .env at the repository root
// (gitignored), as AGC_CLIENT_ID / AGC_CLIENT_SECRET / AGC_APP_ID. They are an
// AGC "API client" credential (开发者管理 > ID、证书和Profile > 凭证): the
// Connect API exchanges them for an access token valid for 48 hours.
//
// Read-only: this never uploads, submits, withdraws or takes an app off shelf.

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const HOST = 'https://connect-api.cloud.huawei.com';

/// .env, but only for keys not already in the environment.
function loadEnvFile() {
  let text;
  try {
    text = readFileSync(resolve(ROOT, '.env'), 'utf8');
  } catch {
    return;
  }
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim();
    const value = trimmed.slice(index + 1).trim().replace(/^["']|["']$/g, '');
    if (!process.env[key]) process.env[key] = value;
  }
}

/// Huawei's releaseState, which means different things per release type.
const APP_STATE = {
  0: '已上架',
  1: '上架审核不通过',
  2: '已下架',
  3: '待上架/预约上架',
  4: '审核中',
  5: '升级审核中',
  6: '申请下架',
  7: '草稿/准备提交',
  8: '升级审核不通过',
  9: '下架审核不通过',
  10: '开发者已下架',
  11: '撤销上架',
  12: '预审中',
  13: '预审不通过',
};

const DEVICE = { 4: '手机', 5: '平板', 8: '智慧屏', 12: '智能手表', 14: '运动手表', 19: 'PC/2in1' };
const REVIEW = { 1: '等待审核', 2: '正在审核' };

async function api(path, { method = 'GET', body, headers } = {}) {
  const res = await fetch(HOST + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`${path} → HTTP ${res.status}, not JSON: ${text.slice(0, 200)}`);
  }
  if (!res.ok) throw new Error(`${path} → HTTP ${res.status}: ${text.slice(0, 300)}`);
  return payload;
}

function requireEnv(key) {
  const value = process.env[key];
  if (!value) {
    throw new Error(
      `${key} is not set. Put AGC_CLIENT_ID, AGC_CLIENT_SECRET and AGC_APP_ID in ` +
        `.env (gitignored), or export them.`,
    );
  }
  return value;
}

function formatTime(utc) {
  if (!utc) return '-';
  // AGC reports UTC as "YYYY-MM-DD HH:mm:ss"; show it in the machine's zone too.
  const iso = utc.replace(' ', 'T') + 'Z';
  const local = new Date(iso);
  return Number.isNaN(local.getTime()) ? utc : `${utc} UTC (${local.toLocaleString()})`;
}

async function main() {
  loadEnvFile();
  const clientId = requireEnv('AGC_CLIENT_ID');
  const clientSecret = requireEnv('AGC_CLIENT_SECRET');
  const appId = requireEnv('AGC_APP_ID');

  const token = await api('/api/oauth2/v1/token', {
    method: 'POST',
    body: { grant_type: 'client_credentials', client_id: clientId, client_secret: clientSecret },
  });
  if (!token.access_token) {
    throw new Error(`No access_token: ${JSON.stringify(token)}`);
  }
  const auth = { client_id: clientId, Authorization: `Bearer ${token.access_token}`, appId };

  const info = await api(`/api/publish/v3/app-info?appId=${appId}`, { headers: auth });
  if (info.ret?.code !== 0) throw new Error(`app-info: ${JSON.stringify(info.ret)}`);
  const app = info.appInfo ?? {};

  const versions = await api('/api/publish/v3/version/brief-info/list', {
    method: 'POST',
    headers: auth,
    body: { packageName: process.env.AGC_PACKAGE_NAME || 'com.geekpie.techpie' },
  });

  console.log(`appId ${appId}`);
  console.log(`状态   ${app.releaseState} ${APP_STATE[app.releaseState] ?? '未知'}` +
    (app.reviewState ? `；审核 ${app.reviewState} ${REVIEW[app.reviewState] ?? ''}` : ''));
  console.log(`版本   ${app.versionNumber ?? '-'} (versionCode ${app.versionCode ?? '-'})` +
    (app.onShelfVersionCode ? `；在架 ${app.onShelfVersionNumber} (${app.onShelfVersionCode})` : '；当前无在架版本'));
  console.log(`versionId ${app.versionId ?? '-'}`);
  console.log(`设备   ${(app.deviceTypes ?? []).map((d) => `${DEVICE[d.deviceType] ?? d.deviceType}`).join('、') || '-'}`);
  console.log(`发布地 ${app.publishCountry ?? '-'}；分级 ${app.contentRate ?? '-'}`);
  console.log(`更新   ${formatTime(app.updateTime)}`);
  console.log(`上架   ${formatTime(app.releaseTime)}`);
  const opinion = info.auditInfo?.auditOpinion;
  console.log(`审核意见 ${opinion ? `\n${opinion}` : '(无)'}`);

  console.log('\n版本列表：');
  for (const v of versions.versionList ?? []) {
    const pkg = (v.packageList ?? [])[0] ?? {};
    const kind = v.releaseType === 6 ? '测试' : '全网';
    console.log(
      `  ${kind} ${pkg.versionName ?? '-'} (${pkg.versionCode ?? '-'})` +
        ` state ${v.state} ${APP_STATE[v.state] ?? ''} phase ${v.releasePhase ?? 0}` +
        ` versionId ${v.versionId} packageId ${pkg.packageId ?? '-'}`,
    );
  }
}

await main();
