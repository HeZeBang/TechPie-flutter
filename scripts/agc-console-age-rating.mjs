#!/usr/bin/env node
// Copy the app's content rating onto one version, through the console's own
// edge API.
//
//   AGC_CONSOLE_COOKIE='authdata=…; csrfToken=…; …' AGC_TEAM_ID=30086000692335558 \
//     node scripts/agc-console-age-rating.mjs --version-id 2076670289856461888
//   … --dry-run          # read only: show what would be applied
//
// Why this exists: AppGallery keeps the age rating **per version serial**
// (`srvSerialNo` = the versionId), not per app. Publishing API can rate the app
// (`POST /api/publish/v2/app-age-rating`), the console then *copies* that
// questionnaire onto each version through this edge service — and a version
// without that record is refused at submit time with
// `[AppGalleryConnectAppMetaInfoService]contentRating in amis is invalid`.
// Sending `extInfo.contentRating` on the version PUT is accepted and ignored
// (measured on v1.0.4-rc.1+19), so the copy is the only way in.
//
// Auth is the developer console's session cookie, not the API client: these are
// console endpoints (`agc-drcn.developer.huawei.com/agc/edge/…`) and they answer
// 401 to anything else. The cookie lasts about an hour, which is why this is a
// step you run around a release rather than something a tagged CI run can hold.
//
// Credentials:
//   AGC_CONSOLE_COOKIE   the whole Cookie header copied from a console request
//   AGC_TEAM_ID          the agcTeamId header the console sends
//   AGC_CSRF             optional; defaults to the csrfToken inside the cookie
//   AGC_APP_ID           from .env, or the environment

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const HOST = process.env.AGC_CONSOLE_HOST ?? 'https://agc-drcn.developer.huawei.com';
const RATING = '/agc/edge/ars/app-agerating-service/v2/appAgeRating';

const args = process.argv.slice(2);
const opt = (name, fallback = '') => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};
const flag = (name) => args.includes(`--${name}`);

function loadEnv() {
  try {
    for (const line of readFileSync(resolve(ROOT, '.env'), 'utf8').split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
      const index = trimmed.indexOf('=');
      const key = trimmed.slice(0, index).trim();
      if (!process.env[key]) {
        process.env[key] = trimmed.slice(index + 1).trim().replace(/^["']|["']$/g, '');
      }
    }
  } catch {
    /* no .env is fine */
  }
}

loadEnv();

try {
  const versionId = opt('version-id');
  if (!/^[0-9]+$/.test(versionId)) {
    throw new Error('--version-id <versionId> is required (the numeric version, not the package id)');
  }
  const appId = process.env.AGC_APP_ID ?? '';
  if (!appId) throw new Error('AGC_APP_ID is missing (environment or .env)');
  const cookie = process.env.AGC_CONSOLE_COOKIE ?? '';
  if (!cookie) {
    throw new Error(
      'AGC_CONSOLE_COOKIE is missing. Copy the whole Cookie header from a request to\n' +
        'agc-drcn.developer.huawei.com in the developer console (DevTools → Network).\n' +
        'It is a session credential for your account; it expires in about an hour.',
    );
  }
  const teamId = process.env.AGC_TEAM_ID ?? '';
  if (!teamId) throw new Error('AGC_TEAM_ID is missing (the agcTeamId the console sends)');
  const csrf =
    process.env.AGC_CSRF ??
    (/csrfToken=([^;]+)/.exec(cookie)?.[1] ?? '').trim();
  if (!csrf) throw new Error('No csrf: set AGC_CSRF, or include csrfToken in the cookie');

  const headers = {
    'Content-Type': 'application/json',
    appId,
    agcTeamId: teamId,
    'X-HD-CSRF': csrf,
    Origin: 'https://developer.huawei.com',
    Referer: 'https://developer.huawei.com/',
    Cookie: cookie,
  };

  async function call(path, { method = 'GET', body } = {}) {
    const res = await fetch(HOST + path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    if (res.status === 401 || res.status === 403) {
      throw new Error(
        `${method} ${path} → HTTP ${res.status}: the console session is not valid. ` +
          'The cookie lasts about an hour — copy a fresh one.',
      );
    }
    let payload;
    try {
      payload = text ? JSON.parse(text) : {};
    } catch {
      throw new Error(`${method} ${path} → HTTP ${res.status}, not JSON: ${text.slice(0, 200)}`);
    }
    if (!res.ok || (payload.ret && payload.ret.code)) {
      throw new Error(`${method} ${path} → HTTP ${res.status}: ${text.slice(0, 300)}`);
    }
    return payload;
  }

  /// The questionnaire the app already answered. Any confirmed record carries it;
  /// the rating itself is recomputed from the same answers, so copying the ids is
  /// what the console does.
  async function existingQuestionnaire() {
    const list = await call(`${RATING}?appId=${appId}`);
    const confirmed = (list.appAgeRatingList ?? []).filter((row) => row.status === 2);
    if (confirmed.length === 0) {
      throw new Error(
        'the app has no confirmed content rating yet: answer the questionnaire once ' +
          '(console, or POST /api/publish/v2/app-age-rating), then re-run this',
      );
    }
    const source = confirmed[0];
    return {
      questionnaireId: source.questionnaireId,
      feedbackId: source.feedbackId,
      ratingResult: source.ratingResult,
      otherRatingList: source.otherRatingList ?? [],
      from: source.srvSerialNo,
    };
  }

  async function currentRating() {
    const one = await call(`${RATING}?appId=${appId}&srvSerialNo=${versionId}`);
    return one.appAgeRating ?? (one.appAgeRatingList ?? [])[0] ?? null;
  }

  const questionnaire = await existingQuestionnaire();
  console.log(
    `app rating: result ${questionnaire.ratingResult} ` +
      `(${(questionnaire.otherRatingList ?? []).map((r) => `${r.gradeTypeName} ${r.ratingResult}`).join(', ') || 'no other standards'})`,
  );
  console.log(`questionnaire ${questionnaire.questionnaireId}, feedback ${questionnaire.feedbackId} (from version ${questionnaire.from})`);

  const before = await currentRating();
  console.log(`version ${versionId} rating before: ${before ? `status ${before.status}` : 'none'}`);

  if (flag('dry-run')) {
    console.log('\ndry run: would save, submit and confirm this questionnaire for this version');
    process.exit(0);
  }

  const shared = {
    srvSerialNo: versionId,
    feedbackId: questionnaire.feedbackId,
    questionnaireId: questionnaire.questionnaireId,
  };

  const saved = await call(RATING, { method: 'POST', body: { action: 'save', ...shared } });
  console.log(`saved: status ${saved.appAgeRating?.status}`);
  const submitted = await call(RATING, { method: 'POST', body: { action: 'submit', ...shared } });
  console.log(`submitted: status ${submitted.appAgeRating?.status}, result ${submitted.appAgeRating?.ratingResult}`);
  await call(`${RATING}/confirm`, {
    method: 'POST',
    body: {
      feedbackId: questionnaire.feedbackId,
      confirmResult: 1,
      questionnaireId: questionnaire.questionnaireId,
      ext: { isForChildren: 0 },
    },
  });
  console.log('confirmed');

  const after = await currentRating();
  console.log(`version ${versionId} rating after: ${after ? `status ${after.status}` : 'none'}`);
} catch (error) {
  console.error(`[agc-age-rating] ${error.message}`);
  process.exit(1);
}
