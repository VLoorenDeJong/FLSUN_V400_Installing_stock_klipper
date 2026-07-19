# LinuxBasics adoption plan

This branch (`dev`) wires in the shared `LinuxBasics` submodule.
It holds generic Debian-family install scripts.
Repo: <https://github.com/VLoorenDeJong/LinuxSetups_installing_basics>
Both repos are public. No private references involved.

## What is done on this branch

- `LinuxBasics/` added as a git submodule.
- `start_install.sh` understands a `basics/` prefix.
  Entries like `basics/cleanup_repositories.sh` run the submodule copy.
- Phase 2 uses basics copies for three scripts:
  `check_shell_syntax.sh`, `set_scripts_executable.sh`, `cleanup_repositories.sh`.
- Phase 1 still uses the local copies. See below why.

## Why Phase 1 is not switched

Phase 1 runs on stock Ubuntu 20.04.
The basics scripts are verified on 24.04 only.
They are guarded (ssh.socket check, deb822 guard). They should work.
But "should" is not "tested". Phase 2 runs on 22.04. Closer, lower risk.

## Fresh clone

Run this first:

```shell
git submodule update --init LinuxBasics
```

Without it, `basics/` steps fail with a hint message.

## Steps to finish adoption (future merge to main)

1. Test Phase 2 on a real device with this branch.
2. If good: switch Phase 1 entries to `basics/` too.
   Candidates: `check_shell_syntax.sh`, `set_scripts_executable.sh`,
   `cleanup_repositories.sh`, `add_ssh.sh`, `updates_install_and_clean.sh`,
   `fix_dpkg_lock.sh`, `fix_xauthority.sh`.
3. Delete the local duplicates from `install_scripts/scripts/`.
4. Keep `reboot.sh` LOCAL. It is this repo's single reboot authority.
   Never swap it for the basics copy. See `.claude/docs/constraints.md`.
5. Update the dpkg-lock case list in `run_script` if names change.
6. Pull the newest basics before testing:
   `git -C LinuxBasics pull origin main`, then commit the pointer.

## Known caveat

The basics `check_shell_syntax.sh` needs superproject support.
Fixed in basics (uses `--show-superproject-working-tree`).
Make sure the submodule pointer includes that fix before merging.
