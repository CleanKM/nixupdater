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

*   **Cross-Distribution Support:** Automatically identifies the Linux distribution (including Debian, Ubuntu, Arch, Alpine, Fedora, openSUSE MicroOS, NixOS, and atomic OSTree systems like Fedora Silverblue) and utilizes the appropriate package manager (`apt`, `dnf`, `pacman`, `apk`, `rpm-ostree`, `bootc`, `transactional-update`, or `nixos-rebuild`).
*   **Enhanced Sudo Privilege Check & Helper:** Intelligently checks for sudo/root privileges, offering to relaunch with sudo if the user is in the sudo/wheel group.
*   **Version Display:** Shows the script's current version at startup.
*   **Simple Banner:** Displays a clean, informative banner instead of ASCII art.
*   **Robust Non-Interactive Execution:** All prompts (including self-updates, sudo relaunch, container restarts, and old kernel cleanup) are TTY-guarded to safely bypass or fail-safe in headless automated/cron environments.
*   **Comprehensive Updates:** Manages updates for system packages, Flatpak applications, Snap packages, and Homebrew (Linuxbrew) packages in a single execution.
*   **Sudo-Safe Homebrew (Linuxbrew) Execution:** Automatically demotes Homebrew operations back to the original non-root user account when the script is run elevated under `sudo`, preventing permission locks.
*   **System Maintenance:** Includes routines for removing unnecessary packages (`autoremove`) safely and clearing package caches conservatively across all supported package managers.
*   **Debian/Ubuntu Health Checks:** For Debian-based systems, it checks for held packages.
*   **Old Kernel Cleanup:** On Debian-based systems, it identifies and offers to remove old, unused kernels to free up disk space.
*   **Intelligent Reboot Check:** Evaluates system reboot triggers dynamically, including Debian/Ubuntu files, `dnf-utils` reboot checks, pending OSTree deployments, transactional snapshot states, and rolling-release kernel module mismatch detectors (checks if active kernel module folder was deleted).
*   **Upgrade Checks:** Notifies about available distribution-level upgrades and firmware updates (via `fwupdmgr`).
*   **Log Cleanup:** Clears old system logs to free up space.
*   **Open Ports:** Lists currently open TCP and UDP ports on the system using `lsof`, `ss`, or `netstat` as fallbacks, utilizing advanced filtering to show both listening TCP sockets and open UDP ports accurately.
*   **Docker Integration:** Stops Docker containers before system upgrades if Docker-related packages (checked across system packages, snaps, and Homebrew) are being updated, and restarts them afterward.
*   **Dependency Handling:** Safely attempts to install `lsof` for listing open ports, with improved error handling for installation failures.
*   **Advanced Docker & Compose Integration:** Categorizes running containers into Standalone and Compose projects at startup. If Docker-related updates are required, it provides an interactive selection menu to choose exactly which containers to safely spin down. Post-update, it supplies an ordered-restart menu so you can boot interdependent Compose networks and standalone databases in a precise operational sequence. Validates states specifically for targeted containers.

**Usage:**

To quickly download and install the latest Linux update script:

```bash
curl -o update.sh https://raw.githubusercontent.com/CleanKM/nixupdater/main/linux/update.sh && chmod +x update.sh
```

To run the Linux update script:

```bash
./update.sh
```

To run the script and skip the self-update check, use the `noupdate` argument:

```bash
./update.sh noupdate
```

Or, if it's not executable:

```bash
bash update.sh
```

The script requires `sudo` privileges for many operations and will prompt for a password if not run as root.

### `macos/update_macos.sh`

This script is designed to keep your macOS system and its installed software up-to-date. It integrates with macOS's built-in update mechanisms and popular package managers.

**Key Features:**

*   **macOS System Updates:** Checks for available macOS operating system updates. It prevents automatic installation of major OS upgrades and allows for individual confirmation of each recommended update.
*   **Homebrew Integration:** Manages updates for Homebrew formulae and casks, running them elevated safely under the original user session.
*   **App Store Integration:** Checks for and installs updates for Mac App Store applications using `mas-cli` (will prompt to install if missing).
*   **MacPorts Integration:** Manages updates for MacPorts packages.
*   **Sudo-Safe Privilege Demotion Wrappers:** Automatically demotes Homebrew and App Store CLI (`mas`) actions back to the original non-root user (`$SUDO_USER`) when the script runs elevated under `sudo`, preventing permission errors and session profile locks.
*   **System Maintenance:** Cleans up Homebrew and MacPorts caches and removes inactive packages.
*   **Log Cleanup:** Clears old log files from common macOS log directories.
*   **Open Ports:** Lists currently open TCP and UDP ports on the system using `lsof` or `netstat`, utilizing advanced filtering to list both listening TCP sockets and open UDP ports accurately.
*   **Reboot Check:** Notifies you if a restart is required after installing macOS system updates.
*   **Robust Non-Interactive Execution:** Safe integration with headless and pipelined scenarios across all prompts (including self-update confirmations and system update confirmations).
*   **Automatic Self-Update:** The script can check for and offer to install its own latest version from the GitHub repository. Built with instant CDN cache-busting logic, graceful offline network fallbacks, and single-pass relaunch optimization to prevent redundant network checks during process handoffs and sudo elevations.
*   **Version Display:** Shows the script's current version at startup.
*   **Simple Banner:** Displays a clean, informative banner instead of ASCII art.

**Usage:**

To quickly download and install the latest macOS update script:

```bash
curl -o update_macos.sh https://raw.githubusercontent.com/CleanKM/nixupdater/main/macos/update_macos.sh && chmod +x update_macos.sh
```

To run the macOS update script:

```bash
./update_macos.sh
```

To run the script and skip the self-update check, use the `noupdate` argument:

```bash
./update_macos.sh noupdate
```

Or, if it's not executable:

```bash
bash update_macos.sh
```

The script requires `sudo` privileges for some operations (like `softwareupdate` and MacPorts updates) and will prompt for a password if not run as root. It will also prompt you before installing macOS system updates.

## Contributing

Feel free to open issues or submit pull requests.

## License

This project is licensed under the MIT License.
