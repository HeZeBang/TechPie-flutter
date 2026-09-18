#!/usr/bin/env node
// Publish a signed OHOS App Pack to Huawei AppGallery Connect.
//
//   node scripts/appgallery-publish.mjs --file dist/TechPie-1.0.1-ohos-arm64v8-signed.app
//   node scripts/appgallery-publish.mjs --file <pack> --submit --remark "…"   # also submit for review
//   node scripts/appgallery-publish.mjs --file <pack> --dry-run               # validate, change nothing
//
// Credentials come from the environment (see CLAUDE.md → AppGallery):
//
//   AGC_APP_ID          the app's App ID in AGC
//   AGC_CLIENT_ID       a *team-level* AGC API client's ID      (project must be N/A)
//   AGC_CLIENT_SECRET   that client's secret
//   AGC_API_BASE        optional; defaults to the mainland endpoint. Accounts on
//                       the global site use https://connect-api-dre.cloud.huawei.com
//
// Uploading is safe to repeat — it adds a software package to the app's draft, and
// every upload gets a fresh objectId. Submitting for review is not repeatable in
// the same way: it is what puts a version in front of Huawei's reviewers, needs
// `--submit` *and* AGC_CONFIRM_SUBMIT=YES, and is therefore a deliberate act even
// in CI (the workflow exposes it as a dispatch input, off by default).
//
// Exit codes, following the convention the OHOS shell scripts use: 0 on success,
// 1 when a step failed, and 2 when the run was refused before any request went out
// (missing credentials, an unsigned or missing pack, a version already on the
// shelf, an unlock missing for --submit).

import { createHash } from 'node:crypto';
import { readFileSync, statSync, readdirSync } from 'node:fs';
import { basename, resolve } from 'node:path';

const DEFAULT_API_BASE = 'https://connect-api.cloud.huawei.com';

// AGC reports a package that is still being compiled with this business code and
// HTTP 200, so a submit has to wait rather than fail.
const PACKAGE_COMPILING_CODE = 204144719;
const SUBMIT_POLL_ATTEMPTS = 10;
const SUBMIT_POLL_INTERVAL_MS = 15_000;

// AGC's answer when the ID is not an API client's: "the type of clientId not
// match". It is the likeliest first-run failure, because three other values look
// like an API client's ID and none of them are.
const CLIENT_ID_TYPE_MISMATCH = 203886599;

const USAGE = `Publish a signed OHOS App Pack to Huawei AppGallery Connect.

  node scripts/appgallery-publish.mjs --file <pack.app> [options]

Options
  --file <path>    the signed .app to publish. Defaults to the only pack in dist/
                   that is not named -unsigned, so a release build needs no
                   argument.
  --submit         submit for review after registering the package. Also
                   requires AGC_CONFIRM_SUBMIT=YES — two deliberate acts.
  --remark <text>  optional note attached to the submit call.
  --dry-run        read AGC's current version and stop: proves the credentials
                   and that this version is publishable, without needing a pack
                   and without changing anything. Still talks to AGC.
  -h, --help       this text.

Environment: AGC_APP_ID, AGC_CLIENT_ID, AGC_CLIENT_SECRET, [AGC_API_BASE].
A local .env file is read when present (gitignored, and it never overrides a
value that is already in the environment).
`;

/// Read pubspec.yaml's version — the single source of truth for it, and what
/// hvigor stamps into the pack, so it is also the versionCode AGC will see.
function readPubspecVersion() {
  const declared = /^version:[ \t]*(\S+)[ \t]*$/m.exec(readFileSync('pubspec.yaml', 'utf8'))?.[1];
  if (!declared) {
    throw new Error('No version: line in pubspec.yaml');
  }
  const [, name, code] = /^([0-9][0-9.]*(?:-rc\.[0-9]+)?)(?:\+([0-9]+))?$/.exec(declared) ?? [];
  if (!name) {
    throw new Error(`Unrecognised version in pubspec.yaml: ${declared}`);
  }
  // Mirrors Flutter's own rule, which the OHOS generator follows too: no `+N`
  // means build 1.
  return { name, code: Number(code ?? 1) };
}

/// Thrown for anything that should stop the run before a request is sent.
class Refusal extends Error {}

