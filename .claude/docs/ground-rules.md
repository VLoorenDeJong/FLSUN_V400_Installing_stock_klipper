# Ground rules

Generic self-containment and look-and-feel conventions (every script stands alone, consistent status-message style) live in the shared submodule — see:

@../guiderails/bash-installer-conventions.md

FLSUN-specific ground rules not covered by the generic conventions above:

- **WiFi loss on the Speeder Pad is unrecoverable.** The Speeder Pad is WiFi-only — there is no ethernet fallback, no physical console access, nothing to fall back on. If a network-related script drops or misconfigures the WiFi connection mid-execution, the device is gone: no reconnection, no recovery, no remote fix, full stop. Treat any change touching networking (`add_network_manager.sh`, `configure_locale_and_wifi_country.sh`, `backup_config/timed_wifi_toggle/*`, `install_wifi_toggle_service.sh`, the archived connman/wpa_supplicant scripts) as maximally high-risk: prefer fail-safe ordering, avoid anything that could leave WiFi in a half-configured state, and call out the risk explicitly before proposing changes here. `add_network_manager.sh` already implements the safe pattern — a detached handover script with state-capture and rollback instead of a synchronous restart in its own process (see [Architecture](architecture.md#network-handover-architecture-add_network_managersh)) — match that shape rather than reverting to something simpler.
- **Reboots only ever happen via `install_scripts/scripts/reboot.sh`.** No other script — new or edited — may call `reboot`, `shutdown -r`, `systemctl reboot`, or a backgrounded/timed reboot. A previous embedded safety-timer reboot in `add_network_manager.sh` fired mid-run over a live SSH session, dropped the connection before the script's own recovery logic executed, and the device required a full reflash. The only accepted exception is Guilouz's own `sp_installer1.sh` (vendored + live-downloaded), which reboots by upstream design at the end of Phase 1 — don't add a second reboot path anywhere else, and don't remove `reboot.sh`'s exclusivity to "simplify" a script.

For deeper reference, see: [Architecture](architecture.md) · [Script conventions](script-conventions.md) · [Constraints](constraints.md) · [shared generic conventions](../guiderails/bash-installer-conventions.md) (private submodule — see note in Commands below)
