#!/usr/bin/env node
// Compute the release plan from the single version source: pubspec.yaml
// (`version: X.Y.Z[-rc.N]+B`).
//
// Called by .github/workflows/release.yml, and runnable locally:
//
//   node scripts/release-plan.mjs --ref release/1.0.0
//   node scripts/release-plan.mjs --ref release/1.0.0 --base HEAD~1
//   node scripts/release-plan.mjs --next-version 1.0.0        # prints 1.0.0+6
//
// Two ways in, and they differ in who decides:
//
//   dispatch            → always plans. Asking for a release is the decision, and
//                         candidates are released this way.
//   push to release/**  → `--base <the commit the push started from>` decides: only
//                         a push that *moves* the version line publishes. Cutting
//                         the branch does not move it, merging the release PR does.
//
// A base that is missing, all zeros or unresolvable answers "did not move", which
// is the safe way round: a release that did not happen can be asked for again, an
// unintended one cannot be taken back.
//
// The plan is written as `key=value` lines to stdout (GitHub Actions reads them
// via $GITHUB_OUTPUT). The ref picks the channel:
//
//   master         → pre-release: the version line on master is a candidate.
//   release/X.Y.Z  → stable: the branch declares the version it freezes, and
//                    pubspec must agree with it. Anything else is refused, so a
//                    mistyped branch cannot publish from an arbitrary commit.
//
// Version stamps handed to the platform builds never carry the pre-release
// part: iOS rejects a CFBundleShortVersionString like `1.0.0-rc.4`, and keeping
// Android identical means one artifact version per release everywhere. The tag
// keeps it instead, so the tag alone says which candidate shipped:
//
//   vX.Y.Z-rc.N+B  the release: Android APKs, then the OHOS hap, on one GitHub
//   vX.Y.Z+B       release — the same shape, for a stable one
//   ios-vX.Y.Z+B   iOS, whose private signing workflow validates this exact
//                  shape, so it keeps its platform prefix
//
// A tag is therefore `v` + the release name + the build number, and the
// presence of the `-rc.N` part is what makes the Android workflow mark the
// GitHub release as a pre-release.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { notesFor, readChangelog } from './changelog.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..');

/// Flags that stand alone: `--check` is not `--check <value>`.
const BOOLEAN_FLAGS = new Set(['check', 'strict']);

function parseArgs(argv) {
  const opts = {};
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (BOOLEAN_FLAGS.has(key) && (argv[i + 1] == null || argv[i + 1].startsWith('--'))) {
      opts[key] = 'true';
      continue;
    }
    const value = argv[++i];
    if (value == null) throw new Error(`Missing value for ${arg}`);
    opts[key] = value;
  }
  return opts;
}

/// A git command's stdout, or null when it fails: a rev that is not in this
/// clone (a branch's first push, a rewritten history, a shallow checkout).
function gitTry(args) {
  try {
    return execFileSync('git', args, { cwd: repoRoot, encoding: 'utf8' });
  } catch {
    return null;
  }
}

/// The pubspec of the commit being released.
function readPubspec() {
  return readFileSync(resolve(repoRoot, 'pubspec.yaml'), 'utf8');
}

/// The raw `version:` token of a pubspec, or null when the field is absent.
function versionToken(text) {
  const match = /^version:\s*(\S+)\s*$/m.exec(text);
  return match ? match[1] : null;
}

/// Play rejects a versionCode above 2,100,000,000, so a build number that high
/// is refused here instead of by the store.
const MAX_BUILD_NUMBER = 2100000000;

/// `version: X.Y.Z[-rc.N]+B` → { raw, base, pre, code }.
function readVersion() {
  const where = resolve(repoRoot, 'pubspec.yaml');
  const pubspec = readPubspec();
  const raw = versionToken(pubspec);
  if (raw == null) {
    throw new Error(
      /^version:/m.test(pubspec)
        ? `Unparsable version line in ${where}: it must be exactly ` +
          `\`version: X.Y.Z[-rc.N]+B\`, with nothing after the number (a trailing ` +
          `comment breaks every consumer of that line).`
        : `No "version:" line in ${where}`,
    );
  }
  const plus = raw.indexOf('+');
  if (plus < 0) {
    throw new Error(
      `pubspec version "${raw}" has no "+B" build number; the build number is ` +
        `what stores require to increase, so it must live in pubspec.yaml too.`,
    );
  }
  const name = raw.slice(0, plus);
  const codeText = raw.slice(plus + 1);
  const code = Number(codeText);
  // Leading zeros would make the number read one way here and another way in the
  // platform workflows, which compare the tag's digits against pubspec's text.
  if (!/^[1-9][0-9]*$/.test(codeText) || code > MAX_BUILD_NUMBER) {
    throw new Error(
      `Unusable build number "${codeText}" in version "${raw}": it must be a ` +
        `plain integer above zero without leading zeros, at most ` +
        `${MAX_BUILD_NUMBER} (Play's versionCode ceiling).`,
    );
  }
  const dash = name.indexOf('-');
  const base = dash < 0 ? name : name.slice(0, dash);
  const pre = dash < 0 ? '' : name.slice(dash + 1);
  if (!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(base)) {
    throw new Error(`Version "${raw}" is not X.Y.Z[-rc.N]+B shaped`);
  }
  if (/^0[0-9]|\.0[0-9]/.test(base)) {
    throw new Error(
      `Version "${raw}" has a leading zero in X.Y.Z, which SemVer forbids; ` +
        `pub and the platforms would read it as a different version.`,
    );
  }
  return { raw, base, pre, code };
}

