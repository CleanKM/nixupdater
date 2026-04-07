# Linux Updater Script (`update.sh`)

This project contains the `update.sh` script, a comprehensive tool for updating various Linux distributions. It automates system package updates, manages Flatpak and Snap applications, and performs system maintenance.

## Key Features

*   **Cross-Distribution Support:** Automatically detects the distribution and uses the appropriate package manager (`apt`, `dnf`, `pacman`, `apk`, `rpm-ostree`, `bootc`). Full support for immutable and OCI-based OSes (e.g. Fedora Silverblue, Bluefin).
*   **Sudo Privilege Check:** Intelligently handles `sudo` privileges, relaunching itself if necessary.
*   **Comprehensive Updates:** Manages system packages, Flatpak, and Snap updates in a single run.
*   **System Maintenance:** Cleans unused packages and clears package caches.
*   **Upgrade Checks:** Notifies about distribution-level upgrades and firmware updates.
*   **System Information:** Displays open ports using `lsof`, `ss`, or `netstat`.
*   **Docker Integration:** Lists running Docker containers and manages their lifecycle during updates.
*   **Self-Update:** Automatically checks for and installs the latest version from the GitHub repository, featuring instant CDN cache-busting and graceful offline connection handling.
*   **Version Display:** Shows the current script version.
*   **Banner:** Displays a clean, informative startup banner.
## Robustness Improvements (v1.4+)

*   **Non-Interactive Safety:** Interactive prompts (container shutdown, self-update confirmation, sudo relaunch) safely fail open or default appropriately when run in non-TTY environments (e.g., cron jobs).
*   **Dependency Installation Feedback:** Improved success/failure reporting when dynamically installing required utilities like `lsof`.
*   **Docker Container Handling:** Features an interactive menu to stop ALL, SELECTIVELY STOP, or SKIP taking down containers for system upgrades. It provides a dynamic looping menu during the restart phase, allowing you to explicitly dictate the exact boot sequence of interdependent Compose projects and standalone containers.
*   **Docker Compose Awareness (v1.5+):** Intelligently categorizes and displays standalone `docker run` containers versus composed environments on the splash screen, and natively leverages `.yml` lifecycle rules (`docker compose up -d`) to manage them alongside standalone applications.


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
