#!/usr/bin/env node
// Generate the OHOS manifests hvigor needs from committed templates:
//
//   ohos/AppScope/app.json5        <- AppScope/app.template.json5 + pubspec.yaml version
//   ohos/build-profile.json5       <- build-profile.template.json5 + OHOS_* env vars
//
// With OHOS_UNSIGNED=1 the profile is written without any signing material, so
// hvigor packs `<module>-default-unsigned.hap` instead of a signed one. That is
// the build CI publishes (no signing secrets on the runner) and the one a
// contributor without signing material can run.
//
// hvigorfile.ts runs this on every hvigor invocation (DevEco builds included),
// and it can also be invoked directly:
//
//   node ohos/scripts/generate-build-profile.mjs
//
// Both outputs are gitignored: pubspec.yaml is the single source of truth for
// the app version, .envrc (or the CI environment) for the signing material.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const ohosDir = resolve(here, '..');
const repoRoot = resolve(ohosDir, '..');

const templatePath = resolve(ohosDir, 'build-profile.template.json5');
const outputPath = resolve(ohosDir, 'build-profile.json5');

const REQUIRED = [
  'OHOS_CERT_PATH',
  'OHOS_STORE_PASSWORD',
  'OHOS_KEY_ALIAS',
  'OHOS_KEY_PASSWORD',
  'OHOS_PROFILE_PATH',
  'OHOS_SIGN_ALG',
  'OHOS_STORE_FILE',
];

/// The app version, read from pubspec.yaml.
///
/// `flutter build hap` stamps the packed bundle from this file already, so a
/// DevEco-only build must be rendered from the same numbers or the two build
/// paths disagree. Returns the name and the numeric versionCode; the code
/// mirrors Flutter's own rule (the `+N` suffix, or 1 when absent).
function readAppVersion() {
  const pubspecPath = resolve(repoRoot, 'pubspec.yaml');
  const match = /^version:\s*(\S+)\s*$/m.exec(readFileSync(pubspecPath, 'utf8'));
  if (!match) {
    throw new Error(`No "version:" line in ${pubspecPath}`);
  }
  const raw = match[1];
  const separator = raw.indexOf('+');
  const name = separator < 0 ? raw : raw.slice(0, separator);
  const codeText = separator < 0 ? '' : raw.slice(separator + 1);
  const code = separator < 0 ? 1 : Number(codeText);
  if (!name || !Number.isInteger(code) || code <= 0) {
    throw new Error(`Unusable version "${raw}" in ${pubspecPath}`);
  }
  if (separator < 0) {
    console.warn(
      `[generate-ohos-manifests] pubspec version "${raw}" carries no "+N" ` +
        `build number; rendering versionCode 1. Add "+N" (e.g. "${raw}+1") ` +
        `so stores and iOS get a numeric build number.`,
    );
  }
  return { name, code };
}

/// AppScope/app.json5 — bundle identity plus the version pubspec declares.
function generateAppManifest() {
  const templatePath = resolve(ohosDir, 'AppScope', 'app.template.json5');
  const outputPath = resolve(ohosDir, 'AppScope', 'app.json5');
  if (!existsSync(templatePath)) {
    throw new Error(`Template not found: ${templatePath}`);
  }

  const { name, code } = readAppVersion();
  let content = readFileSync(templatePath, 'utf8');
  content = content
    .replaceAll('__APP_VERSION_NAME__', name)
    .replaceAll('__APP_VERSION_CODE__', String(code));
  if (content.includes('__APP_VERSION_')) {
    throw new Error(`Unsubstituted version placeholder in ${templatePath}`);
  }
  writeFileSync(outputPath, content);
}

function generateBuildProfile() {
  if (!existsSync(templatePath)) {
    throw new Error(`Template not found: ${templatePath}`);
  }

  let content = readFileSync(templatePath, 'utf8');

  if (process.env.OHOS_UNSIGNED === '1') {
    // Drop the signing block and the product's reference to it: hvigor then has
    // nothing to sign with and writes `entry-default-unsigned.hap`.
    content = content
      .replace(/"signingConfigs":\s*\[[\s\S]*?\r?\n    \],\r?\n/, '')
      .replace(/"signingConfig": "default",\r?\n/, '');
    if (content.includes('signingConfig')) {
      throw new Error('Could not strip the signing block from the template');
    }
    writeFileSync(outputPath, content);
    return;
  }

  const missing = REQUIRED.filter((k) => !process.env[k]);
  if (missing.length === REQUIRED.length) {
    // No signing env at all — likely a contributor without signing material.
    // Leave any existing build-profile.json5 alone so DevEco's automatic signing
    // (or a previously generated file) can still be used.
    if (existsSync(outputPath)) return;
    throw new Error(
      `No OHOS_* signing env vars set and ${outputPath} does not exist. ` +
        `Source .envrc (direnv) or copy .envrc.example, fill in the values, then retry.`,
    );
  }
  if (missing.length > 0) {
    throw new Error(
      `Missing required OHOS signing env vars: ${missing.join(', ')}. ` +
        `See .envrc.example.`,
    );
  }

  for (const key of REQUIRED) {
    content = content.replaceAll(`__${key}__`, process.env[key]);
  }
  writeFileSync(outputPath, content);
}

try {
  // The app manifest never depends on the signing environment, so it is
  // rendered first and survives a contributor without signing material.
  generateAppManifest();
  generateBuildProfile();
} catch (err) {
  console.error(`[generate-ohos-manifests] ${err.message}`);
  process.exit(1);
}
