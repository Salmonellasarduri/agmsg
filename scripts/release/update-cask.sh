#!/usr/bin/env bash
set -euo pipefail

# update-cask.sh <app-version> — update the Homebrew tap (fujibee/homebrew-agmsg)
# for an already-published app-v<version> GitHub Release.
#
#   1. find the release's .dmg asset (exactly one expected)
#   2. download it and compute the sha256
#   3. rewrite version/sha256/url in Casks/agmsg.rb
#   4. commit and push the tap
#
# Run AFTER the release assets are uploaded — the cask's url must resolve the
# moment the tap commit lands, or `brew install` breaks for anyone in between.
#
# The url is written with Homebrew's `#{version}` interpolation, derived from
# the actual asset name, so asset naming changes (e.g. a future productName
# rename dropping the "agmsg-app_" prefix) are picked up automatically.
#
# Requires: gh authenticated as fujibee (direnv pins GH_TOKEN for this repo),
# and push access to the tap over SSH. Override the tap remote with
# AGMSG_TAP_REMOTE if your SSH host alias differs.
#
# Usage: scripts/release/update-cask.sh 0.1.1

die() { echo "update-cask: $*" >&2; exit 1; }

VERSION="${1:-}"
[ -n "$VERSION" ] || die "usage: update-cask.sh <app-version>  (semver, no leading 'v' or 'app-v')"
case "$VERSION" in
  v*|app-*) die "version must be bare semver (got '$VERSION')" ;;
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) die "version must be semver MAJOR.MINOR.PATCH (got '$VERSION')" ;;
esac

TAG="app-v$VERSION"
TAP_REMOTE="${AGMSG_TAP_REMOTE:-git@github.com-fujibee:fujibee/homebrew-agmsg.git}"

command -v gh >/dev/null 2>&1 || die "gh not found"
who="$(gh api user --jq .login 2>/dev/null || true)"
[ "$who" = "fujibee" ] || die "gh identity is '$who', expected 'fujibee' (check direnv .envrc)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1. Exactly one .dmg asset on the release.
DMG_NAME="$(gh release view "$TAG" --repo fujibee/agmsg --json assets \
  --jq '[.assets[].name | select(endswith(".dmg"))] | .[]')"
[ -n "$DMG_NAME" ] || die "no .dmg asset on release $TAG"
[ "$(printf '%s\n' "$DMG_NAME" | wc -l)" -eq 1 ] \
  || die "multiple .dmg assets on release $TAG — can't pick one:
$DMG_NAME"
case "$DMG_NAME" in
  *"$VERSION"*) ;;
  *) die "asset '$DMG_NAME' does not contain version '$VERSION' — wrong release?" ;;
esac

# 2. Download + hash.
echo "==> Downloading $DMG_NAME from $TAG"
gh release download "$TAG" --repo fujibee/agmsg --pattern "$DMG_NAME" --dir "$TMP"
SHA="$(shasum -a 256 "$TMP/$DMG_NAME" | awk '{print $1}')"
echo "    sha256 $SHA"

# 3. Rewrite the cask. Derive the url template from the real asset name so the
#    cask keeps Homebrew's #{version} interpolation.
URL_ASSET="${DMG_NAME//$VERSION/#{version\}}"
URL="https://github.com/fujibee/agmsg/releases/download/app-v#{version}/$URL_ASSET"

echo "==> Updating tap"
git clone --depth 1 -q "$TAP_REMOTE" "$TMP/tap"
CASK="$TMP/tap/Casks/agmsg.rb"
[ -f "$CASK" ] || die "Casks/agmsg.rb not found in the tap"

sed -i '' \
  -e "s|^  version \".*\"$|  version \"$VERSION\"|" \
  -e "s|^  sha256 \".*\"$|  sha256 \"$SHA\"|" \
  -e "s|^  url \".*\"$|  url \"$URL\"|" \
  "$CASK"

grep -q "version \"$VERSION\"" "$CASK" || die "version rewrite failed — cask format changed?"
grep -q "sha256 \"$SHA\"" "$CASK" || die "sha256 rewrite failed — cask format changed?"

# 4. Commit + push (no-op safe: bail politely if nothing changed).
if git -C "$TMP/tap" diff --quiet; then
  echo "==> Tap already up to date for $VERSION — nothing to push"
  exit 0
fi
git -C "$TMP/tap" commit -aqm "agmsg $VERSION"
git -C "$TMP/tap" push -q origin HEAD
echo "==> Tap updated: agmsg $VERSION ($DMG_NAME)"
