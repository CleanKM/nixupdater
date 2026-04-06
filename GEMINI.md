# Project Overview

This project provides scripts to streamline system updates for both Linux and macOS.

## Directory Structure

*   `linux/`: Contains the `update.sh` script for Linux distributions.
*   `macos/`: Contains the `update_macos.sh` script for macOS systems.

## Scripts

### Linux (`linux/update.sh`)

A comprehensive update tool for various Linux distributions. It automates updates for system packages, Flatpak, and Snap applications. Key features include an enhanced sudo check, robust Docker and Docker Compose integration with targeted container management, a self-update mechanism built for interactive and headless flows, and safe system cleanup.

### macOS (`macos/update_macos.sh`)

A dedicated update tool for macOS. It handles OS updates (with confirmation to prevent major upgrades), Homebrew and MacPorts packages, and system cleanup. It also includes a self-update mechanism.
