#!/usr/bin/env node
// Push a signed TechPie .app to AppGallery Connect.
//
//   node scripts/agc-publish.mjs --channel stable --app dist/TechPie-1.0.4-ohos-arm64v8.app
//   node scripts/agc-publish.mjs --channel stable --app … --publish
//   node scripts/agc-publish.mjs --channel stable --app … --submit
//
// Two switches, deliberately separate, because one of them is a legal act:
//
//   (default)   plan only — reads AGC, prints what would happen, writes nothing
//   --publish   upload the package and fill the version in; the version stays at
//               "待提交", which is reversible (delete the draft version)
//   --submit    additionally submit for review, which starts an audit and cannot
//               be undone, only withdrawn
//
// `--channel test` drives a HarmonyOS test release (releaseType 6); `stable`
// drives the 全网 version (releaseType 1). The test channel needs contentRating
// and 备案 fields that Connect API cannot write — this script detects the
// resulting refusal and says so instead of pretending.
//
// Credentials: AGC_CLIENT_ID / AGC_CLIENT_SECRET / AGC_APP_ID from the
// environment, or from .env at the repository root (gitignored).

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { basename, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const HOST = 'https://connect-api.cloud.huawei.com';
const PACKAGE_NAME = 'com.geekpie.techpie';

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const opt = (name, fallback = '') => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};

const channel = opt('channel', 'stable');
const appFile = opt('app') ? resolve(ROOT, opt('app')) : '';
const submit = flag('submit');
const publish = flag('publish') || submit;
const force = flag('force');
const notesArg = opt('notes');
const testDays = Number(opt('days', '7'));

if (!['stable', 'test'].includes(channel)) {
  throw new Error(`--channel must be stable or test, got "${channel}"`);
}
if (publish && !appFile) {
  throw new Error('--publish/--submit needs --app <signed .app>');
}
if (publish && !existsSync(appFile)) {
  throw new Error(`No such file: ${appFile}`);
}

function loadEnv() {
  const path = resolve(ROOT, '.env');
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim();
    if (!process.env[key]) {
      process.env[key] = trimmed.slice(index + 1).trim().replace(/^["']|["']$/g, '');
    }
  }
}

loadEnv();
for (const key of ['AGC_CLIENT_ID', 'AGC_CLIENT_SECRET', 'AGC_APP_ID']) {
  if (!process.env[key]) throw new Error(`${key} is missing (environment or .env)`);
}
const { AGC_CLIENT_ID: clientId, AGC_CLIENT_SECRET: clientSecret, AGC_APP_ID: appId } = process.env;

let authHeaders;

async function call(path, { method = 'GET', body } = {}) {
  const res = await fetch(HOST + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...authHeaders },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`${method} ${path} → HTTP ${res.status}, not JSON: ${text.slice(0, 300)}`);
  }
  // AGC answers HTTP 200 with ret.code != 0 for business refusals; surface those.
  if (!res.ok || (payload.ret && payload.ret.code)) {
    const error = new Error(`${method} ${path} → HTTP ${res.status}: ${text.slice(0, 400)}`);
    error.agc = payload.ret;
    throw error;
  }
  return payload;
}

