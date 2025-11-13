# Project Overview

This project contains a single shell script, `update_macos.sh`, designed to be a comprehensive update tool for macOS. The script automates the process of updating the operating system, Homebrew and MacPorts packages, and cleaning up the system.

## Key Features

*   **macOS System Updates:** Checks for available macOS operating system updates. It prevents automatic installation of major OS upgrades and allows for individual confirmation of each recommended update.
*   **Package Manager Support:** Supports both Homebrew and MacPorts for package updates.
*   **Comprehensive Updates:** Handles system updates, Homebrew formulae and casks, and MacPorts packages.
*   **System Maintenance:** Cleans up unused packages and clears package caches for both Homebrew and MacPorts.
*   **System Information:** Provides information on open ports, using `lsof` or `netstat` as fallbacks.
*   **Automatic Self-Update:** The script can check for and offer to install its own latest version from the GitHub repository.
*   **Version Display:** Shows the script's current version at startup.
*   **Simple Banner:** Displays a clean, informative banner instead of ASCII art.

# Building and Running

This is a standalone shell script and does not require a build process.

## Running the script

To run the script, you can execute it from your terminal:

```bash
./update_macos.sh
```

Or, if it's not executable:

```bash
bash update_macos.sh
```

The script requires `sudo` privileges for many of its operations and will prompt for a password if not run as root.

# Development Conventions

The script is written in `bash` and follows common shell scripting practices. It uses color codes for better readability of the output.