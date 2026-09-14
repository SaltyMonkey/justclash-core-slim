#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-upstream.sh [options]

Options:
  --channel <channel>         Release channel: alpha or stable
  --upstream-url <url>        Upstream Git repository URL
  --upstream-ref <ref>       Upstream branch or tag to clone
  --expected-sha <sha>       Verify the cloned commit SHA
  --target-repository <repo> Destination repository in owner/name form
  -h, --help                  Show this help
EOF
}

fail() {
  echo "Error: $1" >&2
  echo >&2
  usage >&2
  exit 2
}

CHANNEL=""
UPSTREAM_URL=""
UPSTREAM_REF=""
EXPECTED_SHA=""
TARGET_REPOSITORY=""

while (( $# > 0 )); do
  case "$1" in
    --channel)
      (( $# >= 2 )) || fail "--channel requires a value"
      [[ -z "$CHANNEL" ]] || fail "--channel was specified more than once"
      CHANNEL="$2"
      shift 2
      ;;
    --channel=*)
      [[ -z "$CHANNEL" ]] || fail "--channel was specified more than once"
      CHANNEL="${1#*=}"
      shift
      ;;
    --upstream-url)
      (( $# >= 2 )) || fail "--upstream-url requires a value"
      [[ -z "$UPSTREAM_URL" ]] || fail "--upstream-url was specified more than once"
      UPSTREAM_URL="$2"
      shift 2
      ;;
    --upstream-url=*)
      [[ -z "$UPSTREAM_URL" ]] || fail "--upstream-url was specified more than once"
      UPSTREAM_URL="${1#*=}"
      shift
      ;;
    --upstream-ref)
      (( $# >= 2 )) || fail "--upstream-ref requires a value"
      [[ -z "$UPSTREAM_REF" ]] || fail "--upstream-ref was specified more than once"
      UPSTREAM_REF="$2"
      shift 2
      ;;
    --upstream-ref=*)
      [[ -z "$UPSTREAM_REF" ]] || fail "--upstream-ref was specified more than once"
      UPSTREAM_REF="${1#*=}"
      shift
      ;;
    --expected-sha)
      (( $# >= 2 )) || fail "--expected-sha requires a value"
      [[ -z "$EXPECTED_SHA" ]] || fail "--expected-sha was specified more than once"
      EXPECTED_SHA="$2"
      shift 2
      ;;
    --expected-sha=*)
      [[ -z "$EXPECTED_SHA" ]] || fail "--expected-sha was specified more than once"
      EXPECTED_SHA="${1#*=}"
      shift
      ;;
    --target-repository)
      (( $# >= 2 )) || fail "--target-repository requires a value"
      [[ -z "$TARGET_REPOSITORY" ]] || fail "--target-repository was specified more than once"
      TARGET_REPOSITORY="$2"
      shift 2
      ;;
    --target-repository=*)
      [[ -z "$TARGET_REPOSITORY" ]] || fail "--target-repository was specified more than once"
      TARGET_REPOSITORY="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$CHANNEL" ]] || fail "--channel is required"
[[ -n "$UPSTREAM_URL" ]] || fail "--upstream-url is required"
[[ -n "$UPSTREAM_REF" ]] || fail "--upstream-ref is required"
[[ -n "$TARGET_REPOSITORY" ]] || fail "--target-repository is required"

if [[ "$CHANNEL" != "alpha" && "$CHANNEL" != "stable" ]]; then
  fail "unsupported channel: $CHANNEL"
fi

[[ -n "${GH_TOKEN:-}" ]] || fail "GH_TOKEN environment variable is required"

BUILDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
SOURCE_DIR="$WORK_DIR/source"
DIST_DIR="$WORK_DIR/dist"
RELEASE_DIR="$WORK_DIR/release"

if [[ "$CHANNEL" == "alpha" ]]; then
  BUILD_BRANCH="build/alpha"
  RELEASE_TAG="Prerelease-Alpha"
else
  SAFE_REF="${UPSTREAM_REF//\//-}"
  BUILD_BRANCH="build/stable-${SAFE_REF}"
  VERSION="$UPSTREAM_REF"
  RELEASE_TAG="$UPSTREAM_REF"
