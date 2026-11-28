#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOADER_ROOT="$REPO_ROOT/packages/loader"
IOS_ROOT="$LOADER_ROOT/ios"
PACKAGE_DIR="$IOS_ROOT/packages"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "this iOS tweak build requires a macOS runner"
[[ -n "${THEOS:-}" && -d "$THEOS/makefiles" ]] || fail "THEOS is unset or its makefiles directory is missing"

export THEOS_PACKAGE_SCHEME="${THEOS_PACKAGE_SCHEME:-roothide}"
export FINALPACKAGE=1

require_command unbound-tools
require_command gmake
require_command dpkg-deb
require_command shasum

printf 'Using unbound-tools: %s\n' "$(command -v unbound-tools)"
printf 'Using gmake: %s\n' "$(command -v gmake)"
printf 'Using dpkg-deb: %s\n' "$(command -v dpkg-deb)"
printf 'Using shasum: %s\n' "$(command -v shasum)"

mkdir -p "$PACKAGE_DIR"
rm -f "$PACKAGE_DIR"/*.deb "$PACKAGE_DIR"/*.deb.sha256

printf 'Building the iOS package from %s\n' "$LOADER_ROOT"
printf 'Theos: %s\n' "$THEOS"
printf 'Package scheme: %s\n' "$THEOS_PACKAGE_SCHEME"

unbound-tools build tweak \
  --root "$LOADER_ROOT" \
  --configuration release \
  --non-interactive

shopt -s nullglob
packages=("$PACKAGE_DIR"/*.deb)
[[ "${#packages[@]}" -eq 1 ]] || {
  printf 'Expected exactly one .deb package, found %s\n' "${#packages[@]}" >&2
  printf '%s\n' "${packages[@]}" >&2
  exit 1
}

deb="${packages[0]}"
dpkg-deb --info "$deb"

package_name="$(dpkg-deb -f "$deb" Package)"
architecture="$(dpkg-deb -f "$deb" Architecture)"
package_version="$(dpkg-deb -f "$deb" Version)"
[[ "$package_name" == "app.unbound.ios" ]] || fail "unexpected Debian package name: $package_name"
[[ "$architecture" == "iphoneos-arm64e" ]] || fail "unexpected Debian architecture: $architecture"
[[ "$package_version" == "1.13.0" ]] || fail "expected package version 1.13.0, got: $package_version"

shasum -a 256 "$deb" > "$deb.sha256"

printf '\nBuilt package: %s\n' "$deb"
printf 'Package: %s\nVersion: %s\nArchitecture: %s\n' "$package_name" "$package_version" "$architecture"
printf 'SHA-256: '
cat "$deb.sha256"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '### RootHide Debian package\n\n'
    printf '| Field | Value |\n|---|---|\n'
    printf '| Package | `%s` |\n' "$package_name"
    printf '| Architecture | `%s` |\n' "$architecture"
    printf '| File | `%s` |\n' "$(basename "$deb")"
    printf '| SHA-256 | `%s` |\n' "$(awk '{print $1}' "$deb.sha256")"
  } >> "$GITHUB_STEP_SUMMARY"
fi