function gitRevParse(rev) {
  return execFileSync('git', ['rev-parse', rev], { cwd: repoRoot, encoding: 'utf8' }).trim();
}

/// Tags that point at the commit being released. Re-running a workflow must be
/// a no-op, so these are excluded from every "what was released before" check.
function tagsAtHead(tags) {
  const head = gitRevParse('HEAD');
  const atHead = new Set();
  for (const tag of tags) {
    // An annotated tag's own sha is not the commit it names: peel it first, or
    // re-running a release looks like a build number that was already spent.
    const target = gitTry(['rev-parse', '--verify', '--quiet', `${tag}^{commit}`]);
    if (target != null && target.trim() === head) atHead.add(tag);
  }
  return atHead;
}

function gitTags() {
  return execFileSync('git', ['tag', '--list'], { cwd: repoRoot, encoding: 'utf8' })
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
}

/// Highest build number already shipped on any platform: the Play Store
/// requires the versionCode to increase across the whole application, so every
/// release tag counts. Releases before the rename were tagged `android-v…`.
function highestAndroidCode(tags) {
  let highest = 0;
  for (const tag of tags) {
    const match = /^(?:android-)?v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?\+([0-9]+)$/.exec(tag);
    if (match) highest = Math.max(highest, Number(match[1]));
  }
  return highest;
}

/// Include iOS-only releases from every version train in the shared counter.
/// A manual iOS dispatch can consume a build without creating a v… release tag.
function highestIosCode(tags) {
  const pattern = /^ios-v[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)$/;
  let highest = 0;
  for (const tag of tags) {
    const match = pattern.exec(tag);
    if (match) highest = Math.max(highest, Number(match[1]));
  }
  return highest;
}

/// Highest `-rc.N` already used for [base]. The ordinal counts the candidates of
/// a version line, so it comes from the tags rather than being typed — history
/// before the tag rename carried an `android-` prefix.
function highestRcOrdinal(tags, base) {
  const pattern = new RegExp(
    `^(?:android-)?v${base.replaceAll('.', '\\.')}-rc\\.([0-9]+)\\+[0-9]+$`,
  );
  let highest = 0;
  for (const tag of tags) {
    const match = pattern.exec(tag);
    if (match) highest = Math.max(highest, Number(match[1]));
  }
  return highest;
}

