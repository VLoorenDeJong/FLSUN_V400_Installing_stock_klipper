# FLSUN_V400_Installing_stock_klipper

## What this does

Automates the setup of stock Klipper on an FLSUN V400 Speeder Pad by running a sequence of installation scripts:

1. Clean up repositories and fix dpkg locks
2. Update OS packages and kernel
3. Upgrade the distro
4. Configure locale and Wi-Fi country
5. **Set a new login password** (prompted interactively for current or another user)
6. Install UFW (firewall) and SSH
7. Add Git branch name to bash prompt
8. Download and run the FLSUN Speeder Pad installer
9. Clone and install KIAUH (Klipper Installation And Update Helper)
10. Install Webmin (optional web-based admin panel)
11. Reboot

> **Note:** Samba (SMB file sharing) is included but disabled until the gcode folder path is configured in `backup_config/smb/smb.conf`.

## Supported hardware / OS
- FLSUN V400 Speeder Pad

---

## <span id="setting_up_the_basics">Setting up the basics</span>

1. Log into your Speeder Pad.

1. Check if Git is installed:
   ```shell
   git version
   ```
   - Installed → `git version 2.43.0`
   - Not installed → `Command 'git' not found` → [Install Git](#install_git)

1. Confirm internet is working:
   ```shell
   ping 8.8.8.8
   ```
   Press `CTRL + C` to stop. If there is no response, fix your network first.

1. Clone the repository:
   ```shell
   git clone https://github.com/VLoorenDeJong/FLSUN_V400_Installing_stock_klipper
   ```

1. Enter the folder:
   ```shell
   cd FLSUN_V400_Installing_stock_klipper
   ```
   *(Tip: type `cd FL` then press `TAB` for autocomplete)*

1. Check your OS version:
   ```shell
   lsb_release -a
   ```

1. List available branches:
   ```shell
   git branch -r
   ```

1. Switch to your version branch:
   ```shell
   git checkout YOUR_BRANCH_NAME
   ```
   *(No quotes, no `origin/`. Use `TAB` for autocomplete)*
   Success: `Switched to a new branch 'YOUR_BRANCH_NAME'`

1. Make scripts executable:
   ```shell
   sudo chmod -R +x .
   ```

1. Run the installer:
   ```shell
   sudo ./install_scripts/start_install.sh
   ```
   The installer automatically handles dpkg lock issues, OS updates, UFW, SSH, the FLSUN Speeder Pad installer, and KIAUH.

---

## Connecting with SSH

Download an SSH client → [MobaXterm (recommended)](https://mobaxterm.mobatek.net/download.html)

Find your local IP:
```shell
ip addr show
```
Look for `inet` under `eth0` (e.g. `2: eth0: ... inet 192.168.x.x`). Use that IP in your SSH client.

---

## <span id="install_git">Install Git</span>

```shell
sudo apt update && sudo apt install git && git --version
```
