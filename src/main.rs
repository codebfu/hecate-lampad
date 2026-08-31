//! Copyright (C) 2026 Gaultier HUBERT
//! SPDX-License-Identifier: GPL-3.0-or-later

#[cfg(windows)]
mod windows_service_host;

mod platform;

#[cfg(windows)]
use hecate_lampad_core::PlatformDefaults;

#[cfg(windows)]
pub(crate) const DEFAULTS: PlatformDefaults = PlatformDefaults {
    about: "Hecate lampad agent (Windows)",
    config: r"C:\ProgramData\hecate-lampad\config.toml",
    key_path: r"C:\ProgramData\hecate-lampad\agent.key",
};

#[cfg(windows)]
pub(crate) const SERVICE_NAME: &str = "hecate-lampad";

#[cfg(windows)]
fn main() {
    if let Err(error) = platform::run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

#[cfg(not(windows))]
#[tokio::main]
async fn main() {
    if let Err(error) = platform::run().await {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
