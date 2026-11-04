#!/usr/bin/env node
// Create (or resume) an AppGallery Connect *test* release that carries the same
// software as a TechPie release, and submit it for test review.
//
//   node scripts/agc-test-version.mjs --app dist/TechPie-1.0.3-ohos-arm64v8.app
//   node scripts/agc-test-version.mjs --version-id 1234 --submit
//
// Why a script: a test version is a separate version with its own package, so
// AGC needs the .app uploaded again — there is no "clone" call. The flow is the
// one Testing API documents:
//
//   1. POST /api/publish/v2/test/app/version        create the test version
//   2. GET  /api/publish/v2/upload-url/for-obs      ask where to put the .app
//   3. PUT  <that url>                              upload the bytes
//   4. POST /api/publish/v2/test/version/pkg        bind the uploaded file
//   5. GET  /api/publish/v3/package/compile/status  wait for AGC to parse it
//   6. PUT  /api/publish/v2/test/app/version        attach package + texts
//   7. POST /api/publish/v2/test/app/version/submit submit for test review
//
// Steps 1-6 run by default and print the versionId; --submit adds step 7, which
// is the only step that publishes anything. Re-running with --version-id skips
// 1-6 and goes straight to whatever is asked.

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { basename, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const HOST = 'https://connect-api.cloud.huawei.com';

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const opt = (name, fallback) => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};

const appFile = resolve(ROOT, opt('app', 'dist/TechPie-1.0.3-ohos-arm64v8.app'));
const testDesc = opt('test-desc', 'TechPie 1.0.3 公开测试');
const days = Number(opt('days', '7'));
const installLimit = Number(opt('install-limit', '100000'));
const versionIdArg = opt('version-id', '');
const submit = flag('submit');

