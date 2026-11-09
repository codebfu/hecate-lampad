#!/usr/bin/env bash
# Copyright (C) 2026 Gaultier HUBERT
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build hecate-lampad.rpm inside Rocky Linux 8 so the binary links against
# glibc 2.28 (EL8 / Rocky 8 / Alma 8). Host ubuntu-latest glibc is too new.
#
# Usage:
#   VERSION=1.2.3 ./packaging/linux/build-rpm-in-el8.sh
# Optional:
#   EL8_IMAGE=rockylinux:8
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

if [[ -z "${VERSION:-}" ]]; then
  echo "VERSION is required (e.g. VERSION=1.0.11)" >&2
  exit 1
fi

VERSION="${VERSION#v}"
export VERSION
export HECATE_AGENT_VERSION="${HECATE_AGENT_VERSION:-$VERSION}"
HECATE_AGENT_VERSION="${HECATE_AGENT_VERSION#v}"
export HECATE_AGENT_VERSION

EL8_IMAGE="${EL8_IMAGE:-rockylinux:8}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to build an EL8-compatible RPM" >&2
  exit 1
fi

docker run --rm \
  -v "${ROOT}:/src:rw" \
  -w /src \
  -e VERSION="${VERSION}" \
  -e HECATE_AGENT_VERSION="${HECATE_AGENT_VERSION}" \
  -e RPM_RELEASE="${RPM_RELEASE:-1}" \
  -e CARGO_HOME=/src/.cargo-el8 \
  -e CARGO_TARGET_DIR=/src/target-el8 \
  "${EL8_IMAGE}" \
  bash -lc '
    set -euo pipefail
    dnf -y install gcc gcc-c++ make openssl-devel rpm-build tar gzip git curl
    cargo_env="${CARGO_HOME:-$HOME/.cargo}/env"
    if [[ ! -x "${CARGO_HOME:-$HOME/.cargo}/bin/rustc" ]]; then
      curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
    fi
    # shellcheck disable=SC1090
    source "${cargo_env}"
    rustc --version
    bash packaging/linux/build-rpm.sh
  '

echo "EL8 RPM build finished (artifacts under dist/)"
