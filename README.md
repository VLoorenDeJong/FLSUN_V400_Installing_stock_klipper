# FLSUN V400 Stock Klipper — Quick Guide

## Credits
- Based on [Guilouz/Klipper-Flsun-Speeder-Pad](https://github.com/Guilouz/Klipper-Flsun-Speeder-Pad)

---

## Supported
- FLSUN V400 Speeder Pad

---

## Install in One Go

1. Log in to your Speeder Pad (SSH or local).
2. Make sure you have Git:
   ```shell
   git --version
   ```
   If Git is missing → see [Install Git (if needed)](#install-git-if-needed)
3. Make sure you have internet:
   ```shell
   ping -c 1 8.8.8.8
   ```
4. Clone and run:
- `cd ...` — enter project folder
- `sudo chmod -R +x .` — make scripts executable (safe to repeat)
- `sudo ./install_scripts/start_install.sh` — start menu
   ```shell
   git clone https://github.com/VLoorenDeJong/FLSUN_V400_Installing_stock_klipper && cd FLSUN_V400_Installing_stock_klipper && sudo chmod -R +x . && sudo ./install_scripts/start_install.sh
   ```

---

## Phases (Auto-detected)
1. **Phase 1:** OS prep & upgrade (reboots)
2. **Phase 2:** FLSUN installer prep (reboots)
3. **Phase 3:** KIAUH & extras (no reboot)

**After each reboot:**
```shell
cd FLSUN_V400_Installing_stock_klipper && sudo chmod -R +x . && sudo ./install_scripts/start_install.sh
```
- `cd ...` — enter project folder
- `sudo chmod -R +x .` — make scripts executable (safe to repeat)
- `sudo ./install_scripts/start_install.sh` — start menu

Pick the next phase in the menu.

**To re-run a phase:**
1. Start the script
2. Press `o` for override
3. Select the phase

---

## SSH Access
- [MobaXterm (recommended)](https://mobaxterm.mobatek.net/download.html)
- Find your IP:
  ```shell
  ip addr show
  ```
  Look for `inet` under `eth0` (e.g. `192.168.x.x`)

---

## Install Git (if needed)
```shell
sudo apt update && sudo apt install git && git --version
```

---

## Note
Samba (SMB) is included but disabled until you set the gcode folder path in `backup_config/smb/smb.conf`.

![LTS/Normal](image-7.png)

![Sudoers config](image-5.png)

![Resolved.conf](image-8.png)