/// Highest product version already shipped as a *stable* release, so a release
/// branch cannot regress the line (e.g. release/1.0.0 after 1.1.0).
function highestStableBase(tags) {
  let highest = null;
  for (const tag of tags) {
    const match = /^(?:android-)?v([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+$/.exec(tag);
    if (!match) continue;
    if (highest == null || compareVersions(match[1], highest) > 0) highest = match[1];
  }
  return highest;
}

/// -1 / 0 / 1 for X.Y.Z names.
function compareVersions(left, right) {
  const a = left.split('.').map(Number);
  const b = right.split('.').map(Number);
  for (let i = 0; i < 3; i += 1) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return 0;
}

/// The next patch of an X.Y.Z line, for the "what do I write on master" hint.
function bumpPatch(base) {
  const [major, minor, patch] = base.split('.').map(Number);
  return `${major}.${minor}.${patch + 1}`;
}

function plan(opts) {
  const stableMatch = /^release\/([0-9]+\.[0-9]+\.[0-9]+)$/.exec(opts.ref);
  if (opts.ref !== 'master' && stableMatch == null) {
    throw new Error(
      `${opts.ref} is not a release ref: dispatch a candidate on master, or a ` +
        `stable release on release/X.Y.Z.`,
    );
  }

  const version = readVersion();
  const allTags = gitTags();
  const atHead = tagsAtHead(allTags);
  const tags = allTags.filter((tag) => !atHead.has(tag));

  const channel = stableMatch ? 'stable' : 'prerelease';

  // A candidate is the next line, not a frozen one: dispatching on master with a
  // version that has already shipped stable would name it `1.0.3-rc.10` after
  // `1.0.3+17`. The build number check below cannot see this, because a stale
  // master carries a spent number as well.
  if (channel === 'prerelease') {
    const shipped = highestStableBase(allTags);
    const order = shipped == null ? 1 : compareVersions(version.base, shipped);
    if (order <= 0) {
      throw new Error(
        order === 0
          ? `pubspec.yaml says ${version.base}, which already shipped as a stable ` +
            `release; a candidate is a version line that has not been frozen yet. ` +
            `Bump the version line first (node scripts/release-plan.mjs --check ` +
            `prints the value to write).`
          : `pubspec.yaml says ${version.base}, but ${shipped} already shipped as a ` +
            `stable release. A candidate is the next line: bump the version in ` +
            `pubspec.yaml first (node scripts/release-plan.mjs --check prints the ` +
            `value to write). A maintenance release of ${version.base} is ` +
            `release/${version.base} instead.`,
      );
    }
  }

  if (channel === 'stable') {
    const frozen = stableMatch[1];
    if (frozen !== version.base) {
      throw new Error(
        `Branch ${opts.ref} freezes ${frozen}, but pubspec.yaml says ${version.raw}. ` +
          `A release branch must carry exactly the version it releases.`,
      );
    }
    if (version.pre !== '') {
      throw new Error(
        `${opts.ref} is a stable release branch, but pubspec.yaml says ` +
          `${version.raw}; drop the "-${version.pre}" part (or drop the branch).`,
      );
    }
    // A patch branch for an older line is legitimate, so this is a warning, not
    // a refusal: the maintainer sees it in the run summary and decides.
    const shipped = highestStableBase(allTags.filter((tag) => !atHead.has(tag)));
    if (shipped != null && compareVersions(version.base, shipped) < 0) {
      console.error(
        `[release-plan] warning: ${opts.ref} releases ${version.base}, but ` +
          `${shipped} already shipped as a stable release. Continuing — say so ` +
          `explicitly if this is not a maintenance release.`,
      );
    }
  }

  // The rc ordinal counts the candidates of this version line, so it is derived
  // rather than typed: with one `1.0.0` candidate already shipped, `1.0.0+4` is
  // the second one, `1.0.0-rc.2`. A declared suffix is accepted only when it
  // says exactly that, which keeps pubspec and the release name from disagreeing.
  const rcOrdinal = highestRcOrdinal(tags, version.base) + 1;
  const releaseName =
    channel === 'stable' ? version.base : `${version.base}-rc.${rcOrdinal}`;
  if (version.pre !== '' && version.pre !== `rc.${rcOrdinal}`) {
    throw new Error(
      `pubspec version ${version.raw} declares "-${version.pre}", but this is ` +
        `candidate ${rcOrdinal} of ${version.base}: the release name is ` +
        `${releaseName}. Drop the suffix and let the plan name it, or write ` +
        `exactly "-rc.${rcOrdinal}".`,
    );
  }

  // A release without notes is a release nobody can read: the tag job copies this
  // section into the tag annotation, and the GitHub release page is built from it.
  notesFor(readChangelog(), version.base);

  // The ceiling is read from the tags that are *not* at this commit, so re-running
  // a release that already tagged this commit falls through to the skip below.
  // The advice, though, comes from every tag: suggesting a number another
  // platform already spent would only move the same refusal one step.
  const androidHighest = highestAndroidCode(tags);
  const iosHighest = highestIosCode(tags);
  const highestEver = Math.max(highestAndroidCode(allTags), highestIosCode(allTags));
  if (version.code <= androidHighest) {
    throw new Error(
      `pubspec build number ${version.code} is not above the released build ` +
      `${androidHighest} (tag …+${androidHighest}); Play requires an increase, ` +
      `so bump to "+${highestEver + 1}" or higher.`,
    );
  }
  if (version.code <= iosHighest) {
    throw new Error(
      `pubspec build number ${version.code} is not above the released iOS build ` +
        `${iosHighest}; the repository shares one increasing build number ` +
        `across all versions and platforms, so bump to "+${highestEver + 1}" or higher.`,
    );
  }

  const tag = `v${releaseName}+${version.code}`;
  const tagIos = `ios-v${version.base}+${version.code}`;
  const existing = [tag, tagIos].filter((candidate) => allTags.includes(candidate));
  if (existing.length > 0) {
    // Same commit → this release already went out, so there is nothing to do.
    // A tag pointing somewhere else means the build number was reused.
    if (existing.some((tag) => !atHead.has(tag))) {
      throw new Error(
        `Tag(s) ${existing.join(', ')} already exist for a different commit; ` +
          `bump the build number in pubspec.yaml to publish another release.`,
      );
    }
    return {
      skip: true,
      reason: `release ${releaseName} (build ${version.code}) is already tagged at this commit`,
    };
  }

  return {
    skip: false,
    channel,
    version: version.raw,
    base: version.base,
    code: String(version.code),
    release_name: releaseName,
    tag,
    tag_ios: tagIos,
    prerelease: channel === 'prerelease' ? 'true' : 'false',
  };
}

/// The version line to write for [base]: one build above everything ever shipped
/// on any platform. `prepare-release.yml` proposes this, so the arithmetic stays here with
/// the rest of the rules instead of being re-implemented in bash.
function nextVersionLine(base) {
  if (!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(base)) {
    throw new Error(`--next-version wants X.Y.Z, got "${base}"`);
  }
  const tags = gitTags();
  return `${base}+${Math.max(highestAndroidCode(tags), highestIosCode(tags)) + 1}`;
}

/// Where this checkout stands against everything already released: the product
/// version and the build number, side by side with the newest tags.
///
/// Nothing is refused here. The point is that a stale master is a legal state
/// (no new line has been opened since the last stable release) that still makes
/// a candidate dispatch fail, so it has to be visible *before* someone asks for
/// one — and the value to write has to be printed, not computed by hand.
///
/// `--strict` turns "a release from this ref would be refused" into an exit 1;
/// the default only reports it.
function statusReport(opts) {
  const version = readVersion();
  const allTags = gitTags();
  const shippedBase = highestStableBase(allTags);
  const shippedCode = Math.max(highestAndroidCode(allTags), highestIosCode(allTags));
  const ref = opts.ref;

  const lineVsShipped =
    shippedBase == null ? 'new' : compareVersions(version.base, shippedBase);
  const codeVsShipped = version.code - shippedCode;
  const newest = [
    ...[...allTags].map((tag) => /^(?:android-)?v([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$/.exec(tag)),
  ]
    .filter(Boolean)
    .sort((a, b) => Number(b[2]) - Number(a[2]))[0];

  // The value to write on this ref: on a release branch it is the same line with
  // the next build number (a store resubmission); on master the line has to move
  // forward, so it is the next patch of what shipped unless master is already
  // ahead of it.
  const stableRef = /^release\/([0-9]+\.[0-9]+\.[0-9]+)$/.exec(ref);
  const suggestedBase = stableRef != null
    ? stableRef[1]
    : shippedBase != null && compareVersions(version.base, shippedBase) <= 0
      ? bumpPatch(shippedBase)
      : version.base;

  const report = {
    ref,
    version: version.raw,
    newest_release: newest == null ? 'none' : `${newest[1]}+${newest[2]}`,
    version_vs_newest:
      lineVsShipped === 'new' ? 'no-stable-yet' : ['older', 'equal', 'newer'][lineVsShipped + 1],
    build_vs_newest: String(codeVsShipped),
    suggested: `${suggestedBase}+${shippedCode + 1}`,
    // `spent` is the rule the build-number ledger is kept for: this exact number
    // was already tagged, so a build here would reuse it.
    build: codeVsShipped <= 0 ? 'spent' : 'unused',
    line: lineVsShipped === -1 ? 'stale' : 'current',
  };

  // Same rules the plan and the version guard apply, so this report cannot say
  // "releasable" about a release that would be refused: a free build number, and
  // a line that either moves past the newest stable (from master) or is this very
  // branch's own line (a maintenance rebuild).
  const ownBranch = stableRef != null && stableRef[1] === version.base;
  const lineOk =
    shippedBase == null || ownBranch || (stableRef == null && lineVsShipped > 0);
  const releasable = codeVsShipped > 0 && lineOk;
  report.releasable = releasable ? 'yes' : 'no';

  for (const [key, value] of Object.entries(report)) console.log(`${key}=${value}`);

  const reasons = [];
  if (codeVsShipped <= 0) {
    reasons.push(`build ${version.code} is already spent (newest ${report.newest_release})`);
  }
  if (!lineOk) {
    reasons.push(
      lineVsShipped > 0
        ? `${ref} freezes ${stableRef?.[1]}, but pubspec.yaml says ${version.base}`
        : stableRef != null
          ? `${ref} is not the branch of ${version.base}`
          : lineVsShipped === 0
            ? `${version.base} already shipped as a stable release`
            : `${version.base} is older than the newest stable release ${shippedBase}`,
    );
  }
  const summary = releasable
    ? `[release-plan] ${ref}: ${version.raw} is releasable ` +
      `(newest release ${report.newest_release})`
    : `[release-plan] ${ref}: ${version.raw} would be refused — ` +
      `${reasons.join('; ')}. Write ${report.suggested} to release from here.`;
  console.error(summary);

  if (opts.strict != null && !releasable) process.exit(1);
  return null;
}

/// The current branch name, or null on a detached checkout.
function currentBranch() {
  const name = gitTry(['rev-parse', '--abbrev-ref', 'HEAD'])?.trim();
  // A detached checkout answers "HEAD"; that is not a ref a release can be
  // planned from, so the caller's fallback decides instead.
  return name == null || name === 'HEAD' || name === '' ? null : name;
}

/// The hard guard in front of a release: may `version` still be released from
/// `ref`? The build number is checked by `plan()` when the tags are made; this
/// is the product-version half, which nothing else covers.
///
/// Two refusals, both aimed at the same mistake — publishing a line that has
/// already been superseded:
///
///   - an older line from `master` (a new release must move the line forward;
///     maintenance of an old line happens on that line's own branch);
///   - re-proposing the line that already shipped stable from `master` (a store
///     resubmission is `release/X.Y.Z` + a higher `+B`, per the release docs).
function requireVersion(opts) {
  const wanted = opts.requireVersion;
  if (!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(wanted)) {
    throw new Error(`--require-version wants X.Y.Z, got "${wanted}"`);
  }
  const ref = opts.ref;
  const shipped = highestStableBase(gitTags());
  if (shipped == null) {
    console.error(`[release-plan] ${wanted} from ${ref}: no stable release yet`);
    return;
  }
  const order = compareVersions(wanted, shipped);
  if (order < 0) {
    if (ref === `release/${wanted}`) {
      console.error(
        `[release-plan] ${wanted} from ${ref}: maintenance release of an older ` +
          `line, allowed here (newest stable is ${shipped})`,
      );
      return;
    }
    throw new Error(
      `${wanted} is older than the newest stable release ${shipped}. A new ` +
        `release from ${ref} has to move the line forward — pick a higher ` +
        `X.Y.Z — and a maintenance patch is cut on release/${wanted}.`,
    );
  }
  if (order === 0 && ref === 'master') {
    throw new Error(
      `${wanted} already shipped as a stable release. Re-publishing it is ` +
        `release/${wanted} with a higher "+B", not a new line from master.`,
    );
  }
  console.error(
    `[release-plan] ${wanted} from ${ref}: ${order === 0 ? 'rebuild of' : 'newer than'} ` +
      `the newest stable release ${shipped}`,
  );
}

/// Did this push move the `version:` line? That line is the release switch, so a
/// push that leaves it alone plans nothing — including the push that cuts a new
/// release branch. `--base` absent means "a dispatch is asking for a release":
/// then this script is not the gate.
function versionChanged(base) {
  if (base == null) return true;
  if (!base || !gitTry(['rev-parse', '--verify', '--quiet', `${base}^{commit}`])) return false;
  const before = gitTry(['show', `${base}:pubspec.yaml`]);
  if (before == null) return false;
  return versionToken(before) !== versionToken(readPubspec());
}

try {
  const opts = parseArgs(process.argv);
  // The ref decides the channel, so an unspecified one means "wherever this
  // checkout is": a bare `--check` on release/1.0.3 must report that branch, not
  // master. The workflows always pass it explicitly (github.ref_name).
  const ref = opts.ref ?? currentBranch() ?? 'master';
  if (opts.nextVersion != null) {
    console.log(nextVersionLine(opts.nextVersion));
  } else if (opts.check != null || opts.strict != null) {
    statusReport({ ...opts, ref });
  } else if (opts.requireVersion != null) {
    requireVersion({ ...opts, ref });
  } else {
    const result = versionChanged(opts.base)
      ? plan({ ...opts, ref })
      : {
          skip: true,
          reason: 'the pubspec version line did not move in this push',
        };
    for (const [key, value] of Object.entries(result)) {
      console.log(`${key}=${value}`);
    }
    // Summary goes to stderr: stdout is parsed as key=value by the workflow.
    console.error(
      result.skip
        ? `[release-plan] no release: ${result.reason}`
        : `[release-plan] ${result.channel} ${result.release_name} (build ${result.code})` +
            ` → ${result.tag}, ${result.tag_ios}`,
    );
  }
} catch (err) {
  console.error(`[release-plan] ${err.message}`);
  process.exit(1);
}
