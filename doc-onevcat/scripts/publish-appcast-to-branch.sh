#!/usr/bin/env bash
set -euo pipefail

SOURCE_FILE="${1:-}"
TARGET_BRANCH="${2:-sparkle-appcast}"
TARGET_PATH="${3:-appcast.xml}"
COMMIT_MESSAGE="${4:-Update Sparkle appcast}"

die() {
  echo "[appcast] error: $*" >&2
  exit 1
}

[[ -n "$SOURCE_FILE" ]] || die "source file path is required"
[[ -f "$SOURCE_FILE" ]] || die "source file not found: $SOURCE_FILE"

REPO_URL="$(git remote get-url origin 2>/dev/null || true)"
[[ -n "$REPO_URL" ]] || die "cannot determine origin remote URL"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

git init -q "$TMP_DIR"
pushd "$TMP_DIR" >/dev/null
git remote add origin "$REPO_URL"

if git fetch --depth=1 origin "$TARGET_BRANCH" >/dev/null 2>&1; then
  git checkout -B "$TARGET_BRANCH" "FETCH_HEAD" >/dev/null 2>&1
else
  git checkout --orphan "$TARGET_BRANCH" >/dev/null 2>&1
  find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
fi

mkdir -p "$(dirname "$TARGET_PATH")"
cp "$OLDPWD/$SOURCE_FILE" "$TARGET_PATH"

git config user.name "${GIT_COMMITTER_NAME:-github-actions[bot]}"
git config user.email "${GIT_COMMITTER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
git add "$TARGET_PATH"

if git diff --cached --quiet; then
  echo "[appcast] unchanged"
  popd >/dev/null
  exit 0
fi

git commit -m "$COMMIT_MESSAGE" >/dev/null
git push origin "HEAD:$TARGET_BRANCH"
popd >/dev/null
echo "[appcast] published to $TARGET_BRANCH:$TARGET_PATH"
