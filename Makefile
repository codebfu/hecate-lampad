.PHONY: help prerequisites build test clean package package-agent package-desktop package-proxmox

help:
	@echo "hecate-lampad-linux — Linux agent binary and packaging"
	@echo ""
	@echo "Targets:"
	@echo "  help            Show this help (default)"
	@echo "  prerequisites   Verify Rust toolchain and fetch dependencies"
	@echo "  build           Build release agent binary"
	@echo "  test            Run tests"
	@echo "  clean           Remove build artifacts"
	@echo "  package         Build agent + desktop + proxmox .deb packages"
	@echo "  package-agent   Build hecate-lampad .deb only"
	@echo "  package-desktop Build hecate-lampad-desktop .deb only"
	@echo "  package-proxmox Build hecate-lampad-proxmox .deb only"

prerequisites:
	@echo "Checking Rust toolchain..."
	@command -v cargo >/dev/null 2>&1 || { echo "Error: cargo not found. Install Rust via https://rustup.rs"; exit 1; }
	cargo fetch

build: prerequisites
	cargo build --release

test: prerequisites
	cargo test

clean:
	cargo clean

package: package-agent package-desktop package-proxmox

package-agent: build
	@command -v dpkg-deb >/dev/null 2>&1 || { echo "Error: dpkg-deb not found (install dpkg)"; exit 1; }
	bash packaging/linux/build-deb.sh

package-desktop:
	@command -v dpkg-deb >/dev/null 2>&1 || { echo "Error: dpkg-deb not found (install dpkg)"; exit 1; }
	bash packaging/linux/build-desktop-deb.sh

package-proxmox:
	@command -v dpkg-deb >/dev/null 2>&1 || { echo "Error: dpkg-deb not found (install dpkg)"; exit 1; }
	bash packaging/linux/build-proxmox-deb.sh
