#!/usr/bin/env bash
set -euo pipefail

REMOTE="origin"
DRY_RUN=0
DEFAULT_FIRST_TAG="v0.1.0"

usage() {
  cat <<EOF
usage: $0 [--remote <name>] [--dry-run] [version] [message]

Create and push an annotated release tag. When version is omitted, the script
bumps the latest vX.Y.Z tag by one patch version. Pushing a v* tag triggers the
GitHub Actions package build and release publishing workflow.

Examples:
  $0
  $0 v0.2.0 "Release v0.2.0"
  $0 --dry-run
EOF
}

latest_semver_tag() {
  git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname |
    while IFS= read -r tag; do
      if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf "%s" "$tag"
        return 0
      fi
    done
}

next_patch_tag() {
  local latest="$1"

  if [[ -z "$latest" ]]; then
    printf "%s" "$DEFAULT_FIRST_TAG"
    return 0
  fi

  if [[ "$latest" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    printf "v%s.%s.%s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$((BASH_REMATCH[3] + 1))"
  else
    echo "latest tag is not a stable semver tag: $latest" >&2
    return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      if [[ $# -lt 2 ]]; then
        echo "--remote requires a value" >&2
        exit 2
      fi
      REMOTE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "not inside a git repository" >&2
  exit 1
fi

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  echo "git remote '$REMOTE' does not exist" >&2
  exit 1
fi

git fetch --tags "$REMOTE" >/dev/null

if [[ $# -eq 0 ]]; then
  LATEST_TAG="$(latest_semver_tag)"
  TAG="$(next_patch_tag "$LATEST_TAG")"
elif [[ $# -eq 1 ]]; then
  TAG="$1"
else
  TAG="$1"
  MESSAGE="$2"
fi

if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
  echo "version must look like v1.2.3 or v1.2.3-beta.1" >&2
  exit 2
fi

MESSAGE="${MESSAGE:-Release $TAG}"

if [[ -n "$(git status --porcelain)" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "warning: working tree is not clean; real tagging would fail until changes are committed or stashed" >&2
  else
    echo "working tree is not clean; commit or stash changes before tagging" >&2
    exit 1
  fi
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "local tag already exists: $TAG" >&2
  exit 1
fi

if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "remote tag already exists on $REMOTE: $TAG" >&2
  exit 1
fi

CURRENT_COMMIT="$(git rev-parse --short HEAD)"

cat <<EOF
Release tag: $TAG
Commit:      $CURRENT_COMMIT
Remote:      $REMOTE
Message:     $MESSAGE
EOF

if [[ "$DRY_RUN" == "1" ]]; then
  echo "dry run: tag was not created or pushed"
  exit 0
fi

git tag -a "$TAG" -m "$MESSAGE"
git push "$REMOTE" "$TAG"

echo "Pushed $TAG. GitHub Actions will build and publish the release package."
