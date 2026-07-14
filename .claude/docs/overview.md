# What this repo is

A collection of Bash installer scripts that convert a stock FLSUN V400 Speeder Pad (Ubuntu 20.04, FLSUN's own firmware environment) into a Guilouz-style Klipper/Moonraker/Mainsail/KlipperScreen setup (Ubuntu 22.04). It is not an application with a build step — there is no compiled artifact, package manager, or app server. Everything runs directly on the Speeder Pad over SSH as root.

The scripts wrap and orchestrate several upstream projects (KIAUH, Klipper, Moonraker, Mainsail, Guilouz's `Klipper-Flsun-Speeder-Pad` config repo) rather than reimplementing them.
