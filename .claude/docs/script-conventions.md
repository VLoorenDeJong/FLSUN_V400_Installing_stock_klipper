# Script conventions (install_scripts/scripts/*.sh)

Generic script-writing conventions (progress indicators, sudo/env semantics, self-containment, `/dev/tty` prompting, distro-default package preference, handover/rollback for self-endangering operations, single-authority for irreversible actions) live in the shared submodule — see:

@.claude/guiderails/bash-installer-conventions.md

FLSUN-specific conventions not covered by the generic rules above:

- Debug mode: `start_install.sh -d` exports `FLSUN_DEBUG=1` (and runs sub-scripts with `bash -x`). The inline `show_progress` / `run_with_log_progress` helpers honor it: `FLSUN_DEBUG=1` streams command output live; otherwise output is captured to a temp log and the last lines are printed on failure (see the "never discard output" rule in the shared submodule).
- Idempotency state files live under `/var/lib/linuxsetups/` (e.g. `install_python_latest.done`, `klipperscreen_guilouz.done`) and are skipped on rerun unless the script's specific `FORCE_RUN_*` env var is set.
- Logging: `start_install.sh` appends start/success/error lines to `/var/log/install_scripts.log`; some individual scripts also reference `/var/log/installer.log`, `/tmp/klippy.log`, `/var/log/moonraker.log` (see README "Log Locations").