function loadEnv() {
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
    if (!process.env[key]) {
      process.env[key] = trimmed.slice(index + 1).trim().replace(/^["']|["']$/g, '');
    }
  }
}

loadEnv();
for (const key of ['AGC_CLIENT_ID', 'AGC_CLIENT_SECRET', 'AGC_APP_ID']) {
  if (!process.env[key]) throw new Error(`${key} is missing (put it in .env)`);
}
const { AGC_CLIENT_ID: clientId, AGC_CLIENT_SECRET: clientSecret, AGC_APP_ID: appId } = process.env;

let authHeaders;

async function call(path, { method = 'GET', body, headers = {}, raw = false } = {}) {
  const res = await fetch(HOST + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...authHeaders, ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (raw) return { status: res.status, text };
  let payload;
  try {
    payload = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`${method} ${path} → HTTP ${res.status}, not JSON: ${text.slice(0, 300)}`);
  }
  if (!res.ok || payload.ret?.code) {
    throw new Error(`${method} ${path} → HTTP ${res.status}: ${text.slice(0, 400)}`);
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

/// The texts AGC insists on for a test version: appDesc and newFeatures are
/// mandatory. Reuse what the 全网 version already says rather than inventing
/// store copy here.
/// AGC returns materials as short-lived OBS URLs; the API takes objectIds, which
/// sit in the URL path (".../CN/2026091715/xxx.png?X-Amz-...").
function objectId(value) {
  if (!value) return '';
  try {
    return new URL(value).pathname.replace(/^\//, '');
  } catch {
    return value.startsWith('CN/') ? value : '';
  }
}

async function currentTexts() {
  const info = await call(`/api/publish/v3/app-info?appId=${appId}&lang=zh-CN`);
  const lang = (info.languages ?? []).find((l) => l.lang === 'zh-CN') ?? {};
  const app = info.appInfo ?? {};
  // A test version does not inherit screenshots, and AGC refuses a submission
  // whose declared device types have no materials — so carry them over.
  const deviceMaterials = (lang.deviceMaterials ?? [])
    .map((m) => ({
      deviceType: m.deviceType,
      showType: m.showType ?? 1,
      appIcon: objectId(m.appIcon),
      screenShots: (m.screenShots ?? []).map(objectId).filter(Boolean),
    }))
    .filter((m) => m.appIcon);
  return {
    deviceMaterials,
    appName: lang.appName || 'TechPie',
    appDesc: lang.appDesc || '上海科技大学校园第三方服务客户端。',
    briefInfo: lang.briefInfo || '校园服务一站直达',
    privacyPolicy: app.privacyPolicy || '',
    privacyRightsUrl: app.privacyRightsUrl || '',
    // 备案信息: AGC refuses a test submission without these, and they live on the
    // app rather than on the version, so they are copied over.
    registeredIdType: app.registeredIdType,
    registeredIdNumber: app.registeredIdNumber,
    isAiGenerate: app.isAiGenerate ?? 0,
  };
}

/// versionName/versionCode inside the .app, so the test version is labelled with
/// what the package actually says rather than what we think it says.
function readNotes() {
  try {
    const changelog = readFileSync(resolve(ROOT, 'CHANGELOG.md'), 'utf8');
    const match = /^## \[1\.0\.3\]([\s\S]*?)(?=^## \[|\Z)/m.exec(changelog);
    const text = (match ? match[1] : '').replace(/^#+.*$/gm, '').replace(/\s+/g, ' ').trim();
    if (text) return text.slice(0, 1024);
  } catch {
    /* fall through */
  }
  return 'TechPie 1.0.3 公开测试版本。';
}


/// Attach the test version's texts, device types, test window and install quota.
/// Used right after creating a version, and again for `--update` when AGC asks
/// for another field before it will accept the submission.
async function updateTestVersion(versionId, pkgId) {
  const texts = await currentTexts();
  const now = Date.now();
  const updated = await call(`/api/publish/v2/test/app/version?appId=${appId}`, {
    method: 'PUT',
    body: {
      versionId,
      ...(pkgId ? { pkgId } : {}),
      languages: [
        {
          language: 'zh-CN',
          appName: texts.appName,
          appDesc: texts.appDesc,
          briefInfo: texts.briefInfo,
          newFeatures: readNotes(),
          ...(texts.deviceMaterials.length ? { deviceMaterials: texts.deviceMaterials } : {}),
        },
      ],
      deviceTypes: [
        { deviceType: 4, appAdapters: '' },
        { deviceType: 5, appAdapters: '' },
        { deviceType: 8, appAdapters: '', remoteControl: '1' },
        { deviceType: 19, appAdapters: '' },
      ],
      distCountryList: 'CN',
      extInfo: {
        privacyPolicy: texts.privacyPolicy,
        privacyRightsUrl: texts.privacyRightsUrl,
        registeredIdType: texts.registeredIdType,
        registeredIdNumber: texts.registeredIdNumber,
        isAiGenerate: texts.isAiGenerate,
      },
      openTestInfo: {
        startTime: now,
        endTime: now + days * 86400_000,
        testDesc,
        testTaskInfo: {
          groupInfos: [],
          needShareLink: 1,
          publicTestInstallLimit: installLimit,
          displayArea: '1',
          needNotify: 1,
        },
      },
    },
  });
  console.log(`updated test version ${versionId}: ${JSON.stringify(updated.ret)}`);
}

/// Upload the .app, bind it to the app's test channel and wait until AGC has
/// parsed it. Returns the package id the test version must reference.
async function uploadPackage() {
  const bytes = readFileSync(appFile);
  const fileName = basename(appFile);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  console.log(`package ${fileName} ${bytes.length} B sha256 ${sha256}`);

  const upload = await call(
  `/api/publish/v2/upload-url/for-obs?appId=${appId}&fileName=${encodeURIComponent(fileName)}` +
    `&contentLength=${bytes.length}&sha256=${sha256}`,
  );
  const { url, headers } = upload.urlInfo;
  const putHeaders = { ...headers, 'Content-Length': String(bytes.length) };
  delete putHeaders.Host; // undici refuses to set Host
  const put = await fetch(url, { method: 'PUT', headers: putHeaders, body: bytes });
  if (!put.ok) throw new Error(`upload → HTTP ${put.status}: ${(await put.text()).slice(0, 300)}`);
  console.log(`uploaded ${upload.urlInfo.objectId}`);

  const bound = await call(`/api/publish/v2/test/version/pkg?appId=${appId}`, {
  method: 'POST',
  body: { distributeMode: 1, file: { fileName, objectId: upload.urlInfo.objectId } },
  });
  const pkgId = bound.pkgVersion?.[0];
  if (!pkgId) throw new Error(`no pkgVersion: ${JSON.stringify(bound).slice(0, 200)}`);
  console.log(`bound test package ${pkgId}`);

  for (let attempt = 1; attempt <= 40; attempt++) {
  const state = await call(`/api/publish/v3/package/compile/status?appId=${appId}&pkgIds=${pkgId}`);
  const status = state.pkgStateList?.[0]?.successStatus;
  if (status === 0) {
    console.log('package parsed');
    break;
  }
  if (attempt === 40) throw new Error(`package still not parsed: ${JSON.stringify(state).slice(0, 200)}`);
  await new Promise((r) => setTimeout(r, 5000));
  }

  return pkgId;
}

async function main() {
  await authenticate();
  let versionId = versionIdArg;

  if (!versionId) {
    const created = await call(`/api/publish/v2/test/app/version?appId=${appId}`, {
      method: 'POST',
      body: { releaseType: 6, testType: 4, testDesc, onshelfSelfDetect: 1 },
    });
    versionId = created.versionId;
    console.log(`created test version ${versionId}`);

    const pkgId = await uploadPackage();
    await updateTestVersion(versionId, pkgId);
  } else if (flag('package')) {
    // Replace the software of an existing draft: new upload, new binding, same
    // texts and window. This is how a rebuilt versionCode reaches a test version.
    const pkgId = await uploadPackage();
    await updateTestVersion(versionId, pkgId);
  } else if (flag('update')) {
    // Re-apply the fields of an existing draft, e.g. after AGC rejected the
    // submission for a missing one (publicTestInstallLimit was such a case).
    await updateTestVersion(versionId, undefined);
  }

  if (!submit) {
    console.log(`\nNot submitted. Resume with:\n  node scripts/agc-test-version.mjs --version-id ${versionId} --submit`);
    return;
  }

  const submitted = await call(`/api/publish/v2/test/app/version/submit?appId=${appId}`, {
    method: 'POST',
    body: { versionId },
  });
  console.log(`submitted for test review: ${JSON.stringify(submitted.ret)} (versionId ${versionId})`);
}

await main();