function parseArgs(argv) {
  const options = { submit: false, dryRun: false, remark: '', file: null, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--file') options.file = argv[++i];
    else if (arg === '--remark') options.remark = argv[++i];
    else if (arg === '--submit') options.submit = true;
    else if (arg === '--dry-run') options.dryRun = true;
    else if (arg === '-h' || arg === '--help') options.help = true;
    else throw new Refusal(`Unknown argument: ${arg}`);
  }
  return options;
}

/// Where an artifact name has to be a *signed* pack: AppGallery validates the
/// signature on upload, so an unsigned one is rejected on their side with a
/// message far less useful than this.
function resolvePack(explicit) {
  if (explicit) {
    return resolve(explicit);
  }
  const candidates = (() => {
    try {
      return readdirSync('dist', { withFileTypes: true })
        // A publishable pack is the signed one, and `-unsigned` is what the names
        // rule puts on a pack nothing signed (CLAUDE.md → Artifact names) — so a
        // signed pack is the `.app` without it.
        .filter((entry) => entry.isFile() && entry.name.endsWith('.app') && !entry.name.includes('-unsigned'))
        .map((entry) => resolve('dist', entry.name));
    } catch {
      // No dist/ at all — the same refusal as an empty one, because "there is
      // nothing to publish here" is what the caller needs to hear either way.
      return [];
    }
  })();
  if (candidates.length === 1) {
    return candidates[0];
  }
  throw new Refusal(
    candidates.length === 0
      ? 'No signed App Pack in dist. Build one with signing material ' +
        '(OHOS_UNSIGNED=0 scripts/build-ohos-app.sh), or name one with --file.'
      : `More than one publishable pack in dist: ${candidates.join(', ')} — pick one with --file.`,
  );
}

function checkPack(path) {
  let size;
  try {
    size = statSync(path).size;
  } catch {
    throw new Refusal(`No such file: ${path}`);
  }
  if (!path.endsWith('.app')) {
    throw new Refusal(`Not an App Pack: ${path} (a .hap installs on a device; AppGallery takes .app)`);
  }
  if (path.includes('-unsigned')) {
    throw new Refusal(
      `${basename(path)} is unsigned, and AppGallery rejects an unsigned pack. ` +
        'Sign it first (OHOS_UNSIGNED=0 scripts/build-ohos-app.sh), then publish the pack that comes out.',
    );
  }
  return size;
}

/// Lowercase hex, deliberately: AGC copies this value straight into the OBS
/// header x-amz-content-sha256, which rejects uppercase with
/// XAmzContentSHA256Mismatch. (That is why the digest is not uppercased here even
/// though the release notes publish one in uppercase.)
function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

