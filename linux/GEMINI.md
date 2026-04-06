# Linux Updater Script (`update.sh`)

This project contains the `update.sh` script, a comprehensive tool for updating various Linux distributions. It automates system package updates, manages Flatpak and Snap applications, and performs system maintenance.

## Key Features

*   **Cross-Distribution Support:** Automatically detects the distribution and uses the appropriate package manager (`apt`, `dnf`, `pacman`, `apk`).
*   **Sudo Privilege Check:** Intelligently handles `sudo` privileges, relaunching itself if necessary.
*   **Comprehensive Updates:** Manages system packages, Flatpak, and Snap updates in a single run.
*   **System Maintenance:** Cleans unused packages and clears package caches.
*   **Upgrade Checks:** Notifies about distribution-level upgrades and firmware updates.
*   **System Information:** Displays open ports using `lsof`, `ss`, or `netstat`.
*   **Docker Integration:** Lists running Docker containers and manages their lifecycle during updates.
*   **Self-Update:** Automatically checks for and installs the latest version from the GitHub repository.
*   **Version Display:** Shows the current script version.
*   **Banner:** Displays a clean, informative startup banner.
## Robustness Improvements (v1.4+)

*   **Non-Interactive Safety:** Interactive prompts (container shutdown, self-update confirmation, sudo relaunch) safely fail open or default appropriately when run in non-TTY environments (e.g., cron jobs).
*   **Dependency Installation Feedback:** Improved success/failure reporting when dynamically installing required utilities like `lsof`.
*   **Docker Container Handling:** Prompts the user before taking down containers for system upgrades. Correctly stops and restarts multiple containers during Docker-related updates by enforcing a safe restart order (Compose projects first).
*   **Docker Compose Awareness (v1.5+):** Intelligently categorizes and displays standalone `docker run` containers versus composed environments on the splash screen, and natively leverages `.yml` lifecycle rules (`docker compose up -d`) to manage them.


# Building and Running

The script is standalone and requires no build process.

## Running the Script

Execute it from your terminal:
```bash
./update.sh
```
Or, if not executable:
```bash
bash update.sh
```
The script requires `sudo` privileges for most operations and will prompt for a password if needed.

# Development Conventions

The script is written in `bash` and uses color codes for improved output readability.
