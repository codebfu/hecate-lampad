
use hecate_lampad_core::{
    collect_agent_tags, collect_status, default_runtime_status_path, forget_agent_enrollment,
    generate_completion, build_enroll_request, local_hostname, parse_with_defaults,
    prepare_agent_enrollment, print_forget_report, read_enrollment_token, run_agent_service,
    run_agent_update, submit_enrollment, AgentRunOptions, AgentUpdateOptions, Commands,
    ForgetEnrollmentOptions, ServiceProbe, ServiceReport, ServiceStatus, StatusOptions,
    print_status_json, print_status_report,
};
use std::env::consts::{ARCH, OS};
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::info;

use crate::{DEFAULTS, SERVICE_NAME};

const SERVICE_START_HINT: &str = r"sc start hecate-lampad";

struct WindowsServiceProbe;

impl ServiceProbe for WindowsServiceProbe {
    fn probe(&self) -> ServiceReport {
        match Command::new("sc").args(["query", SERVICE_NAME]).output() {
            Ok(output) => {
                let detail = String::from_utf8_lossy(&output.stdout).to_string();
                let status = if !output.status.success()
                    || detail.to_ascii_lowercase().contains("specified service does not exist")
                {
                    ServiceStatus::NotFound
                } else if detail.contains("RUNNING") {
                    ServiceStatus::Active
                } else if detail.contains("STOPPED") {
                    ServiceStatus::Inactive
                } else if detail.contains("STOP_PENDING") || detail.contains("START_PENDING") {
                    ServiceStatus::Unknown
                } else {
                    ServiceStatus::Unknown
                };
                ServiceReport {
                    name: SERVICE_NAME.into(),
                    status,
                    detail: Some(summarize_sc_state(&detail)),
                    runtime: None,
                }
            }
            Err(error) => ServiceReport {
                name: SERVICE_NAME.into(),
                status: ServiceStatus::Unknown,
                detail: Some(format!("sc unavailable: {error}")),
                runtime: None,
            },
        }
    }
}

fn summarize_sc_state(sc_output: &str) -> String {
    for line in sc_output.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("STATE") {
            return trimmed.to_string();
        }
    }
    "sc query".into()
}

pub fn run() -> anyhow::Result<()> {
    // Must run before Tokio / clap when launched by the Service Control Manager.
    if crate::windows_service_host::try_run_as_service() {
        return Ok(());
    }
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(run_cli())
}


async fn run_cli() -> anyhow::Result<()> {
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
        Commands::Forget => {
            return run_forget(&cli);
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
        Commands::Status { .. } | Commands::Complete { .. } | Commands::Forget => unreachable!(),
    }
}

fn run_forget(cli: &hecate_lampad_core::Cli) -> anyhow::Result<()> {
    let report = forget_agent_enrollment(ForgetEnrollmentOptions {
        config_path: cli.config.clone(),
        key_path: cli.key_path.clone(),
        runtime_status_path: default_runtime_status_path(),
    })?;
    print_forget_report(&report);
    Ok(())
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
            service_name: SERVICE_NAME.into(),
            service_start_hint: SERVICE_START_HINT.into(),
            enroll_hint: format!(
                "hecate-lampad enroll --server-url <url> --token-file <path>"
            ),
            runtime_status_path: default_runtime_status_path(),
        },
        &WindowsServiceProbe,
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
