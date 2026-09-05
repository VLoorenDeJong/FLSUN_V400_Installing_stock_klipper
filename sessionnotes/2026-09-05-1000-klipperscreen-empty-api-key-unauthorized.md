# Session: 2026-09-05 10:00: KlipperScreen file list Unauthorized (empty API key)

| | |
| --- | --- |
| Started / ended | 2026-09-05 ~09:40 to ~10:00 (CEST) |
| Repo / branch | FLSUN_V400_Installing_stock_klipper on `dev` (no repo code changed) |
| Machines touched | Speeder Pad `pi@192.168.2.23`, Ubuntu 22.04.5 LTS, kernel 4.9.191 aarch64 |
| Commits | this note only |
| Pushed | note only |

## Goal

After a Klipper stack update on 2026-09-04, the print-file browser on the
Speeder Pad screen shows no files and the spinner never stops. Find the cause,
plan a local fix, and prepare a PR to the fork that ships the bug.

## What happened

All diagnosis was live on the device over SSH. No repo file was edited.

1. Checked the gcode folder exists and is readable:

   ```
   ls -la ~/printer_data/gcodes | head
   ```

   Folder present, owned `pi:pi`, many subfolders. Not the cause.

2. Checked Moonraker server config:

   ```
   grep -A5 "\[server\]" ~/printer_data/config/moonraker.conf
   ```

   `host: 0.0.0.0`, `port: 7125`. Normal.

3. Read the Moonraker log:

   ```
   tail -30 ~/printer_data/logs/moonraker.log
   ```

   The meaningful lines:

   ```
   101 GET /websocket?token= (127.0.0.1)
   Connection 4048466680: Trusted Client attempt at user/api-key authentication failed.  Revoking trusted authentication.
   JSON-RPC Request Error - Requested Method: server.connection.identify, Code: -32602, Message: Invalid API Key
   JSON-RPC Request Error - Requested Method: printer.objects.subscribe, Code: -32602, Message: Unauthorized
   JSON-RPC Request Error - Requested Method: server.files.list, Code: -32602, Message: Unauthorized
   JSON-RPC Request Error - Requested Method: server.files.get_directory, Code: -32602, Message: Unauthorized
   ```

   Note the URL: `?token=` with nothing after it.

4. Read the KlipperScreen log:

   ```
   tail -40 ~/printer_data/logs/KlipperScreen.log
   ```

   KlipperScreen connects fine, subscribes, then:

   ```
   [files.py:_callback()] - {'code': -32602, 'message': 'Unauthorized'}
   [gcodes.py:load_files()] - {'jsonrpc': '2.0', 'error': {'code': -32602, 'message': 'Unauthorized'}, 'id': 4}
   ```

   That is the spinner: `load_files` never gets a list, so it waits forever.

   Versions from the same log:
   - Moonraker `v0.11.0-0-g985c1d0`
   - Klipper `v0.13.0-745-gf0892d82`
   - Moonraker API version `1.5.0`

5. Checked KlipperScreen config for a stale key:

   ```
   grep -n -i "api_key\|moonraker" ~/printer_data/config/KlipperScreen.conf
   ```

   Only `moonraker_host: 127.0.0.1` and `moonraker_port: 7125`.
   No `moonraker_api_key` line at all.

6. Checked Moonraker trusted clients:

   ```
   grep -A8 "\[authorization\]" ~/printer_data/config/moonraker.conf
   ```

   `127.0.0.0/8` is trusted. So the connection starts trusted and is then
   revoked by the bad key. That ordering is the whole bug.

7. Found the code that sends the empty key:

   ```
   grep -n "api_key\|token" ~/KlipperScreen/ks_includes/KlippyWebsocket.py
   ```

   ```
   33:        self.header = {"x-api-key": api_key} if api_key else {}
   34:        self.api_key = api_key
   63:        self.ws_url = f"{self.ws_proto}://{self._url}/websocket?token={self.api_key}"
   334:    def identify_client(self, version, api_key):
   343:                "api_key": f"{api_key}"
   ```

   Line 33 correctly omits the header when the key is falsy.
   Lines 63 and 343 do NOT: they interpolate it unconditionally.

8. Found where the empty value comes from:

   ```
   grep -rn "api_key" ~/KlipperScreen/ks_includes/config.py
   ```

   ```
   102: "moonraker_api_key": self.config.get(printer, "moonraker_api_key", fallback="")...
   ```

   Fallback is `""`. With no key configured, KlipperScreen sends `?token=`
   and `"api_key": ""`.

9. Identified the repo to report to:

   ```
   git -C ~/KlipperScreen remote -v
   git -C ~/KlipperScreen log --oneline -5 origin/master
   ```

   ```
   origin  https://github.com/Guilouz/KlipperScreen-Flsun-Speeder-Pad.git
   4a447b6 (HEAD -> master, origin/master) Update screen.py     # 2024-08-30
   ```

   Not upstream KlipperScreen. It is Guilouz's FLSUN fork, frozen at
   2024-08-30, while Moonraker moved on to v0.11.

## Causes

**Demonstrated cause.** KlipperScreen sends an empty API key to Moonraker.
Moonraker v0.11 treats a supplied-but-empty key as a failed authentication
attempt and revokes the connection's trusted status, even though the client IP
is in `trusted_clients`. Every later file call returns `Unauthorized`, so the
file panel spins forever.

Evidence chain, all from logs on the machine: `?token=` empty in the request
URL, then `Revoking trusted authentication`, then `Invalid API Key`, then
`Unauthorized` on `server.files.list` and `server.files.get_directory`, matched
by KlipperScreen's own `files.py:_callback()` receiving that same error.

