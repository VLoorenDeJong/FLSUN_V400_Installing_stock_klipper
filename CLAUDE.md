# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of Bash installer scripts that convert a stock FLSUN V400 Speeder Pad (Ubuntu 20.04, FLSUN's own firmware environment) into a Guilouz-style Klipper/Moonraker/Mainsail/KlipperScreen setup (Ubuntu 22.04). It is not an application with a build step — there is no compiled artifact, package manager, or app server. Everything runs directly on the Speeder Pad over SSH as root.

The scripts wrap and orchestrate several upstream projects (KIAUH, Klipper, Moonraker, Mainsail, Guilouz's `Klipper-Flsun-Speeder-Pad` config repo) rather than reimplementing them.

## Ground rules

- **All scripts are executed by `start_install.sh`**, but every script must also stand alone: no sourcing sibling scripts, no relying on variables/state set by a caller, no assuming another script already ran in the same shell. Each script is written to be copy-pasted and shared/run independently outside this repo — keep them self-contained when editing.
- **Same look and feel across every script**: identical root check, identical `SUDO_USER`/target-home resolution, identical color/status-message style. When adding or editing a script, match the existing pattern exactly rather than introducing a new formatting or structuring convention (see "Script conventions" below).
- **WiFi loss on the Speeder Pad is unrecoverable.** The Speeder Pad is WiFi-only — there is no ethernet fallback, no physical console access, nothing to fall back on. If a network-related script drops or misconfigures the WiFi connection mid-execution, the device is gone: no reconnection, no recovery, no remote fix, full stop. Treat any change touching networking (`add_network_manager.sh`, `configure_locale_and_wifi_country.sh`, `backup_config/timed_wifi_toggle/*`, `install_wifi_toggle_service.sh`, the archived connman/wpa_supplicant scripts) as maximally high-risk: prefer fail-safe ordering, avoid anything that could leave WiFi in a half-configured state, and call out the risk explicitly before proposing changes here.

## Commands

There is no build/lint/test toolchain in the traditional sense. The only checks are:

```shell
# Syntax-check every .sh file in the repo (bash -n / sh -n), excluding .git/.venv/venv
./install_scripts/check_shell_syntax_all.sh
```

This is also what CI-equivalent review expects before a PR (see README "Contributing"). Run it after editing any script.

Running the installer itself requires a real (or test) FLSUN V400 Speeder Pad and root:

```shell
sudo ./install_scripts/start_install.sh          # interactive menu
sudo ./install_scripts/start_install.sh -d        # same, with bash -x debug output for each sub-script
sudo bash -x install_scripts/scripts/<script>.sh  # debug a single script directly
```

`chmod -R +x .` should be re-run after adding/renaming scripts (README instructs users to do this before every run; it's safe to repeat).

## Architecture

### Entry point and orchestration

`install_scripts/start_install.sh` is the only entry point. It defines two ordered arrays of script names — `PHASE1_SCRIPTS` and `PHASE2_SCRIPTS` — and a menu that runs them via `run_sequence` → `run_script`. Individual scripts can also be run standalone through menu option 3 (`menu_individual`), which lists everything in `install_scripts/scripts/*.sh`.

- **Phase 1** (OS prep): password/SSH setup, repo cleanup, package updates, kernel update, distro upgrade 20.04→22.04, network manager + WiFi toggle service, then Guilouz's `sp_installer1` — which reboots the machine. Scripts run in the exact order listed in `PHASE1_SCRIPTS`.
- **Phase 2** (Klipper stack): Python setup, Guilouz's `sp_installer2`, KIAUH install, pip/venv fixes, two interactive KIAUH sessions (session 1 removes old FLSUN packages, session 2 installs Klipper/Moonraker/Mainsail), Klipper venv fix, KlipperScreen, USB symlink, Moonraker shutdown fix, restoring Guilouz configs, printer setting selection, FLSUN theme — ends with an optional-extras checklist (Webmin, Samba) and a final reboot.
- Phase order matters: later scripts assume earlier ones already ran (e.g. `fix_klipper_venv.sh` expects a `klippy-env` created by KIAUH in Phase 2). When adding a script to a phase array, place it where its dependencies are satisfied.
- Phase completion is tracked with marker files at `/var/lib/linuxsetups/phase{1,2}.done` (`phase_done`/`mark_phase_done` in `start_install.sh`); `migrate_phase_markers.sh` renames the old marker naming scheme on upgrade. A completed phase shows ✅ in the menu but isn't blocked from re-running via option 3.
- `run_script()` in `start_install.sh` contains a hardcoded case statement listing which script names trigger `fix_dpkg_lock.sh` beforehand (any script that touches `apt`/`dpkg`). New apt-touching scripts must be added to that case list or they'll race dpkg locks.
- Child scripts read prompts from `/dev/tty` explicitly (not stdin) because `start_install.sh` may have redirected/consumed its own stdin — follow this pattern for any new interactive script.

### Script conventions (install_scripts/scripts/*.sh)

- Root check at the top: `[ "$(id -u)" -ne 0 ]` → error and exit.
- Resolve the *real* (non-root) target user via `SUDO_USER`, falling back to the `pi` user or `whoami`, then their home dir via `getent passwd "$TARGET_USER" | cut -d: -f6`. Never assume `$HOME` is the printer user's home when running under `sudo`.
- Colored status output via either inline `printf`/`echo -e` with ANSI codes, or a local `print_status/print_success/print_warning/print_error/print_header` helper block — copy the pattern from a neighboring script rather than inventing new formatting.
- `show_progress()` (busy-dot indicator with a timeout, backgrounding the command and polling `kill -0`) is intentionally duplicated per-script rather than sourced from a shared lib (see comment in `install_python.sh`: "Inline show_progress (copied exactly)") — keep that duplication rather than introducing a shared import unless asked to refactor it.
- Idempotency: scripts that are expensive or order-sensitive (e.g. `install_python.sh`) write a state file under `/var/lib/linuxsetups/` and skip on rerun unless a `FORCE_RUN_*` env var is set.
- Logging: `start_install.sh` appends start/success/error lines to `/var/log/install_scripts.log`; some individual scripts also reference `/var/log/installer.log`, `/tmp/klippy.log`, `/var/log/moonraker.log` (see README "Log Locations").

### Supporting directories

- `install_scripts/scripts/Archived/` — retired scripts (ufw, connman, wpa_supplicant handling) kept for reference; not invoked by `start_install.sh`.
- `install_scripts/scripts/FallbackCopiedScripts/` — local copies of Guilouz's `sp_installer1.sh`/`sp_installer2.sh`, used by `add_flsun_speeder_pad_installer.sh` / `add_flsun_sp_installer2.sh` when the upstream download path fails.
- `backup_config/` — static assets deployed onto the printer rather than executed: a snapshot of Guilouz's `Klipper-Flsun-Speeder-Pad` repo, Mainsail theme files, `smb.conf`, and the `timed_wifi_toggle` systemd service + script (installed by `install_wifi_toggle_service.sh` — it periodically cycles the WiFi adapter because NetworkManager on this hardware is otherwise unstable).

## Constraints

- Target OS is Ubuntu 20.04 → 22.04 on FLSUN's Speeder Pad hardware only (not the Super Racer). Don't assume a generic Debian/Ubuntu desktop — package names, default users, and paths are specific to this board's stock image.
- Everything is designed to run non-interactively where possible but several steps (KIAUH menus, network config) are inherently interactive; preserve `/dev/tty` prompting rather than trying to fully automate KIAUH's own TUI.
- This project does not replace or modify printer firmware — only the Speeder Pad's Linux/software environment. Don't add anything that touches the printer's MCU firmware.
