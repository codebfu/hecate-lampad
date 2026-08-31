#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
# shellcheck source=packaging/macos/common.sh
source "${ROOT}/packaging/macos/common.sh"

# shellcheck source=packaging/common/agent-version.sh
source "${ROOT}/packaging/common/agent-version.sh"
resolve_agent_package_version "${ROOT}"

DIST="${ROOT}/dist"
WORK="$(mktemp -d)"
CROSS_VERSION="${MACOS_CROSS_VERSION:-0.1.2}"
CROSS_ROOT="${MACOS_CROSS_ROOT:-/opt/macos-cross}"

trap 'rm -rf "${WORK}"' EXIT

install_cross_toolchain() {
  local arch="$1"
  local triple="$2"
  local tarball="${arch}-apple-darwin.tar.gz"
  local url="https://github.com/messense/macos-cross-compilers/releases/download/v${CROSS_VERSION}/${tarball}"

  if [ ! -x "${CROSS_ROOT}/${triple}/bin/${triple}-clang" ]; then
    mkdir -p "${CROSS_ROOT}"
    curl -fsSL -o "/tmp/${tarball}" "${url}"
    tar -xf "/tmp/${tarball}" -C "${CROSS_ROOT}"
    rm -f "/tmp/${tarball}"
  fi

  export "CC_${triple//-/_}=${CROSS_ROOT}/${triple}/bin/${triple}-clang"
  export "CXX_${triple//-/_}=${CROSS_ROOT}/${triple}/bin/${triple}-clang++"
  export "AR_${triple//-/_}=${CROSS_ROOT}/${triple}/bin/${triple}-ar"
  export "CARGO_TARGET_${triple//-/_}_LINKER=${CROSS_ROOT}/${triple}/bin/${triple}-clang"
}

package_arch() {
  local arch="$1"
  local triple="$2"
  local staging="${DIST}/macos-${arch}"
  local binary="target/${triple}/release/hecate-lampad"
  local sudoers_src="${ROOT}/packaging/sudoers/hecate-lampad"
  local install_helper="${ROOT}/packaging/install-elevation-policy.sh"

  install_cross_toolchain "${arch}" "${triple}"
  rustup target add "${triple}"
  cargo build --release --target "${triple}"

  rm -rf "${staging}"
  mkdir -p \
    "${staging}/usr/local/bin" \
    "${staging}/Library/LaunchDaemons" \
    "${staging}/etc/hecate-lampad" \
    "${staging}/etc/sudoers.d" \
    "${staging}/usr/local/etc/bash_completion.d" \
    "${staging}/usr/local/share/zsh/site-functions" \
    "${staging}/usr/local/share/fish/vendor_completions.d"
  install -m 755 "${binary}" "${staging}/usr/local/bin/hecate-lampad"
  install -m 644 packaging/macos/com.hecate.lampad.plist "${staging}/Library/LaunchDaemons/"
  install -m 440 "${sudoers_src}" "${staging}/etc/sudoers.d/hecate-lampad"
  install -m 755 packaging/macos/install.sh "${staging}/install.sh"
  install -m 755 "${install_helper}" "${staging}/install-elevation-policy.sh"
  install -m 644 README.md "${staging}/README.md"

  COMPLETIONS="${WORK}/completions-${arch}"
  bash packaging/stage-completions.sh "${ROOT}/completions" "${COMPLETIONS}"
  install -m 644 "${COMPLETIONS}/bash/hecate-lampad" "${staging}/usr/local/etc/bash_completion.d/"
  install -m 644 "${COMPLETIONS}/zsh/_hecate-lampad" "${staging}/usr/local/share/zsh/site-functions/"
  install -m 644 "${COMPLETIONS}/fish/hecate-lampad.fish" "${staging}/usr/local/share/fish/vendor_completions.d/"

  OUTPUT="${DIST}/hecate-lampad_${VERSION}_macos-${arch}.tar.gz"
  tar -czf "${OUTPUT}" -C "${staging}" .
  sha256_file "${OUTPUT}" > "${OUTPUT}.sha256"
  echo "Built ${OUTPUT}"
}

rm -rf "${DIST}"/*.tar.gz "${DIST}"/*.sha256
package_arch "x86_64" "x86_64-apple-darwin"
package_arch "aarch64" "aarch64-apple-darwin"
