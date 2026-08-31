#!/usr/bin/env bash
set -euo pipefail

# Build hecate-lampad-desktop macOS install PKG from the sibling desktop source tree.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=packaging/macos/common.sh
source "${ROOT}/packaging/macos/common.sh"

# Shell executors often skip login profiles.
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

DESKTOP_DIR="${ROOT}/../hecate-lampad-desktop"
VERSION="${VERSION:-$(grep '^version' "${ROOT}/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')}"
DIST="${ROOT}/dist"
ARCH="$(macos_package_arch)"
STAGING="${DIST}/macos-desktop-pkgroot-${ARCH}"
SCRIPTS="${ROOT}/packaging/macos/scripts-desktop"

if [ ! -f "${DESKTOP_DIR}/Cargo.toml" ]; then
  echo "Error: hecate-lampad-desktop not found at ${DESKTOP_DIR}" >&2
  exit 1
fi

cargo build --release --manifest-path "${DESKTOP_DIR}/Cargo.toml"

rm -f \
  "${DIST}"/hecate-lampad-desktop_*.pkg \
  "${DIST}"/hecate-lampad-desktop_*.pkg.sha256 \
  "${DIST}"/hecate-lampad-desktop_*.dmg \
  "${DIST}"/hecate-lampad-desktop_*.dmg.sha256
rm -rf "${STAGING}"
mkdir -p \
  "${STAGING}/usr/local/bin" \
  "${STAGING}/Library/LaunchAgents"

install -m 755 "${DESKTOP_DIR}/target/release/hecate-lampad-desktop" \
  "${STAGING}/usr/local/bin/hecate-lampad-desktop"
install -m 644 "${DESKTOP_DIR}/packaging/macos/com.hecate.lampad-desktop.plist" \
  "${STAGING}/Library/LaunchAgents/"

OUTPUT="${DIST}/hecate-lampad-desktop_${VERSION}_macos-${ARCH}.pkg"
create_pkg_from_root "${STAGING}" "${SCRIPTS}" "com.hecate.lampad-desktop" "${VERSION}" "${OUTPUT}"
sha256_file "${OUTPUT}" > "${OUTPUT}.sha256"
echo "Built ${OUTPUT}"
