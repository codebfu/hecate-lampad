use hecate_lampad_core::{
    collect_agent_tags, collect_status, default_runtime_status_path, generate_completion,
    build_enroll_request, local_hostname, parse_with_defaults, prepare_agent_enrollment,
    read_enrollment_token, run_agent_service, run_agent_update, submit_enrollment,
    AgentRunOptions, AgentUpdateOptions, Commands, PlatformDefaults, ServiceProbe, ServiceReport,
    ServiceStatus, StatusOptions, print_status_json, print_status_report,
};
use std::env::consts::{ARCH, OS};
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::info;

const DEFAULTS: PlatformDefaults = PlatformDefaults {
    about: "Hecate lampad agent (macOS)",
    config: "/etc/hecate-lampad/config.toml",
    key_path: "/etc/hecate-lampad/agent.key",
};

const SERVICE_LABEL: &str = "com.hecate.lampad";
const SERVICE_START_HINT: &str = "sudo launchctl bootstrap system /Library/LaunchDaemons/com.hecate.lampad.plist";

struct MacServiceProbe;

impl ServiceProbe for MacServiceProbe {
    fn probe(&self) -> ServiceReport {
        match Command::new("launchctl")
            .args(["print", &format!("system/{SERVICE_LABEL}")])
            .output()
        {
            Ok(output) if output.status.success() => {
                let detail = String::from_utf8_lossy(&output.stdout).to_string();
                let status = if detail.contains("state = running") {
                    ServiceStatus::Active
                } else {
                    ServiceStatus::Inactive
                };
                ServiceReport {
                    name: SERVICE_LABEL.into(),
                    status,
                    detail: Some("launchd".into()),
                    runtime: None,
                }
            }
            Ok(_) => ServiceReport {
                name: SERVICE_LABEL.into(),
                status: ServiceStatus::NotFound,
                detail: None,
                runtime: None,
            },
            Err(error) => ServiceReport {
                name: SERVICE_LABEL.into(),
                status: ServiceStatus::Unknown,
                detail: Some(format!("launchctl unavailable: {error}")),
                runtime: None,
            },
        }
    }
}


pub async fn run() -> anyhow::Result<()> {
    let cli = parse_with_defaults(DEFAULTS);

    if let Commands::Complete { shell } = cli.command {
        return generate_completion(DEFAULTS, shell).map_err(anyhow::Error::from);
    }

    match &cli.command {
        Commands::Status { .. } => {
            return run_status(&cli).await;
        }
        Commands::Update { .. } => {
            return run_update(&cli).await;
        }
        _ => {}
    }

    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    match cli.command {
        Commands::Enroll {
            server_url,
            token,
            token_file,
            tags,
        } => {
            enroll(
                server_url,
                cli.config,
                cli.key_path,
                cli.key_path_explicit,
                token,
                token_file,
                tags,
            )
            .await
        }
        Commands::Run => {
            run_agent_service(AgentRunOptions {
                config_path: cli.config,
                key_path: cli.key_path,
                runtime_status_path: default_runtime_status_path(),
            })
            .await
        }
        Commands::Update { .. } => unreachable!(),
        Commands::Status { .. } | Commands::Complete { .. } => unreachable!(),
    }
}

async fn run_update(cli: &hecate_lampad_core::Cli) -> anyhow::Result<()> {
    let Commands::Update { check } = &cli.command else {
        unreachable!()
    };

    run_agent_update(AgentUpdateOptions {
        config_path: cli.config.clone(),
        key_path: cli.key_path.clone(),
        check_only: *check,
    })
    .await
    .map_err(anyhow::Error::from)
}

async fn run_status(cli: &hecate_lampad_core::Cli) -> anyhow::Result<()> {
    let Commands::Status { json } = &cli.command else {
        unreachable!()
    };

    let report = collect_status(
        StatusOptions {
            config_path: cli.config.clone(),
            key_path: cli.key_path.clone(),
            service_name: "hecate-lampad".into(),
            service_start_hint: SERVICE_START_HINT.into(),
            enroll_hint: format!(
                "sudo hecate-lampad enroll --server-url <url> --token-file <path>"
            ),
            runtime_status_path: default_runtime_status_path(),
        },
        &MacServiceProbe,
    )
    .await;

    if *json {
        print_status_json(&report)?;
    } else {
        print_status_report(&report);
    }

    if report.exit_code != 0 {
        std::process::exit(report.exit_code);
    }
    Ok(())
}

async fn enroll(
    server_url: String,
    config_path: PathBuf,
    key_path: PathBuf,
    key_path_explicit: bool,
    token: Option<String>,
    token_file: Option<PathBuf>,
    config_tags: Vec<String>,
) -> anyhow::Result<()> {
    let enrollment_token = read_enrollment_token(token, token_file)?;
    let prep = prepare_agent_enrollment(
        &config_path,
        &key_path,
        Path::new(DEFAULTS.key_path),
        key_path_explicit,
    )?;

    let hostname = local_hostname();
    let tags = collect_agent_tags(&config_tags)?;
    let request = build_enroll_request(
        enrollment_token,
        &prep.keypair,
        hostname,
        OS.to_string(),
        ARCH.to_string(),
        tags,
        prep.existing_agent_id,
    );

    info!(server = %server_url, reenroll = prep.reenroll, "submitting enrollment request");
    submit_enrollment(
        server_url,
        config_path,
        key_path,
        request,
        config_tags,
        &prep.keypair.public_key_base64(),
        SERVICE_START_HINT,
        prep.existing_agent_id,
        prep.reenroll,
        prep.key_backup,
    )
    .await?;
    Ok(())
}