async function authenticate() {
  const res = await fetch(`${HOST}/api/oauth2/v1/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ grant_type: 'client_credentials', client_id: clientId, client_secret: clientSecret }),
  });
  const body = await res.json();
  if (!body.access_token) throw new Error(`token: ${JSON.stringify(body).slice(0, 300)}`);
  authHeaders = { client_id: clientId, Authorization: `Bearer ${body.access_token}`, appId };
}

/// versionName/versionCode from the pack itself, so what we publish is what the
/// artifact says rather than what a flag claims.
function readPackVersion() {
  const name = opt('version-name');
  const code = opt('version-code');
  if (name && code) return { name, code: Number(code) };
  if (!appFile) throw new Error('Without --app, pass --version-name and --version-code');
  const info = JSON.parse(execFileSync('unzip', ['-p', appFile, 'pack.info'], { encoding: 'utf8' }));
  const app = info?.summary?.app ?? {};
  return { name: app.version?.name, code: app.version?.code };
}

function readNotes() {
  if (notesArg) return notesArg.slice(0, 1024);
  try {
    const changelog = readFileSync(resolve(ROOT, 'CHANGELOG.md'), 'utf8');
    const match = /^## \[([0-9.]+)\]([\s\S]*?)(?=^## \[|\Z)/m.exec(changelog);
    const text = (match ? match[2] : '').replace(/^#+.*$/gm, '').replace(/\s+/g, ' ').trim();
    if (text) return text.slice(0, 1024);
  } catch {
    /* fall through */
  }
  return '';
}

async function appInfo(releaseType, versionId) {
  const query = releaseType === 6 ? `&releaseType=6&versionId=${versionId}` : '';
  return call(`/api/publish/v3/app-info?appId=${appId}${query}`);
}

async function versions() {
  const body = await call('/api/publish/v3/version/brief-info/list', {
    method: 'POST',
    body: { packageName: PACKAGE_NAME },
  });
  return body.versionList ?? [];
}

/// The fields AMIS expects on a version record but the Publishing API will not
/// default: the content rating, the ICP filing (备案) and the privacy links all
/// live on the app, and a version created through the API starts without them —
/// which is why a submit is refused field by field
/// (`contentRating in amis is invalid`, then
/// `registeredIdType and registeredIdNumber can not be null`). Copy what the app
/// has; send nothing it does not, because AMIS distinguishes absent from null.
async function extInfoFromAppInfo() {
  const info = await call(`/api/publish/v3/app-info?appId=${appId}&lang=zh-CN`);
  const app = info.appInfo ?? {};
  const ext = {};
  const copy = (to, from = to) => {
    if (app[from] != null && app[from] !== '') ext[to] = app[from];
  };
  copy('contentRating', 'contentRate');
  copy('registeredDclType');
  copy('registeredIdType');
  copy('registeredIdNumber');
  copy('registeredEntity');
  copy('registeredEntityName');
  copy('privacyPolicy');
  copy('privacyRightsUrl');
  copy('privacyAgreementId');
  copy('userAgreementIds');
  return ext;
}

async function uploadPackage() {
  const bytes = readFileSync(appFile);
  const fileName = basename(appFile);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  const upload = await call(
    `/api/publish/v2/upload-url/for-obs?appId=${appId}&fileName=${encodeURIComponent(fileName)}` +
      `&contentLength=${bytes.length}&sha256=${sha256}`,
  );
  const { url, headers } = upload.urlInfo;
  const putHeaders = { ...headers, 'Content-Length': String(bytes.length) };
  delete putHeaders.Host; // undici refuses to set Host
  const put = await fetch(url, { method: 'PUT', headers: putHeaders, body: bytes });
  if (!put.ok) throw new Error(`upload → HTTP ${put.status}: ${(await put.text()).slice(0, 300)}`);
  console.log(`uploaded ${fileName} ${bytes.length} B sha256 ${sha256}`);
  return { fileName, objectId: upload.urlInfo.objectId, sha256, size: bytes.length };
}

async function waitParsed(pkgId) {
  for (let attempt = 1; attempt <= 40; attempt++) {
    const state = await call(`/api/publish/v3/package/compile/status?appId=${appId}&pkgIds=${pkgId}`);
    const status = state.pkgStateList?.[0]?.successStatus;
    if (status === 0) {
      console.log(`package ${pkgId} parsed`);
      return;
    }
    await new Promise((r) => setTimeout(r, 5000));
  }
  throw new Error(`package ${pkgId} still not parsed after 200s`);
}

/// Stable channel: the package becomes the draft of the 全网 version.
async function stable() {
  const { name, code } = readPackVersion();
  console.log(`stable channel: ${name} (versionCode ${code})`);

  const all = await versions();
  const existing = all.find(
    (v) => v.releaseType === 1 && (v.packageList ?? []).some((p) => p.versionCode === code),
  );
  if (existing) {
    console.log(`versionCode ${code} is already on the stable channel (state ${existing.state}, versionId ${existing.versionId})`);
    if (!force) {
      console.log('refusing to upload a second package for the same versionCode; pass --force to override');
      return 0;
    }
  }

  const info = await appInfo(1, existing?.versionId);
  const current = info.appInfo ?? {};
  console.log(`current 全网 state ${current.releaseState} (${current.versionNumber} / ${current.versionCode})`);

  if (!publish) {
    console.log('\nplan only: would upload, write app-package-info, set newFeatures, then stop at 待提交');
    console.log(submit ? 'would then POST /app-submit (review)' : '(--submit not given, so nothing would be submitted)');
    return 0;
  }

  const { fileName, objectId } = await uploadPackage();
  const attached = await call(`/api/publish/v3/app-package-info?appId=${appId}`, {
    method: 'PUT',
    body: { fileName, objectId },
  });
  const pkgId = attached.packageId;
  console.log(`package ${pkgId} attached to the 全网 version`);
  await waitParsed(pkgId);

  const notes = readNotes();
  if (notes) {
    await call(`/api/publish/v3/app-language-info?appId=${appId}`, {
      method: 'PUT',
      body: { lang: 'zh-CN', newFeatures: notes },
    });
    console.log('newFeatures set from CHANGELOG.md');
  } else {
    console.log('warning: no CHANGELOG text for this version; leaving newFeatures untouched');
  }

  const after = await versions();
  const version = after.find((v) => v.releaseType === 1 && (v.packageList ?? []).some((p) => p.versionCode === code));
  console.log(`version is now state ${version?.state ?? '?'} (7 = 待提交), versionId ${version?.versionId ?? '?'}`);

  if (!submit) {
    console.log('\nstopped at 待提交 (--submit not given). Review it in the console, or re-run with --submit.');
    return 0;
  }

  await call(`/api/publish/v3/app-submit?appId=${appId}`, {
    method: 'POST',
    body: { releaseType: 1, releasePhase: 0 },
  });
  console.log('submitted for review');
  return 0;
}

/// Test channel. A test version carries its own package, and AGC refuses one
/// whose device types include 智慧屏 (releaseType 6 does not support it).
async function test() {
  const { name, code } = readPackVersion();
  console.log(`test channel: ${name} (versionCode ${code})`);

  const all = await versions();
  const existing = all.find(
    (v) => v.releaseType === 6 && (v.packageList ?? []).some((p) => p.versionCode === code),
  );
  const drafts = all.filter((v) => v.releaseType === 6 && v.state === 7);
  console.log(`test versions: ${all.filter((v) => v.releaseType === 6).length}, drafts ${drafts.length}`);

  if (!publish) {
    console.log('\nplan only: would create/reuse a test version, upload, bind, fill texts, then stop at 待提交');
    console.log('note: submitting a test version needs contentRating and 备案 fields that only the console writes');
    return 0;
  }

  if (existing && !force) {
    console.log(`versionCode ${code} already has a test version ${existing.versionId} (state ${existing.state})`);
    if (existing.state !== 7) {
      console.log('refusing to touch a test version that is not a draft; pass --force to override');
      return 0;
    }
  }

  const versionId =
    existing?.versionId ??
    (
      await call(`/api/publish/v2/test/app/version?appId=${appId}`, {
        method: 'POST',
        body: { releaseType: 6, testType: 4, testDesc: `${name} 公开测试`, onshelfSelfDetect: 1 },
      })
    ).versionId;
  console.log(`test version ${versionId}`);

  const { fileName, objectId } = await uploadPackage();
  const bound = await call(`/api/publish/v2/test/version/pkg?appId=${appId}`, {
    method: 'POST',
    body: { distributeMode: 1, file: { fileName, objectId } },
  });
  const pkgId = bound.pkgVersion?.[0];
  console.log(`bound test package ${pkgId}`);
  await waitParsed(pkgId);

  await call(`/api/publish/v2/test/app/version?appId=${appId}`, {
    method: 'PUT',
    body: {
      versionId,
      pkgId,
      languages: [
        { language: 'zh-CN', appName: 'TechPie', appDesc: '上海科技大学校园第三方服务客户端。', newFeatures: readNotes() || name },
      ],
      // 智慧屏 is not a valid device type for releaseType 6.
      deviceTypes: [
        { deviceType: 4, appAdapters: '' },
        { deviceType: 5, appAdapters: '' },
        { deviceType: 19, appAdapters: '' },
      ],
      distCountryList: 'CN',
      // AMIS reads the filing and the privacy links from here; a version made by
      // the API has none of them, and the submit is refused field by field.
      extInfo: await extInfoFromAppInfo(),
      openTestInfo: {
        startTime: Date.now(),
        endTime: Date.now() + testDays * 86400_000,
        testDesc: `${name} 公开测试`,
        testTaskInfo: { groupInfos: [], needShareLink: 1, publicTestInstallLimit: 100000, displayArea: '1', needNotify: 1 },
      },
    },
  });
  console.log(`test version ${versionId} filled; state should be 7 (待提交)`);

  if (!submit) {
    console.log('\nstopped at 待提交 (--submit not given)');
    return 0;
  }

  try {
    await call(`/api/publish/v2/test/app/version/submit?appId=${appId}`, { method: 'POST', body: { versionId } });
    console.log('test version submitted for review');
    return 0;
  } catch (error) {
    if (error.agc?.code === 204144692) {
      console.error(
        `AGC refused the test submission: ${error.agc.msg}\n` +
          'AMIS validates the version record and names the field it wants; the fields it\n' +
          'reads live on the app, which is why this script copies them into `extInfo`\n' +
          '(content rating, 备案 and privacy links). A field still named above is one the\n' +
          'app does not carry either — fill it in the console once, for the app, and the\n' +
          'copy picks it up on the next run. Nothing here can be sent from the API client\n' +
          'alone.',
      );
      return 2;
    }
    throw error;
  }
}

await authenticate();
const code = channel === 'stable' ? await stable() : await test();
process.exit(code);
