#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
# shellcheck source=packaging/macos/common.sh
source "${ROOT}/packaging/macos/common.sh"

# Shell executors often skip login profiles.
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

# shellcheck source=packaging/common/agent-version.sh
source "${ROOT}/packaging/common/agent-version.sh"
resolve_agent_package_version "${ROOT}"

DIST="${ROOT}/dist"
ARCH="$(macos_package_arch)"
STAGING="${DIST}/macos-pkgroot-${ARCH}"
SCRIPTS="${ROOT}/packaging/macos/scripts-agent"
SUDOERS_SRC="${ROOT}/packaging/sudoers/hecate-lampad"

cargo build --release

# Agent installer only (do not wipe desktop packages).
rm -f \
  "${DIST}"/hecate-lampad_*.pkg \
  "${DIST}"/hecate-lampad_*.pkg.sha256 \
  "${DIST}"/hecate-lampad_*.dmg \
  "${DIST}"/hecate-lampad_*.dmg.sha256
rm -rf "${STAGING}"
mkdir -p \
  "${STAGING}/usr/local/bin" \
  "${STAGING}/Library/LaunchDaemons" \
  "${STAGING}/etc/hecate-lampad" \
  "${STAGING}/etc/sudoers.d"
install -m 755 target/release/hecate-lampad "${STAGING}/usr/local/bin/hecate-lampad"
install -m 644 packaging/macos/com.hecate.lampad.plist "${STAGING}/Library/LaunchDaemons/"
install -m 440 "${SUDOERS_SRC}" "${STAGING}/etc/sudoers.d/hecate-lampad"

OUTPUT="${DIST}/hecate-lampad_${VERSION}_macos-${ARCH}.pkg"
create_pkg_from_root "${STAGING}" "${SCRIPTS}" "com.hecate.lampad" "${VERSION}" "${OUTPUT}"
sha256_file "${OUTPUT}" > "${OUTPUT}.sha256"
echo "Built ${OUTPUT}"
