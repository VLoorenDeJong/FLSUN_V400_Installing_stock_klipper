# Constraints

The generic "single authority for irreversible actions" and "never silence progress" principles behind the rules below live in the shared submodule:

@.claude/guiderails/bash-installer-conventions.md

FLSUN-specific application of those principles, plus hardware/domain constraints:

- Target OS is Ubuntu 20.04 → 22.04 on FLSUN's Speeder Pad hardware only (not the Super Racer). Don't assume a generic Debian/Ubuntu desktop — package names, default users, and paths are specific to this board's stock image.
- Everything is designed to run non-interactively where possible but several steps (KIAUH menus, network config) are inherently interactive; preserve `/dev/tty` prompting rather than trying to fully automate KIAUH's own TUI.
- This project does not replace or modify printer firmware — only the Speeder Pad's Linux/software environment. Don't add anything that touches the printer's MCU firmware.
- **Reboots only happen through `install_scripts/scripts/reboot.sh`** — this is this project's single reboot authority (see the generic principle above). No other script may call `reboot`, `shutdown -r`, `systemctl reboot`, or a backgrounded/timed reboot (e.g. `sleep N && reboot &`). A prior embedded safety-timer reboot in `add_network_manager.sh` fired mid-script during a live run, dropped SSH before the script's own restore logic ran, and required a full reflash to recover — see the WiFi ground rule in the top-level CLAUDE.md. The one accepted exception is Guilouz's vendored/downloaded `sp_installer1.sh` (`FallbackCopiedScripts/sp_installer1.sh` and the live-downloaded copy), which reboots at the end of Phase 1 by upstream design; do not add a second one.
