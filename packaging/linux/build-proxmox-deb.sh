#!/usr/bin/env bash
set -euo pipefail

# Build hecate-lampad-proxmox .deb from the sibling proxmox source tree.
# The proxmox postinst enables and starts hecate-lampad-proxmox.service.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROXMOX_DIR="${ROOT}/../hecate-lampad-proxmox"
VERSION="${VERSION:-$(grep '^version' "${ROOT}/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')}"
ARCH="amd64"
DIST="${ROOT}/dist"

if [ ! -f "${PROXMOX_DIR}/Cargo.toml" ]; then
  echo "Error: hecate-lampad-proxmox not found at ${PROXMOX_DIR}" >&2
  echo "Run ci/clone-deps.sh or clone the proxmox helper repo as a sibling." >&2
  exit 1
fi

cargo build --release --manifest-path "${PROXMOX_DIR}/Cargo.toml"
BINARY="${PROXMOX_DIR}/target/release/hecate-lampad-proxmox"

BUILT_VERSION="$("${BINARY}" --version 2>/dev/null | awk '{print $2}' || true)"
if [ -n "${BUILT_VERSION}" ] && [ "${BUILT_VERSION}" != "${VERSION}" ]; then
  echo "Error: proxmox binary reports ${BUILT_VERSION}, expected ${VERSION}" >&2
  exit 1
fi

mkdir -p "${DIST}"
bash "${PROXMOX_DIR}/packaging/linux/build-deb.sh" "${VERSION}" "${ARCH}" "${BINARY}" "${DIST}"
sha256sum "${DIST}/hecate-lampad-proxmox_${VERSION}_${ARCH}.deb" \
  > "${DIST}/hecate-lampad-proxmox_${VERSION}_${ARCH}.deb.sha256"
echo "Built ${DIST}/hecate-lampad-proxmox_${VERSION}_${ARCH}.deb"