fi

cleanup() {
  # The full upstream codebase exists in our repository only while the
  # upstream build workflow is running. Remove the temporary branch afterwards.
  git -C "$SOURCE_DIR" push downstream --delete "$BUILD_BRANCH" >/dev/null 2>&1 || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

git clone --depth=1 --branch "$UPSTREAM_REF" \
  "$UPSTREAM_URL" \
  "$SOURCE_DIR"

UPSTREAM_SHA="$(git -C "$SOURCE_DIR" rev-parse HEAD)"

if [[ -n "$EXPECTED_SHA" && "$UPSTREAM_SHA" != "$EXPECTED_SHA" ]]; then
  echo "Upstream ref moved while preparing the build." >&2
  echo "Expected: $EXPECTED_SHA" >&2
  echo "Actual:   $UPSTREAM_SHA" >&2
  exit 3
fi

if [[ "$CHANNEL" == "alpha" ]]; then
  VERSION="alpha-${UPSTREAM_SHA:0:7}"
fi

echo "Channel:      $CHANNEL"
echo "Upstream ref: $UPSTREAM_REF"
echo "Version:      $VERSION"
echo "Build branch: $BUILD_BRANCH"
echo "Release tag:  $RELEASE_TAG"

echo "Applying downstream patches..."
shopt -s nullglob
PATCHES=("$BUILDER_DIR"/patches/*.patch)
shopt -u nullglob

for patch in "${PATCHES[@]}"; do
  echo "  -> $(basename "$patch")"
  git -C "$SOURCE_DIR" apply --check "$patch"
  git -C "$SOURCE_DIR" apply "$patch"
done

git -C "$SOURCE_DIR" config user.name "github-actions[bot]"
git -C "$SOURCE_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$SOURCE_DIR" add -A

if ! git -C "$SOURCE_DIR" diff --cached --quiet; then
  git -C "$SOURCE_DIR" commit \
    -m "Downstream build changes for ${CHANNEL} ${VERSION}"
fi

PATCHED_SHA="$(git -C "$SOURCE_DIR" rev-parse HEAD)"

# Exact corresponding source for the binaries, including the patched workflow.
git -C "$SOURCE_DIR" archive \
  --format=tar.gz \
  --prefix=source/ \
  -o "$WORK_DIR/custom-core-source.tar.gz" \
  HEAD

git -C "$SOURCE_DIR" remote add downstream \
  "https://x-access-token:${GH_TOKEN}@github.com/${TARGET_REPOSITORY}.git"

# A temporary ref is required because actions/checkout in the original workflow
# must see the upstream source tree and its patched build.yml.
git -C "$SOURCE_DIR" push --force downstream \
  "HEAD:refs/heads/${BUILD_BRANCH}"

OLD_RUN_ID="$(
  gh run list \
    --repo "$TARGET_REPOSITORY" \
    --workflow build.yml \
    --branch "$BUILD_BRANCH" \
    --event workflow_dispatch \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty'
)"

echo "Dispatching upstream build workflow..."
gh workflow run build.yml \
  --repo "$TARGET_REPOSITORY" \
  --ref "$BUILD_BRANCH" \
  -f "version=$VERSION"

RUN_ID=""
for _ in $(seq 1 60); do
  CANDIDATE="$(
    gh run list \
      --repo "$TARGET_REPOSITORY" \
      --workflow build.yml \
      --branch "$BUILD_BRANCH" \
      --event workflow_dispatch \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // empty'
  )"

  if [[ -n "$CANDIDATE" && "$CANDIDATE" != "$OLD_RUN_ID" ]]; then
    RUN_ID="$CANDIDATE"
    break
  fi

  sleep 2
done

if [[ -z "$RUN_ID" ]]; then
  echo "Unable to locate the dispatched build workflow run." >&2
  exit 4
fi

echo "Build run: $RUN_ID"
gh run watch "$RUN_ID" \
  --repo "$TARGET_REPOSITORY" \
  --exit-status

mkdir -p "$DIST_DIR" "$RELEASE_DIR"

gh run download "$RUN_ID" \
  --repo "$TARGET_REPOSITORY" \
  --dir "$DIST_DIR"

# Publish only binary archives. The original CI may also create distro packages,
# toolchains and vendor archives; those remain workflow artifacts but are not
# copied into our downstream release.
while IFS= read -r -d '' file; do
  base="$(basename "$file")"
  cp "$file" "$RELEASE_DIR/$base"
done < <(
  find "$DIST_DIR" -type f \
    \( -name 'mihomo*.gz' -o -name 'mihomo*.zip' \) \
    -print0
)

cp "$WORK_DIR/custom-core-source.tar.gz" "$RELEASE_DIR/"
printf '%s\n' "$VERSION" > "$RELEASE_DIR/version.txt"

if ! find "$RELEASE_DIR" -maxdepth 1 -type f -name 'mihomo-*' | grep -q .; then
  echo "No binary archives were downloaded from the upstream build." >&2
  exit 5
fi

(
  cd "$RELEASE_DIR"
  find . -maxdepth 1 -type f ! -name checksums.txt ! -name version.txt -printf '%P\n' \
    | sort \
    | xargs sha256sum > checksums.txt
)

NOTES="$WORK_DIR/release-notes.txt"
{
  echo "Upstream: MetaCubeX/mihomo"
  echo "Upstream ref: $UPSTREAM_REF"
  echo "Upstream SHA: $UPSTREAM_SHA"
  echo "Patched source SHA: $PATCHED_SHA"
  echo "Runtime version: ${VERSION}-tiny"
  echo "Build tags: with_gvisor,no_easytier,no_tailscale,no_zerotier"
  echo
  echo "The exact corresponding source used for this build is attached as custom-core-source.tar.gz."
} > "$NOTES"

# The release tags point to the builder repository, not to a permanent mirror of
# the upstream codebase. Exact patched source is kept as a release asset instead.
BUILDER_SHA="$(git -C "$BUILDER_DIR" rev-parse HEAD)"

if gh release view "$RELEASE_TAG" \
    --repo "$TARGET_REPOSITORY" >/dev/null 2>&1; then

  echo "Replacing assets in existing release $RELEASE_TAG"

  mapfile -t OLD_ASSETS < <(
    gh release view "$RELEASE_TAG" \
      --repo "$TARGET_REPOSITORY" \
      --json assets \
      --jq '.assets[].name'
  )

  for asset in "${OLD_ASSETS[@]}"; do
    [[ -n "$asset" ]] || continue
    gh release delete-asset "$RELEASE_TAG" "$asset" \
      --repo "$TARGET_REPOSITORY" \
      --yes
  done

  gh release upload "$RELEASE_TAG" "$RELEASE_DIR"/* \
    --repo "$TARGET_REPOSITORY"

  if [[ "$CHANNEL" == "alpha" ]]; then
    gh release edit "$RELEASE_TAG" \
      --repo "$TARGET_REPOSITORY" \
      --title "Core Alpha ${UPSTREAM_SHA:0:7}" \
      --notes-file "$NOTES" \
      --prerelease
  else
    gh release edit "$RELEASE_TAG" \
      --repo "$TARGET_REPOSITORY" \
      --title "Core $RELEASE_TAG" \
      --notes-file "$NOTES"
  fi

else
  if [[ "$CHANNEL" == "alpha" ]]; then
    gh release create "$RELEASE_TAG" "$RELEASE_DIR"/* \
      --repo "$TARGET_REPOSITORY" \
      --target "$BUILDER_SHA" \
      --title "Core Alpha ${UPSTREAM_SHA:0:7}" \
      --notes-file "$NOTES" \
      --prerelease
  else
    gh release create "$RELEASE_TAG" "$RELEASE_DIR"/* \
      --repo "$TARGET_REPOSITORY" \
      --target "$BUILDER_SHA" \
      --title "Core $RELEASE_TAG" \
      --notes-file "$NOTES"
  fi
fi

echo "Published $RELEASE_TAG"
