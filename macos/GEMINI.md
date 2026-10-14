# macOS Updater Script (`update_macos.sh`)

This project contains the `update_macos.sh` script, a tool for automating updates on macOS. It handles operating system updates, manages Homebrew, MacPorts, and Mac App Store packages, and performs system cleanup.

## Key Features

*   **macOS System Updates:** Checks for macOS updates, with individual confirmation to prevent major OS upgrades.
*   **Package Manager Support:** Supports Homebrew, MacPorts, and the Mac App Store (via `mas`, offering to install it if missing).
*   **Comprehensive Updates:** Handles system updates, Homebrew (formulae and casks, optional `--greedy`), App Store apps, and MacPorts packages.
*   **System Maintenance:** Cleans up unused packages and clears caches for Homebrew and MacPorts, offers Xcode DerivedData/simulator cleanup, thins Time Machine snapshots when disk space is low, runs `periodic`, and flushes the DNS cache. Log cleanup is a prompt.
*   **Reboot Check:** Reports when an installed macOS update requires a restart.
*   **Failure Summary:** Failed steps are listed at the end and the script exits non-zero.
*   **System Information:** Displays open ports using `lsof` or `netstat`.
*   **Self-Update:** Automatically checks for and installs the latest version from the GitHub repository, featuring instant CDN cache-busting and graceful offline connection handling. Updates are offered only when the remote `SCRIPT_VERSION` is newer.
*   **Version Display:** Shows the current script version.
*   **Banner:** Displays a clean, informative startup banner.

# Building and Running

The script is standalone and requires no build process.

## Running the Script

Execute it from your terminal:
```bash
./update_macos.sh
```

To run the script and skip the self-update check, use the `noupdate` argument:
```bash
./update_macos.sh noupdate
```

Or, if not executable:
```bash
bash update_macos.sh
```
The script requires `sudo` privileges for many operations and will prompt for a password if needed.

# Development Conventions

The script is written in `bash` and uses color codes for improved output readability.

It must run on the bash 3.2 that ships with macOS: no associative arrays (`declare -A`), `mapfile`, `${var,,}`, or GNU-only flags such as `chmod --reference` or `sort -V` (use BSD `stat -f`, and the pure-bash `version_gt`). Feed `while read` loops that set variables from a process substitution, not a pipe, or the variables are lost.

Prompts go through `ask_yes_no` (which reads `/dev/tty` and uses the default when non-interactive); step results go through `finish_step`.
