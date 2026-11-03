#!/usr/bin/env bash
# Build and publish the OHOS release build environment image (ci/Dockerfile.ohos-buildenv).
#
#   ci/publish-buildenv.sh              # build, then push to GHCR
#   ci/publish-buildenv.sh --no-push    # build only, for local verification
#
# The toolchain is a local dependency, not a build product: this script stages
# whatever the developer machine has ($CLD_DIR + $FLUTTER_DIR) into a context and
# bakes it. That is deliberate — the HarmonyOS SDK is behind a Huawei developer
# login, so it cannot be fetched on a runner, and the whole point of the image is
# to move that one download off CI and onto a machine that already has it.
#
# Staging hard-links rather than copies, so it costs no disk on the common case
# of the sources and the stage dir sharing a filesystem; it falls back to a real
# copy when they do not.
#
# The image tag is derived from the two toolchain versions, never hand-written:
# a tag that says what is inside it is the only way to tell two builds of this
# image apart, and `latest` would let CI drift from the toolchain it was tested
# against. After pushing, point `container.image` in
# .github/workflows/ohos-release.yml at the printed tag.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="$ROOT/ci/Dockerfile.ohos-buildenv"

# The toolchain lives in the developer's own directory layout (.envrc, CLAUDE.md);
# override to publish from somewhere else.
CLD_DIR="${CLD_DIR:-$HOME/dev/command-line-tools}"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/dev/flutter_flutter}"
IMAGE="${IMAGE:-ghcr.io/hezebang/techpie-ohos-buildenv}"

push=1
for arg in "$@"; do
  case "$arg" in
    --no-push) push=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

log() { printf '\033[32m[buildenv]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[buildenv]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Inputs -----------------------------------------------------------------
[[ -f "$CLD_DIR/version.txt" ]] || die "No version.txt in $CLD_DIR — is CLD_DIR the command-line-tools root?"
[[ -f "$FLUTTER_DIR/bin/cache/flutter.version.json" ]] || die "No bin/cache/flutter.version.json in $FLUTTER_DIR — has that SDK ever run?"

# "# Version: <x.y.z.n>" / "frameworkVersion": "<a.b.c>-ohos-<n>"
cli_version="$(sed -n 's/^#[[:space:]]*Version:[[:space:]]*//p' "$CLD_DIR/version.txt" | head -1)"
flutter_version="$(sed -n 's/.*"frameworkVersion":[[:space:]]*"\([^"]*\)".*/\1/p' \
                     "$FLUTTER_DIR/bin/cache/flutter.version.json" | head -1)"
[[ -n "$cli_version" && -n "$flutter_version" ]] || die "Could not read both toolchain versions"
# Docker tags allow only [A-Za-z0-9_.-], and the OHOS fork's version can carry a
# "+" (`3.41.9+ohos-1.0.2`). Mapping it to "_" keeps the tag readable and
# collision-free — two fork versions never differ only in "+" versus "_".
docker_tag() {
  printf '%s' "${1//+/_}"
}

tag="$(docker_tag "${cli_version}-${flutter_version}")"

# --- Staging context --------------------------------------------------------
# Next to the sources so the hard links are on one filesystem; $TMPDIR may be a
# tmpfs, where cp -al is guaranteed to fail with EXDEV.
stage="$(mktemp -d "${CLD_DIR%/*}/.techpie-buildenv-stage.XXXXXX")"
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

stage_dir() {
  local src="$1" name="$2"
  if cp -al "$src" "$stage/$name" 2>/dev/null; then
    log "staged $name (hard links)"
  else
    log "staged $name (copy — different filesystem)"
    # cp -al may have left a partial tree behind before failing.
    rm -rf "$stage/${name:?}"
    cp -a "$src" "$stage/$name"
  fi
}

log "command-line-tools $cli_version, flutter $flutter_version"
stage_dir "$CLD_DIR" command-line-tools
stage_dir "$FLUTTER_DIR" flutter_flutter

# --- Build ------------------------------------------------------------------
log "building $IMAGE:$tag"
# The source label is what links the GHCR package to this repository, which is
# also what lets a workflow pull it with its own GITHUB_TOKEN.
docker build \
  --file "$DOCKERFILE" \
  --tag "$IMAGE:$tag" \
  --label "org.opencontainers.image.source=https://github.com/HeZeBang/TechPie-flutter" \
  --label "org.opencontainers.image.description=OHOS release build environment (DevEco command-line tools $cli_version + OHOS Flutter $flutter_version)" \
  "$stage"

size="$(docker image inspect --format '{{.Size}}' "$IMAGE:$tag")"
# .Size is the sum of the image's layer descriptors — the compressed bytes a
# runner downloads. Extracting it costs more again: this toolchain is mostly many
# small SDK files, so it lands at several GB on disk.
log "built $(awk -v b="$size" 'BEGIN { printf "%.2f GB", b / 1000000000 }') to download"

# --- Push -------------------------------------------------------------------
if (( push )); then
  log "pushing $IMAGE:$tag (needs: docker login ghcr.io with a token carrying write:packages)"
  docker push "$IMAGE:$tag"
else
  log "not pushing (--no-push)"
fi

cat <<EOF

Publish complete. Point the OHOS release job at it:

  .github/workflows/ohos-release.yml ->  container.image: $IMAGE:$tag

Verify the image on this machine first — a release runner has no room for a
toolchain that does not work. These are the two commands the workflow runs, in
an empty container, against a bind-mounted checkout:

  docker run --rm -v "\$PWD:/workspace/techpie" -w /workspace/techpie $IMAGE:$tag \\
    bash -c 'flutter pub get && scripts/build-unsigned-hap.sh'

Local docker cache now holds the untrimmed staging payload as well;
'docker system prune' reclaims it once the image is pushed.
EOF
