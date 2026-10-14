# Linux Updater Script (`update.sh`)

This project contains the `update.sh` script, a comprehensive tool for updating various Linux distributions. It automates system package updates, manages Flatpak and Snap applications, and performs system maintenance.

## Key Features

*   **Cross-Distribution Support:** Automatically detects the distribution and uses the appropriate package manager (`apt-get`, `dnf5`, `dnf`, `pacman`, `apk`, `zypper`, `xbps`, `emerge`, `eopkg`, `swupd`, `guix`, `rpm-ostree`, `bootc`, `transactional-update`, `nixos-rebuild`). Full support for immutable and OCI-based OSes (e.g. Fedora Silverblue, Bluefin).
*   **Sudo Privilege Check:** Intelligently handles `sudo` privileges, relaunching itself if necessary.
*   **Comprehensive Updates:** Manages system packages, Flatpak (system and the invoking user's installs), Snap, Homebrew (Linuxbrew, run as the installation's owner), AUR helpers, pipx, Cargo and global npm updates in a single run.
*   **System Maintenance:** Cleans unused packages (including old kernels on Debian/Ubuntu, via `autoremove`) and clears package caches. Optionally clears logs and crash dumps older than 10 days after a prompt.
*   **Reboot Check:** Reports yes, no, or unknown, instead of assuming no reboot is needed when a check is unavailable.
*   **Upgrade Checks:** Notifies about distribution-level upgrades and firmware updates.
*   **System Information:** Displays open ports using `ss`, `lsof`, or `netstat`.
*   **Docker Integration:** Lists running Docker containers and manages their lifecycle during updates.
*   **Self-Update:** Automatically checks for and installs the latest version from the GitHub repository, featuring instant CDN cache-busting and graceful offline connection handling. Updates are offered only when the remote `SCRIPT_VERSION` is newer.
*   **Version Display:** Shows the current script version.
*   **Banner:** Displays a clean, informative startup banner.

## Robustness Improvements (v1.4+)

*   **Non-Interactive Safety:** Interactive prompts (container shutdown, self-update confirmation, sudo relaunch, log cleanup) safely fail open or default appropriately when run in non-TTY environments (e.g., cron jobs).
*   **Docker Container Handling:** Features an interactive menu to stop ALL, SELECTIVELY STOP, or SKIP taking down containers for system upgrades. It provides a dynamic looping menu during the restart phase, allowing you to explicitly dictate the exact boot sequence of interdependent Compose projects and standalone containers.
*   **Docker Compose Awareness (v1.5+):** Intelligently categorizes and displays standalone `docker run` containers versus composed environments on the splash screen, and manages them alongside standalone applications.
*   **Error Reporting (v1.12+):** Every update, restart and cleanup step goes through `finish_step`. Failures are listed in a final summary and the script exits non-zero.
*   **Interactivity Detection (v1.12+):** A single `INTERACTIVE` flag is set by trying to open `/dev/tty`, so piping output (e.g. to `tee`) keeps prompts working. All yes/no prompts go through `ask_yes_no`.
*   **User-Level Tools (v1.12+):** `run_as_user` runs tools as `$SUDO_USER` with their `~/.local/bin` and `~/.cargo/bin` on PATH. User-writable directories are never added to root's PATH.
*   **Compose by Project Name (v1.12+):** Compose projects are stopped and started with `docker compose -p <project> stop|start`, which restarts existing containers instead of recreating them.


# Building and Running

The script is standalone and requires no build process.

## Running the Script

Execute it from your terminal:
```bash
./update.sh
```

To run the script and skip the self-update check, use the `noupdate` argument:
```bash
./update.sh noupdate
```

Or, if not executable:
```bash
bash update.sh
```
The script requires `sudo` privileges for most operations and will prompt for a password if needed.

# Development Conventions

The script is written in `bash` and uses color codes for improved output readability.
