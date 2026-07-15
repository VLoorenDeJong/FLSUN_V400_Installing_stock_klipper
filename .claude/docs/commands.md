# Commands

There is no build/lint/test toolchain in the traditional sense. The only checks are:

```shell
# Syntax-check every .sh file in the repo (bash -n / sh -n), excluding .git/.venv/venv
./install_scripts/scripts/check_shell_syntax.sh
```

This is also what CI-equivalent review expects before a PR (see README "Contributing"). Run it after editing any script. It also runs on the device, as the first step of every phase in `start_install.sh`.

Running the installer itself requires a real (or test) FLSUN V400 Speeder Pad and root:

```shell
sudo ./install_scripts/start_install.sh          # interactive menu
sudo ./install_scripts/start_install.sh -d        # same, with bash -x debug output for each sub-script
sudo bash -x install_scripts/scripts/<script>.sh  # debug a single script directly
```

`chmod -R +x .` should be re-run after adding/renaming scripts (README instructs users to do this before every run; it's safe to repeat).

This repo has a git submodule at `.claude/guiderails` (private — holds generic, vendor-neutral conventions shared across multiple projects, not FLSUN-specific). On a fresh clone, run `git submodule update --init` to populate it. Anyone without access to the private `Guiderails` repo will get an empty directory there instead — that's expected and not an error to chase down.
