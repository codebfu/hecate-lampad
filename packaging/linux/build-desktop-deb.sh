#!/usr/bin/env bash
set -euo pipefail

# Build hecate-lampad-desktop .deb from the sibling desktop source tree.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_DIR="${ROOT}/../hecate-lampad-desktop"
VERSION="${VERSION:-$(grep '^version' "${ROOT}/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')}"
ARCH="amd64"
DIST="${ROOT}/dist"

if [ ! -f "${DESKTOP_DIR}/Cargo.toml" ]; then
  echo "Error: hecate-lampad-desktop not found at ${DESKTOP_DIR}" >&2
  echo "Run ci/clone-deps.sh or clone the desktop repo as a sibling." >&2
  exit 1
fi

cargo build --release --manifest-path "${DESKTOP_DIR}/Cargo.toml"
BINARY="${DESKTOP_DIR}/target/release/hecate-lampad-desktop"

BUILT_VERSION="$("${BINARY}" --version 2>/dev/null | awk '{print $2}' || true)"
if [ -n "${BUILT_VERSION}" ] && [ "${BUILT_VERSION}" != "${VERSION}" ]; then
  echo "Error: desktop binary reports ${BUILT_VERSION}, expected ${VERSION}" >&2
  exit 1
fi

mkdir -p "${DIST}"
bash "${DESKTOP_DIR}/packaging/linux/build-deb.sh" "${VERSION}" "${ARCH}" "${BINARY}" "${DIST}"
sha256sum "${DIST}/hecate-lampad-desktop_${VERSION}_${ARCH}.deb" \
  > "${DIST}/hecate-lampad-desktop_${VERSION}_${ARCH}.deb.sha256"
echo "Built ${DIST}/hecate-lampad-desktop_${VERSION}_${ARCH}.deb"
