# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of Bash installer scripts that convert a stock FLSUN V400 Speeder Pad (Ubuntu 20.04, FLSUN's own firmware environment) into a Guilouz-style Klipper/Moonraker/Mainsail/KlipperScreen setup (Ubuntu 22.04). It is not an application with a build step — there is no compiled artifact, package manager, or app server. Everything runs directly on the Speeder Pad over SSH as root.

The scripts wrap and orchestrate several upstream projects (KIAUH, Klipper, Moonraker, Mainsail, Guilouz's `Klipper-Flsun-Speeder-Pad` config repo) rather than reimplementing them.

## Ground rules

- **All scripts are executed by `start_install.sh`**, but every script must also stand alone: no sourcing sibling scripts, no relying on variables/state set by a caller, no assuming another script already ran in the same shell. Each script is written to be copy-pasted and shared/run independently outside this repo — keep them self-contained when editing.
- **Same look and feel across every script**: identical root check, identical `SUDO_USER`/target-home resolution, identical color/status-message style. When adding or editing a script, match the existing pattern exactly rather than introducing a new formatting or structuring convention (see [Script conventions](.claude/docs/script-conventions.md)).
- **WiFi loss on the Speeder Pad is unrecoverable.** The Speeder Pad is WiFi-only — there is no ethernet fallback, no physical console access, nothing to fall back on. If a network-related script drops or misconfigures the WiFi connection mid-execution, the device is gone: no reconnection, no recovery, no remote fix, full stop. Treat any change touching networking (`add_network_manager.sh`, `configure_locale_and_wifi_country.sh`, `backup_config/timed_wifi_toggle/*`, `install_wifi_toggle_service.sh`, the archived connman/wpa_supplicant scripts) as maximally high-risk: prefer fail-safe ordering, avoid anything that could leave WiFi in a half-configured state, and call out the risk explicitly before proposing changes here. `add_network_manager.sh` already implements the safe pattern — a detached handover script with state-capture and rollback instead of a synchronous restart in its own process (see [Architecture](.claude/docs/architecture.md#network-handover-architecture-add_network_managersh)) — match that shape rather than reverting to something simpler.
- **Reboots only ever happen via `install_scripts/scripts/reboot.sh`.** No other script — new or edited — may call `reboot`, `shutdown -r`, `systemctl reboot`, or a backgrounded/timed reboot. A previous embedded safety-timer reboot in `add_network_manager.sh` fired mid-run over a live SSH session, dropped the connection before the script's own recovery logic executed, and the device required a full reflash. The only accepted exception is Guilouz's own `sp_installer1.sh` (vendored + live-downloaded), which reboots by upstream design at the end of Phase 1 — don't add a second reboot path anywhere else, and don't remove `reboot.sh`'s exclusivity to "simplify" a script.

For deeper reference, see: [Architecture](.claude/docs/architecture.md) · [Script conventions](.claude/docs/script-conventions.md) · [Constraints](.claude/docs/constraints.md) · [shared generic conventions](.claude/guiderails/bash-installer-conventions.md) (private submodule — see note in Commands below)

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

This repo has a git submodule at `.claude/guiderails` (private — holds generic, vendor-neutral conventions shared across multiple projects, not FLSUN-specific). On a fresh clone, run `git submodule update --init` to populate it. Anyone without access to the private `Guiderails` repo will get an empty directory there instead — that's expected and not an error to chase down.

## Architecture

@.claude/docs/architecture.md

## Script conventions

@.claude/docs/script-conventions.md

## Constraints

@.claude/docs/constraints.md