**Whose software.** Not a bug in this repo. It is in
`KlipperScreen/ks_includes/KlippyWebsocket.py`, shipped by the Guilouz FLSUN
fork. The bug pattern is generic, nothing FLSUN- or V400-specific in it. What
is fork-specific is that the fork is pinned to 2024-08-30 code while Moonraker
kept updating.

Unproven: whether current upstream KlipperScreen already fixed this. Check
before filing.

## Ruled out

| Hypothesis | How it was eliminated |
| --- | --- |
| Missing or empty gcodes folder | `ls -la ~/printer_data/gcodes` shows many folders |
| Wrong permissions on gcodes | owned `pi:pi`, mode `drwxrwxr-x`, Moonraker runs as `pi` |
| Moonraker or Klipper not running | log shows `Klippy ready`, all services active |
| KlipperScreen pointed at wrong host or port | config has `127.0.0.1:7125`, matches Moonraker |
| Stale API key in KlipperScreen.conf | no `moonraker_api_key` line exists |
| API key file on disk | `~/.moonraker_api_key` and `~/printer_data/.moonraker_api_key` both absent |
| `127.0.0.1` not trusted by Moonraker | `127.0.0.0/8` is in `trusted_clients` |
| Wrong gcodes path in KlipperScreen | log: `Gcodes path: /home/pi/printer_data/gcodes` |

Unrelated log noise, deliberately ignored: OctoApp announcement `HTTP 404`, and
`Key 'general' in namespace 'mainsail' not found`.

## Changes

None. Nothing was edited, on the device or in this repo. The session ended
before the fix was applied.

## Verification

Nothing to verify. The fix is not applied yet.

## End state

Broken and live: the Speeder Pad print-file browser still shows no files and
still spins. Printing from the screen does not work. Printing from Mainsail in
a browser was not tested this session.

## Reproduction

### Reproduce the bug

1. Run the Guilouz FLSUN KlipperScreen fork at `4a447b6` with Moonraker
   `v0.11.x` and no `moonraker_api_key` in `KlipperScreen.conf`.
2. Tap the print icon on the Speeder Pad screen.
3. `~/printer_data/logs/moonraker.log` shows `Revoking trusted authentication`
   followed by `Unauthorized`.

### Apply the local fix - NEXT SESSION STARTS HERE

Step 1. Look at the two code blocks before patching. These are the two
commands parked for next time:

```
sed -n '330,350p' ~/KlipperScreen/ks_includes/KlippyWebsocket.py
```

```
sed -n '60,66p' ~/KlipperScreen/ks_includes/KlippyWebsocket.py
```

(`sed -n 'A,Bp' file` prints only lines A to B. It changes nothing.)

Step 2. Back up the file:

```
cp ~/KlipperScreen/ks_includes/KlippyWebsocket.py ~/KlippyWebsocket.py.bak
```

Step 3. Patch line 63 so the token is only appended when a key exists:

```
sed -i '63s|.*|        self.ws_url = f"{self.ws_proto}://{self._url}/websocket" + (f"?token={self.api_key}" if self.api_key else "")|' ~/KlipperScreen/ks_includes/KlippyWebsocket.py
```

(`sed -i '63s|.*|NEW|' file` edits in place: on line 63, replace the whole
line with NEW.)

Step 4. Patch line 343 so `"api_key"` is left out of the payload when the key
is empty. The block was inspected this session and reads:

```python
    def identify_client(self, version, api_key):
        logging.debug("Sending server.connection.identify")
        return self._ws.send_method(
            "server.connection.identify",
            {
                "client_name": "KlipperScreen",
                "version": f"{version}",
                "type": "display",
                "url": "https://github.com/KlipperScreen/KlipperScreen",
                "api_key": f"{api_key}"
            },
        )
```

Line 343 is the `"api_key"` line. Replace it with a conditional unpack, so the
key is absent instead of empty:

```
sed -i '343s|.*|                **({"api_key": f"{api_key}"} if api_key else {})|' ~/KlipperScreen/ks_includes/KlippyWebsocket.py
```

Then confirm the file still parses:

```
python3 -m py_compile ~/KlipperScreen/ks_includes/KlippyWebsocket.py && echo OK
```

Step 5. Restart and check:

```
sudo systemctl restart KlipperScreen
```

```
tail -20 ~/printer_data/logs/moonraker.log
```

Success looks like: no `Revoking trusted authentication` line, and no
`Unauthorized` on `server.files.list`. Files appear on the screen.

### Workaround if the patch goes wrong

Restore the backup, then set a real Moonraker API key in `KlipperScreen.conf`
as `moonraker_api_key: <REDACTED>` (read it from Mainsail, Settings, API key).
A real key satisfies Moonraker, so trust is never revoked.

## Open

1. Run the two `sed -n` inspection commands above, then apply the local fix.
2. Verify the file browser lists files after `systemctl restart KlipperScreen`.
3. Before filing: check whether upstream KlipperScreen already fixed this.
   Search their issues for `Revoking trusted authentication`.
4. Open a PR against
   `https://github.com/Guilouz/KlipperScreen-Flsun-Speeder-Pad` with the
   two-line fix. Include: fork commit `4a447b6`, Moonraker
   `v0.11.0-0-g985c1d0`, Klipper `v0.13.0-745-gf0892d82`, the Moonraker log
   lines above, and the point that line 33 already guards the falsy key while
   lines 63 and 343 do not.
5. Decide whether this repo should carry a post-install check or a README note,
   since every Speeder Pad on this fork plus a current Moonraker hits the same
   wall.
