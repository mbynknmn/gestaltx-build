#!/usr/bin/env bash
# Build GestaltX and package an ad-hoc signed IPA with the entitlements of the
# app and its share extension embedded. Re-signing tools such as AltStore and
# SideStore read the entitlements from the existing signature to decide which
# App Groups to register, so an unsigned IPA ends up without an App Group.
#
# Usage: .github/scripts/build-ipa.sh [output-dir]   (default: build/ipa)
#
# Set BUILD_DATE (YYYY-MM-DD) to write it to GestaltX/BuildDate.txt, which the
# About page shows. In GitHub Actions, `version` and `ipa` are written to
# GITHUB_OUTPUT.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$(mkdir -p "${1:-$root/build/ipa}" && cd "${1:-$root/build/ipa}" && pwd)"
cd "$root"

# Every target must share one marketing version
version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);/\1/p' GestaltX.xcodeproj/project.pbxproj | sort -u)"
if [[ -z "$version" || "$(wc -l <<< "$version")" -ne 1 ]]; then
  echo "Error: expected one MARKETING_VERSION, found: ${version:-none}" >&2
  exit 1
fi
echo "==> Building GestaltX $version"

if [[ -n "${BUILD_DATE:-}" ]]; then
  printf '%s' "$BUILD_DATE" > GestaltX/BuildDate.txt
fi

# Locale JSON files must be compiled into the catalog used by both targets.
if [[ -f scripts/generate_localization.py ]]; then
  python3 scripts/generate_localization.py
fi

# Building the app target also builds the embedded share extension
xcodebuild -quiet \
  -project GestaltX.xcodeproj \
  -target GestaltX \
  -configuration Release \
  -sdk iphoneos \
  SYMROOT="$root/build" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload" "$out"
cp -R "$root/build/Release-iphoneos/GestaltX.app" "$stage/Payload/"
app="$stage/Payload/GestaltX.app"
appex="$app/PlugIns/GestaltXShare.appex"

echo "==> Signing with entitlements"
# Sign nested code from the inside out: frameworks and dylibs, then the
# extension, then the app
while IFS= read -r -d '' item; do
  codesign -f -s - "$item"
done < <(find "$app" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)

# Older versions have no share extension
bundles=()
if [[ -d "$appex" ]]; then
  codesign -f -s - --entitlements ShareExtension/GestaltXShare.entitlements "$appex"
  bundles+=("$appex")
fi
codesign -f -s - --entitlements GestaltX/GestaltX.entitlements "$app"
bundles+=("$app")

# Check the actual embedded signature, not just the entitlement source files.
python3 - "${bundles[@]}" <<'VERIFY_ENTITLEMENTS'
import plistlib, subprocess, sys
common = None
for bundle in sys.argv[1:]:
    subprocess.run(["codesign", "--verify", "--strict", bundle], check=True)
    result = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", bundle], capture_output=True, check=True)
    entitlements = plistlib.loads(result.stdout)
    groups = entitlements.get("com.apple.security.application-groups", [])
    if not isinstance(groups, list) or not groups or not all(isinstance(group, str) and group for group in groups):
        raise SystemExit("Missing usable App Group entitlements in a signed bundle")
    if entitlements.get("com.apple.developer.team-identifier"):
        raise SystemExit("A developer Team ID must not be embedded in the ad-hoc package")
    metadata = subprocess.run(["codesign", "-dvv", bundle], capture_output=True, text=True, check=True).stderr
    if "Signature=adhoc" not in metadata or "TeamIdentifier=not set" not in metadata:
        raise SystemExit("Expected an ad-hoc signature without a developer identity")
    common = set(groups) if common is None else common.intersection(groups)
if not common:
    raise SystemExit("The app and share extension do not have a common App Group")
print("App and embedded extensions retain common App Groups with ad-hoc signatures.")
VERIFY_ENTITLEMENTS

ipa="$out/GestaltX_$version.ipa"
# Keep an existing package until the replacement is complete.
(cd "$stage" && zip -qry "$stage/GestaltX_$version.ipa" Payload)
mv -f "$stage/GestaltX_$version.ipa" "$ipa"
echo "==> Wrote $ipa"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$version"
    echo "ipa=$ipa"
  } >> "$GITHUB_OUTPUT"
fi
