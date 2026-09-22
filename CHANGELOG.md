# Changelog

## 1.0.6 — 2026-09-22

- Auto-repair desktop IPC socket/token group to `hecate-ipc` when the helper recreates them without group access (hecate-lampad-core 1.0.6).

## 1.0.5 — 2026-09-22

- Always restore `/etc/hecate-lampad` ownership to `hecate-lampad:hecate-ipc` in postinst (guards against helper packages leaving the dir as `root:root` `0750`).
- Clearer readiness errors when config is not readable (hecate-lampad-core 1.0.5).

## 1.0.4 — 2026-09-21

- After Linux desktop helper install, activate live GUI sessions (hecate-lampad-core 1.0.4).

## 1.0.3 — 2026-08-31

- Auto-repair agent connectivity without manual `systemctl restart` after enroll (hecate-lampad-core 1.0.3).

## 1.0.1 — 2026-08-31

- Fix stale `pending_approval` in local config and runtime mode after server approval (hecate-lampad-core 1.0.1).

## 1.0.0 — 2026-08-31

Initial public release.

- Add `forget` command to clear local agent enrollment.
