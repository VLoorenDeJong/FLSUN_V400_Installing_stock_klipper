# Architecture

## Entry point and orchestration

`install_scripts/start_install.sh` is the only entry point. It defines two ordered arrays of script names — `PHASE1_SCRIPTS` and `PHASE2_SCRIPTS` — and a menu that runs them via `run_sequence` → `run_script`. Individual scripts can also be run standalone through menu option 3 (`menu_individual`), which lists everything in `install_scripts/scripts/*.sh`.

- **Phase 1** (OS prep): password/SSH setup, repo cleanup, package updates, kernel update, distro upgrade 20.04→22.04, network manager + WiFi toggle service, then Guilouz's `sp_installer1` — which reboots the machine. Scripts run in the exact order listed in `PHASE1_SCRIPTS`.
- **Phase 2** (Klipper stack): Python setup, Guilouz's `sp_installer2`, KIAUH install, pip/venv fixes, two interactive KIAUH sessions (session 1 removes old FLSUN packages, session 2 installs Klipper/Moonraker/Mainsail), Klipper venv fix, KlipperScreen, USB symlink, Moonraker shutdown fix, restoring Guilouz configs, printer setting selection, FLSUN theme — ends with an optional-extras checklist (Webmin, Samba) and a final reboot.
- Phase order matters: later scripts assume earlier ones already ran (e.g. `fix_klipper_venv.sh` expects a `klippy-env` created by KIAUH in Phase 2). When adding a script to a phase array, place it where its dependencies are satisfied.
- Phase completion is tracked with marker files at `/var/lib/linuxsetups/phase{1,2}.done` (`phase_done`/`mark_phase_done` in `start_install.sh`); `migrate_phase_markers.sh` renames the old marker naming scheme on upgrade. A completed phase shows ✅ in the menu but isn't blocked from re-running via option 3.
- `run_script()` in `start_install.sh` contains a hardcoded case statement listing which script names trigger `fix_dpkg_lock.sh` beforehand (any script that touches `apt`/`dpkg`). New apt-touching scripts must be added to that case list or they'll race dpkg locks.
- Child scripts read prompts from `/dev/tty` explicitly (not stdin) because `start_install.sh` may have redirected/consumed its own stdin — follow this pattern for any new interactive script.

## Supporting directories

- `install_scripts/scripts/Archived/` — retired scripts (ufw, connman, wpa_supplicant handling) kept for reference; not invoked by `start_install.sh`.
- `install_scripts/scripts/FallbackCopiedScripts/` — local copies of Guilouz's `sp_installer1.sh`/`sp_installer2.sh`, used by `add_flsun_speeder_pad_installer.sh` / `add_flsun_sp_installer2.sh` when the upstream download path fails.
- `backup_config/` — static assets deployed onto the printer rather than executed: a snapshot of Guilouz's `Klipper-Flsun-Speeder-Pad` repo, Mainsail theme files, `smb.conf`, and the `timed_wifi_toggle` systemd service + script (installed by `install_wifi_toggle_service.sh` — it periodically cycles the WiFi adapter because NetworkManager on this hardware is otherwise unstable).

## Network handover architecture (add_network_manager.sh)

Implements the generic "handling operations that can cut your own access" principle from the shared submodule:

@.claude/guiderails/bash-installer-conventions.md

FLSUN-specific implementation: `add_network_manager.sh` does NOT reboot and does NOT synchronously restart networking in its own process. It configures NetworkManager, captures pre-change state (`NET_HAD_NETWORKD`, `NET_HAD_WPA`, `NET_GATEWAY` — captured *before* any DNS-refresh section that would disturb routes), then writes and launches a detached (`setsid`) handover script (`/tmp/nm-handover.sh`, logs to `/var/log/nm-handover.log`) that:

1. Stops the old network stack (`systemd-networkd` and friends, standalone `wpa_supplicant` processes not owned by NetworkManager — raw wpa_supplicant holding wlan0 blocks NM association on this hardware).
2. Restarts NM and brings the connection up (`nmcli connection up "$SSID"`).
3. Verifies success via NM device state (`nmcli -t -f DEVICE,STATE device status` showing `wlan0:connected`) — NOT an internet ping, since this device can run LAN-only with no default gateway.
4. On failure, rolls back by re-enabling whatever was running before (per the captured flags).

This exists because a prior synchronous redesign attempt dropped SSH mid-script and could not recover — see the WiFi-unrecoverable ground rule in the top-level CLAUDE.md. Any future edit to this script must preserve the detached-handover + rollback shape; do not collapse it back into a synchronous restart in the caller's own process.
