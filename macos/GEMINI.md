# macOS Updater Script (`update_macos.sh`)

This project contains the `update_macos.sh` script, a tool for automating updates on macOS. It handles operating system updates, manages Homebrew and MacPorts packages, and performs system cleanup.

## Key Features

*   **macOS System Updates:** Checks for macOS updates, with individual confirmation to prevent major OS upgrades.
*   **Package Manager Support:** Supports both Homebrew and MacPorts.
*   **Comprehensive Updates:** Handles system updates, Homebrew (formulae and casks), and MacPorts packages.
*   **System Maintenance:** Cleans up unused packages and clears caches for Homebrew and MacPorts.
*   **System Information:** Displays open ports using `lsof` or `netstat`.
*   **Self-Update:** Automatically checks for and installs the latest version from the GitHub repository.
*   **Version Display:** Shows the current script version.
*   **Banner:** Displays a clean, informative startup banner.

# Building and Running

The script is standalone and requires no build process.

## Running the Script

Execute it from your terminal:
```bash
./update_macos.sh
```
Or, if not executable:
```bash
bash update_macos.sh
```
The script requires `sudo` privileges for many operations and will prompt for a password if needed.

# Development Conventions

The script is written in `bash` and uses color codes for improved output readability.
