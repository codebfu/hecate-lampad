fn main() {
    println!("cargo:rerun-if-changed=../hecate-lampad-core/src/cli.rs");

    let defaults = hecate_lampad_core::PlatformDefaults {
        about: "Hecate lampad agent (Linux)",
        config: "/etc/hecate-lampad/config.toml",
        key_path: "/etc/hecate-lampad/agent.key",
    };

    let output_dir = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap())
        .join("completions");
    hecate_lampad_core::generate_completions_to_dir(defaults, &output_dir)
        .expect("failed to generate shell completions");
}
