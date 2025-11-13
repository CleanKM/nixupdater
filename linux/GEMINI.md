# Project Overview

This project contains a single shell script, `update.sh`, designed to be a comprehensive update tool for various Linux distributions. The script automates the process of updating system packages, Flatpak and Snap applications, cleaning up the system, and checking for firmware or distribution upgrades.

## Key Features

*   **Cross-Distribution Support:** Automatically detects the underlying Linux distribution and uses the appropriate package manager (`apt`, `dnf`, `pacman`, `apk`).
*   **Comprehensive Updates:** Handles system packages, Flatpak, and Snap updates.
*   **System Maintenance:** Cleans up unused packages and clears package caches. For Alpine Linux, it notes that a direct 'autoremove' equivalent is not available.
*   **Upgrade Checks:** Looks for distribution-level upgrades and firmware updates.
*   **System Information:** Provides information on open ports, using `lsof`, `ss`, or `netstat` as fallbacks.
*   **Docker Integration:** If Docker is installed and a Docker-related package is being updated, the script will stop running containers before the update and restart them afterward.
*   **Automatic Self-Update:** The script can check for and offer to install its own latest version from the GitHub repository.

# Building and Running

This is a standalone shell script and does not require a build process.

## Running the script

To run the script, you can execute it from your terminal:

```bash
./update.sh
```

Or, if it's not executable:

```bash
bash update.sh
```

The script requires `sudo` privileges for many of its operations and will prompt for a password if not run as root.

# Development Conventions

The script is written in `bash` and follows common shell scripting practices. It uses color codes for better readability of the output.