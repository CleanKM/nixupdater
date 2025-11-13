# Linux and macOS System Updater Scripts

This project provides a set of shell scripts designed to automate and simplify the process of updating and maintaining both Linux and macOS systems. The goal is to offer a comprehensive solution for keeping your operating system, package managers, and applications up-to-date, along with performing routine cleanup tasks.

## Project Structure

The project is organized into two main directories, each containing a dedicated update script for its respective operating system:

*   `linux/`: Contains `update.sh`, a script tailored for various Linux distributions.
*   `macos/`: Contains `update_macos.sh`, a script specifically designed for macOS systems.

## Scripts Overview

### `linux/update.sh`

This script is a robust update tool for Linux distributions. It intelligently detects your distribution and uses the appropriate package manager to perform updates.

**Key Features:**

*   **Cross-Distribution Support:** Automatically identifies the Linux distribution (e.g., Ubuntu, Fedora, Arch, Alpine) and utilizes `apt`, `dnf`, `pacman`, or `apk` accordingly.
*   **Comprehensive Updates:** Manages updates for system packages, Flatpak applications, and Snap packages.
*   **System Maintenance:** Includes routines for removing unnecessary packages (`autoremove`) and clearing package caches. For Alpine Linux, it notes that a direct 'autoremove' equivalent is not available.
*   **Debian/Ubuntu Health Checks:** For Debian-based systems, it checks for held packages and verifies package integrity using `debsums` (will prompt to install if missing).
*   **Old Kernel Cleanup:** On Debian-based systems, it identifies and offers to remove old, unused kernels to free up disk space.
*   **Reboot Check:** Checks if a system reboot is required after updates on Debian/Ubuntu and Fedora-based systems.
*   **Upgrade Checks:** Notifies about available distribution-level upgrades and firmware updates (via `fwupdmgr`).
*   **Log Cleanup:** Clears old system logs to free up space.
*   **Open Ports:** Lists currently open TCP and UDP ports on the system, using `lsof`, `ss`, or `netstat` as fallbacks.
*   **Docker Integration:** Stops Docker containers before system updates if Docker-related packages are being updated, and restarts them afterward.
*   **Progress Bars & Dependency Handling:** Attempts to install `pv` (Pipe Viewer) for progress bars and `lsof` for listing open ports, with improved error handling for installation failures.

**Usage:**

To run the Linux update script:

```bash
cd linux/
./update.sh
```

Or, if it's not executable:

```bash
cd linux/
bash update.sh
```

The script requires `sudo` privileges for many operations and will prompt for a password if not run as root.

### `macos/update_macos.sh`

This script is designed to keep your macOS system and its installed software up-to-date. It integrates with macOS's built-in update mechanisms and popular package managers.

**Key Features:**

*   **macOS System Updates:** Checks for and optionally installs macOS operating system updates using `softwareupdate`.
*   **Homebrew Integration:** Manages updates for Homebrew formulae and casks.
*   **App Store Integration:** Checks for and installs updates for Mac App Store applications using `mas-cli` (will prompt to install if missing).
*   **MacPorts Integration:** Manages updates for MacPorts packages.
*   **System Maintenance:** Cleans up Homebrew and MacPorts caches and removes inactive packages.
*   **Log Cleanup:** Clears old log files from common macOS log directories.
*   **Open Ports:** Lists currently open TCP and UDP ports on the system, using `lsof` or `netstat` as fallbacks.
*   **Reboot Check:** Notifies you if a restart is required after installing macOS system updates.
*   **Robust Spinner:** Includes a more robust spinner function for better user experience during long operations.

**Usage:**

To run the macOS update script:

```bash
cd macos/
./update_macos.sh
```

Or, if it's not executable:

```bash
cd macos/
bash update_macos.sh
```

The script requires `sudo` privileges for some operations (like `softwareupdate` and MacPorts updates) and will prompt for a password if not run as root. It will also prompt you before installing macOS system updates.

## Contributing

Feel free to open issues or submit pull requests.

## License

This project is licensed under the MIT License.
