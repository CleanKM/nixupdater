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
