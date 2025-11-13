# Project Overview

This project contains scripts for updating Linux and macOS systems.

## Directory Structure

*   `linux/`: Contains the `update.sh` script for updating various Linux distributions.
*   `macos/`: Contains the `update_macos.sh` script for updating macOS systems.

## Scripts

### Linux

The `linux/update.sh` script is a comprehensive update tool for various Linux distributions. It automates the process of updating system packages, Flatpak and Snap applications, cleaning up the system, checking for firmware or distribution upgrades. It also features an enhanced sudo privilege check, enhanced Docker integration, a self-update mechanism, and displays its version with a simple banner.

### macOS

The `macos/update_macos.sh` script is a comprehensive update tool for macOS. It automates the process of updating the operating system (with user confirmation for individual updates and prevention of major OS upgrades), Homebrew and MacPorts packages, cleaning up the system. It also includes a self-update mechanism, displays its version with a simple banner.