/// Read a local `.env` for a run from a developer machine, so the credentials do
/// not have to be re-exported in every shell — and so nothing changes in CI,
/// where they arrive through the environment. A value that is already set wins,
/// so a stale .env cannot silently shadow a workflow's own.
///
/// `.env` is gitignored; the same three values are the `appgallery-release`
/// environment's secrets.
function loadDotEnv() {
  let contents;
  try {
    contents = readFileSync('.env', 'utf8');
  } catch {
    return false;
  }
  for (const raw of contents.split('\n')) {
    const line = raw.trim().replace(/^export[ \t]+/, '');
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator === -1) continue;
    const name = line.slice(0, separator).trim();
    const value = line.slice(separator + 1).trim().replace(/^(['"])(.*)\1$/, '$2');
    if (name && process.env[name] === undefined) process.env[name] = value;
  }
  return true;
}

function credentials() {
  const missing = ['AGC_APP_ID', 'AGC_CLIENT_ID', 'AGC_CLIENT_SECRET'].filter(
    (name) => !process.env[name],
  );
  if (missing.length > 0) {
    throw new Refusal(`Missing ${missing.join(', ')} — an AGC API client's ID and secret, and the app's App ID.`);
  }
  return {
    appId: process.env.AGC_APP_ID,
    clientId: process.env.AGC_CLIENT_ID,
    clientSecret: process.env.AGC_CLIENT_SECRET,
    base: (process.env.AGC_API_BASE || DEFAULT_API_BASE).replace(/\/$/, ''),
  };
}

/// A 403 here is almost always the API client's scope rather than the call, so
/// say so: an API client created against a *project* cannot use the publishing
/// API at all.
function explain403(what) {
  return (
    `${what} returned 403. The usual cause is the API client, not the request: it must be ` +
    'team-level (AGC → 用户与访问 → API 密钥 → Connect API → 项目: N/A) with at least the ' +
    'APP管理员 role. See CLAUDE.md → AppGallery.'
  );
}

async function request(config, path, { method = 'GET', body, auth = true } = {}) {
  const headers = { Accept: 'application/json' };
  if (auth) {
    headers.client_id = config.clientId;
    headers.Authorization = `Bearer ${config.token}`;
  }
  // Any call carrying a body must say so — including the token request, which is
  // the one call that is not authenticated. Without this, fetch describes the
  // stringified body as text/plain, and AGC answers 400 for a body it cannot
  // deserialize (it reports the JSON it was handed as a String).
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(`${config.base}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  if (response.status === 403) {
    throw new Error(explain403(`${method} ${path}`));
  }
  if (!response.ok) {
    throw new Error(`${method} ${path} failed: HTTP ${response.status} ${text.slice(0, 500)}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${method} ${path} did not answer with JSON: ${text.slice(0, 200)}`);
  }
}

/// AGC wraps every publishing response in {ret: {code, msg}}; HTTP 200 alone is
/// not success.
function unwrap(what, data) {
  const code = data?.ret?.code ?? 0;
  if (code !== 0) {
    throw new Error(`${what} failed: ret.code=${code} ${data?.ret?.msg ?? ''} ${JSON.stringify(data).slice(0, 300)}`);
  }
  return data;
}

async function getToken(config) {
  const data = await request(
    config,
    '/api/oauth2/v1/token',
    {
      method: 'POST',
      auth: false,
      body: {
        grant_type: 'client_credentials',
        client_id: config.clientId,
        client_secret: config.clientSecret,
      },
    },
  );
  if (!data.access_token) {
    // AGC answers HTTP 200 for a client it refuses, so the reason only exists in
    // the body — and a wrong API client is the likeliest thing to be wrong here.
    const code = data?.ret?.code;
    throw new Error(
      `AGC refused the API client: ret.code=${code ?? '?'} ${data?.ret?.msg ?? JSON.stringify(data).slice(0, 200)}` +
        (code === CLIENT_ID_TYPE_MISMATCH
          ? '. That means this ID is not an API client\'s: take both values from AGC → 用户与访问 → ' +
            'API 密钥 → Connect API → API 客户端 (项目 must be N/A), rather than from the app\'s 客户端ID, ' +
            'its App ID, or an agconnect-services.json.'
          : ''),
    );
  }
  return data.access_token;
}

/// The version check is what keeps a run from being rejected at submit time, or
/// from silently re-registering a version users already have: AGC refuses a
/// versionCode that is not above the one on the shelf.
function checkVersionAgainstShelf(local, appInfo) {
  const onShelf = Number(appInfo.onShelfVersionCode ?? 0);
  const latest = Number(appInfo.versionCode ?? 0);
  const describe = `local ${local.name}+${local.code}, AGC on shelf ${appInfo.onShelfVersionNumber ?? 'none'}+${onShelf}, AGC latest ${appInfo.versionNumber ?? 'none'}+${latest}`;
  if (onShelf > 0 && local.code < onShelf) {
    throw new Refusal(`${describe} — this pack is behind AppGallery, so it would be rejected. Raise the build number.`);
  }
  if (local.code === onShelf && onShelf > 0) {
    throw new Refusal(`${describe} — already on the shelf. Raise the build number.`);
  }
  return { onShelf, latest, describe };
}

/// Register the uploaded object as the app's software package. This is the call
/// that puts a new version in the AGC draft — `app-file-info` is for icons and
/// screenshots and leaves 软件包管理 unchanged. Its body is exactly these two
/// fields: the API takes no size here.
async function registerPackage(config, { fileName, objectId }) {
  const data = await request(config, `/api/publish/v3/app-package-info?appId=${encodeURIComponent(config.appId)}`, {
    method: 'PUT',
    body: { objectId, fileName },
  });
  return unwrap('Registering the package', data);
}

async function submitForReview(config, remark) {
  const path = `/api/publish/v3/app-submit?appId=${encodeURIComponent(config.appId)}`;
  for (let attempt = 1; attempt <= SUBMIT_POLL_ATTEMPTS; attempt += 1) {
    const data = await request(config, path, { method: 'POST', body: remark ? { remark } : {} });
    const code = data?.ret?.code ?? 0;
    if (code === 0) {
      return `submitted (attempt ${attempt})`;
    }
    if (code !== PACKAGE_COMPILING_CODE) {
      throw new Error(`Submitting for review failed: ret.code=${code} ${data?.ret?.msg ?? ''}`);
    }
    // Still compiling: AGC answers 200 with a ret.code that says "wait", so the
    // only useful thing to do is wait longer.
    process.stderr.write(
      `  package still compiling (ret.code=${code}), retrying in ${SUBMIT_POLL_INTERVAL_MS / 1000}s (${attempt}/${SUBMIT_POLL_ATTEMPTS})\n`,
    );
    await new Promise((wait) => setTimeout(wait, SUBMIT_POLL_INTERVAL_MS));
  }
  throw new Error(
    `AGC was still compiling the package after ${(SUBMIT_POLL_ATTEMPTS * SUBMIT_POLL_INTERVAL_MS) / 1000}s. ` +
      'It is uploaded and registered; submit it from the AGC console, or run this again.',
  );
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(USAGE);
    return;
  }
  if (options.submit && process.env.AGC_CONFIRM_SUBMIT !== 'YES') {
    throw new Refusal(
      '--submit puts this version in front of Huawei reviewers, so it needs a second act: ' +
        'set AGC_CONFIRM_SUBMIT=YES as well.',
    );
  }

  // Credentials come from the workflow's environment, or from a local `.env` when
  // a shell has not supplied them.
  loadDotEnv();

  const local = readPubspecVersion();
  const config = credentials();
  process.stdout.write(`Checking app ${config.appId} at ${config.base} for version ${local.name}+${local.code}\n`);

  config.token = await getToken(config);
  const appInfo = unwrap(
    'Reading the app',
    await request(config, `/api/publish/v3/app-info?appId=${encodeURIComponent(config.appId)}`),
  ).appInfo;
  const version = checkVersionAgainstShelf(local, appInfo ?? {});
  process.stdout.write(`  ${version.describe}\n`);

  if (options.dryRun) {
    process.stdout.write('Dry run: the credentials work and this version is publishable. Nothing was uploaded.\n');
    return;
  }

  // Resolved only once a dry run can no longer stop here: the version check needs
  // pubspec and AGC, not an artifact, so the first pass over a new account does
  // not have to sign anything first.
  const packPath = resolvePack(options.file);
  const size = checkPack(packPath);
  // One read: the digest and the upload body are the same bytes.
  const bytes = readFileSync(packPath);
  const digest = sha256(bytes);
  const fileName = basename(packPath);
  process.stdout.write(
    `Publishing ${fileName} (${(size / 1024 / 1024).toFixed(1)} MB, sha256 ${digest.slice(0, 16)}…)\n`,
  );

  const upload = unwrap(
    'Requesting an upload URL',
    await request(
      config,
      `/api/publish/v2/upload-url/for-obs?appId=${encodeURIComponent(config.appId)}` +
        `&fileName=${encodeURIComponent(fileName)}&sha256=${digest}` +
        `&contentLength=${size}&fileType=APP`,
    ),
  );
  // The response nests the presigned request, and its headers are signed — so
  // pass them through untouched. fetch sets Host and Content-Length itself, and
  // attempts to override them are dropped or rejected.
  const target = upload.urlInfo ?? upload;
  if (!target.url) {
    throw new Error(`Upload URL response has no urlInfo.url: ${JSON.stringify(upload).slice(0, 300)}`);
  }
  const headers = { ...(target.headers ?? {}) };
  for (const name of Object.keys(headers)) {
    if (['host', 'content-length'].includes(name.toLowerCase())) delete headers[name];
  }
  const put = await fetch(target.url, {
    method: (target.method ?? 'PUT').toUpperCase(),
    headers,
    body: bytes,
  });
  if (!put.ok) {
    throw new Error(`Uploading to OBS failed: HTTP ${put.status} ${(await put.text()).slice(0, 500)}`);
  }
  process.stdout.write(`  uploaded to storage as ${target.objectId}\n`);

  const registered = await registerPackage(config, { fileName, objectId: target.objectId });
  process.stdout.write(`  registered as software package ${registered.packageId}\n`);

  if (options.submit) {
    process.stdout.write(`  ${await submitForReview(config, options.remark)}\n`);
  } else {
    process.stdout.write('Uploaded and registered. Submit from the AGC console, or re-run with --submit.\n');
  }
}

try {
  await main();
} catch (err) {
  if (err instanceof Refusal) {
    process.stderr.write(`Refused: ${err.message}\n`);
    process.exit(2);
  }
  process.stderr.write(`Failed: ${err.message}\n`);
  process.exit(1);
}
