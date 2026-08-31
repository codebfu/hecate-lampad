//! Windows Service Control Manager host for the lampad agent.

use hecate_lampad_core::{default_runtime_status_path, run_agent_service, AgentRunOptions};
use std::ffi::OsString;
use std::sync::mpsc;
use std::time::Duration;
use windows_service::define_windows_service;
use windows_service::service::{
    ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
    ServiceType,
};
use windows_service::service_control_handler::{self, ServiceControlHandlerResult};
use windows_service::{service_dispatcher, Error as ServiceError};

use crate::{DEFAULTS, SERVICE_NAME};

const SERVICE_TYPE: ServiceType = ServiceType::OWN_PROCESS;
/// Win32 `ERROR_FAILED_SERVICE_CONTROLLER_CONNECT` — process was not started by SCM.
const ERROR_FAILED_SERVICE_CONTROLLER_CONNECT: i32 = 1063;

define_windows_service!(ffi_service_main, service_main);

/// Attempt to run as a Windows service.
///
/// Returns `true` when the process was started by the SCM (dispatcher ran to completion).
/// Returns `false` when launched as a normal console/CLI process so the caller can continue.
pub fn try_run_as_service() -> bool {
    match service_dispatcher::start(SERVICE_NAME, ffi_service_main) {
        Ok(()) => true,
        Err(ServiceError::Winapi(ref error))
            if error.raw_os_error() == Some(ERROR_FAILED_SERVICE_CONTROLLER_CONNECT) =>
        {
            false
        }
        Err(error) => {
            eprintln!("failed to connect to Windows service dispatcher: {error}");
            std::process::exit(1);
        }
    }
}

fn service_main(_arguments: Vec<OsString>) {
    if let Err(error) = run_service() {
        eprintln!("hecate-lampad service failed: {error}");
    }
}

fn run_service() -> windows_service::Result<()> {
    let (shutdown_tx, shutdown_rx) = mpsc::channel();

    let event_handler = move |control_event| -> ServiceControlHandlerResult {
        match control_event {
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            ServiceControl::Stop | ServiceControl::Shutdown => {
                let _ = shutdown_tx.send(());
                ServiceControlHandlerResult::NoError
            }
            _ => ServiceControlHandlerResult::NotImplemented,
        }
    };

    let status_handle = service_control_handler::register(SERVICE_NAME, event_handler)?;

    status_handle.set_service_status(ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: ServiceState::Running,
        controls_accepted: ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN,
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    // File logging is preferred under SCM (no console). Still init tracing for Event Log tools.
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .try_init();

    let agent = std::thread::Builder::new()
        .name("hecate-lampad-agent".into())
        .spawn(|| {
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .expect("tokio runtime");
            runtime.block_on(run_agent_service(AgentRunOptions {
                config_path: DEFAULTS.config.into(),
                key_path: DEFAULTS.key_path.into(),
                runtime_status_path: default_runtime_status_path(),
            }));
        })
        .expect("spawn agent thread");

    let _ = shutdown_rx.recv();
    drop(agent);

    status_handle.set_service_status(ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: ServiceState::StopPending,
        controls_accepted: ServiceControlAccept::empty(),
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 1,
        wait_hint: Duration::from_secs(5),
        process_id: None,
    })?;

    status_handle.set_service_status(ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: ServiceState::Stopped,
        controls_accepted: ServiceControlAccept::empty(),
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    // Agent loop is `!`; exit the process so SCM fully releases the service.
    std::process::exit(0);
}
