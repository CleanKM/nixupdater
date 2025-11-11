#!/bin/bash

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- ASCII Art ---
echo -e "${CYAN}"
cat << "EOF"
 _   _  ___ _____ _____ ____  _____ ____
| | | ||_ _|_   _| ____|  _ \| ____|  _ \
| | | | | |  | | |  _| | |_) |  _| | |_) |
| |_| | | |  | | | |___|  _ <| |___|  _ <
 \___/ |___| |_| |_____|_| \_\_____|_| \_\
EOF
echo -e "${NC}"
echo -e "${MAGENTA}--- System Update Script ---"${NC}
echo ""

# --- Spinner ---
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# --- Distribution Detection ---
echo -n -e "${BLUE}Detecting distribution...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    DISTRO=$ID
    echo -e "${GREEN}Done! ($OS)${NC}"
else
    echo -e "${RED}Cannot detect Linux distribution.${NC}"
    exit 1
fi

# --- Package Manager Detection ---
case "$DISTRO" in
    "ubuntu" | "debian" | "pop" | "linuxmint" | "zorin" | "elementary" | "raspbian" | "mx" | "kali")
        PACKAGE_MANAGER="apt"
        ;;
    "fedora" | "centos" | "rhel" | "nobara" | "rocky" | "almalinux")
        PACKAGE_MANAGER="dnf"
        ;;
    "arch" | "manjaro" | "endeavouros" | "garuda")
        PACKAGE_MANAGER="pacman"
        ;;
    "alpine")
        PACKAGE_MANAGER="apk"
        ;;
    *)
        echo -e "${YELLOW}Unsupported distribution: '$OS'. Attempting to find a compatible package manager...${NC}"
        if command -v apt &> /dev/null; then
            PACKAGE_MANAGER="apt"
            echo -e "${GREEN}Found 'apt'. Proceeding.${NC}"
        elif command -v dnf &> /dev/null; then
            PACKAGE_MANAGER="dnf"
            echo -e "${GREEN}Found 'dnf'. Proceeding.${NC}"
        elif command -v pacman &> /dev/null; then
            PACKAGE_MANAGER="pacman"
            echo -e "${GREEN}Found 'pacman'. Proceeding.${NC}"
        elif command -v apk &> /dev/null; then
            PACKAGE_MANAGER="apk"
            echo -e "${GREEN}Found 'apk'. Proceeding.${NC}"
        else
            echo -e "${RED}Could not find a supported package manager (apt, dnf, pacman, apk). Exiting.${NC}"
            exit 1
        fi
        ;;
esac
echo -e "${BLUE}Using package manager: ${GREEN}$PACKAGE_MANAGER${NC}"
echo ""

# --- Update Checking ---
echo -n -e "${BLUE}Checking for system updates...${NC}"
(
case "$PACKAGE_MANAGER" in
    "apt")
        sudo apt update >/dev/null 2>&1
        ;;
    "dnf")
        # dnf check-update runs without sudo and is fast
        ;;
    "pacman")
        sudo pacman -Sy >/dev/null 2>&1
        ;;
    "apk")
        sudo apk update >/dev/null 2>&1
        ;;
esac
) & 
spinner $!
echo -e "${GREEN}Done!${NC}"

SYSTEM_UPDATES=$(
case "$PACKAGE_MANAGER" in
    "apt")
        apt list --upgradable 2>/dev/null | tail -n +2
        ;;
    "dnf")
        dnf check-update | tail -n +2
        ;;
    "pacman")
        pacman -Qu
        ;;
    "apk")
        apk list --upgradeable 2>/dev/null | tail -n +1 # apk list --upgradeable includes a header
        ;;
esac
)

FLATPAK_UPDATES=""
if command -v flatpak &> /dev/null; then
    echo -n -e "${BLUE}Checking for Flatpak updates...${NC}"
    FLATPAK_UPDATES=$(flatpak remote-ls --updates) &
    spinner $!
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${YELLOW}Flatpak not found. Skipping Flatpak check.${NC}"
fi

SNAP_UPDATES=""
if command -v snap &> /dev/null; then
    echo -n -e "${BLUE}Checking for Snap updates...${NC}"
    SNAP_UPDATES_RAW=$( (sudo snap refresh --list 2>&1) ) &
    spinner $!
    wait $! # Ensure the command finishes before processing output
    SNAP_UPDATES=$(echo "$SNAP_UPDATES_RAW" | grep -v "All snaps are up to date." | tail -n +2)
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${YELLOW}Snap not found. Skipping Snap check.${NC}"
fi
echo ""

# --- List Updates and Upgrade ---
if [ -z "$SYSTEM_UPDATES" ] && [ -z "$FLATPAK_UPDATES" ] && [ -z "$SNAP_UPDATES" ]; then
    echo -e "${GREEN}=========================${NC}"
    echo -e "${GREEN} Your system is up to date. ${NC}"
    echo -e "${GREEN}=========================${NC}"
fi

# --- Install pv for progress bars if not present ---
if ! command -v pv &> /dev/null; then
    echo -e "${YELLOW}'pv' command not found. Attempting to install for progress bars...${NC}"
    case "$PACKAGE_MANAGER" in
        "apt")
            sudo apt install -y pv
            ;;
        "dnf")
            sudo dnf install -y pv
            ;;
        "pacman")
            sudo pacman -S --noconfirm pv
            ;;
        "apk")
            sudo apk add pv
            ;;
    esac
fi

# Set USE_PV flag for later use
if command -v pv &> /dev/null; then
    USE_PV=true
else
    echo -e "${RED}Failed to install 'pv'. Progress bars will not be displayed.${NC}"
    USE_PV=false
fi

# --- Docker Pre-Update Check ---
DOCKER_CONTAINERS_TO_RESTART=""
if command -v docker &> /dev/null; then
    if echo "$SYSTEM_UPDATES" | grep -q -e "docker" -e "containerd"; then
        echo -e "${YELLOW}Docker-related update found. Stopping running containers...${NC}"
        DOCKER_CONTAINERS_TO_RESTART=$(sudo docker ps -q)
        if [ -n "$DOCKER_CONTAINERS_TO_RESTART" ]; then
            sudo docker stop $DOCKER_CONTAINERS_TO_RESTART
            echo -e "${GREEN}Containers stopped.${NC}"
        else
            echo -e "${GREEN}No running containers to stop.${NC}"
        fi
    fi
fi

# --- Upgrade ---
if [ -n "$SYSTEM_UPDATES" ] || [ -n "$FLATPAK_UPDATES" ] || [ -n "$SNAP_UPDATES" ]; then
    echo -e "${YELLOW}--- Pending Updates ---"${NC}
    if [ -n "$SYSTEM_UPDATES" ]; then
        echo -e "${CYAN}--- System Updates ---"${NC}
        echo "$SYSTEM_UPDATES"
    fi
    if [ -n "$FLATPAK_UPDATES" ]; then
        echo -e "${CYAN}--- Flatpak Updates ---"${NC}
        echo "$FLATPAK_UPDATES"
    fi
    if [ -n "$SNAP_UPDATES" ]; then
        echo -e "${CYAN}--- Snap Updates ---"${NC}
        echo "$SNAP_UPDATES"
    fi
    echo ""
    echo -e "${MAGENTA}Starting automatic upgrade...${NC}"

    # System Upgrade
    if [ -n "$SYSTEM_UPDATES" ]; then
        echo -e "${BLUE}Upgrading system packages...${NC}"
        case "$PACKAGE_MANAGER" in
            "apt")
                if $USE_PV; then
                    (sudo apt upgrade -y 2>&1) | pv -lep -s $(apt list --upgradable 2>/dev/null | wc -l) >/dev/null
                else
                    sudo apt upgrade -y
                fi
                ;;
            "dnf")
                if $USE_PV; then
                     (sudo dnf upgrade -y 2>&1) | pv -lep -s $(dnf check-update | wc -l) >/dev/null
                else
                     sudo dnf upgrade -y
                fi
                ;;
            "pacman")
                if $USE_PV; then
                    (sudo pacman -Syu --noconfirm 2>&1) | pv -lep -s $(pacman -Qu | wc -l) >/dev/null
                else
                    sudo pacman -Syu --noconfirm
                fi
                ;;
            "apk")
                if $USE_PV; then
                    (sudo apk upgrade 2>&1) | pv -lep -s $(apk list --upgradeable 2>/dev/null | wc -l) >/dev/null
                else
                    sudo apk upgrade
                fi
                ;;
        esac
        echo -e "${GREEN}System upgrade complete.${NC}"

        # --- Docker Post-Update Restart ---
        if [ -n "$DOCKER_CONTAINERS_TO_RESTART" ]; then
            echo -e "${BLUE}Restarting previously running Docker containers...${NC}"
            sudo docker start $DOCKER_CONTAINERS_TO_RESTART
            echo -e "${GREEN}Containers restarted.${NC}"
        fi
    fi

    # Flatpak Upgrade
    if [ -n "$FLATPAK_UPDATES" ]; then
        echo -e "${BLUE}Upgrading Flatpak packages...${NC}"
        # pv is not ideal for flatpak's output, so we run it directly.
        flatpak update -y
        echo -e "${GREEN}Flatpak upgrade complete.${NC}"
    fi

    # Snap Upgrade
    if [ -n "$SNAP_UPDATES" ]; then
        echo -e "${BLUE}Upgrading Snap packages...${NC}"
        sudo snap refresh
        echo -e "${GREEN}Snap upgrade complete.${NC}"
    fi
fi

echo ""
echo -e "${MAGENTA}--- Cleaning up system ---${NC}"

# Autoremove unnecessary packages
echo -e "${BLUE}Removing unnecessary packages...${NC}"
case "$PACKAGE_MANAGER" in
    "apt")
        sudo apt autoremove -y
        ;;
    "dnf")
        sudo dnf autoremove -y
        ;;
    "pacman")
        # First, find orphaned packages, then remove them if any exist.
        if [[ -n $(pacman -Qdtq) ]]; then
            sudo pacman -Rns $(pacman -Qdtq) --noconfirm
        else
            echo "No orphaned packages to remove."
        fi
        ;;
    "apk")
        # apk does not have a direct 'autoremove' equivalent like apt/dnf.
        # This command removes uninstalled and unreferenced packages.
        if command -v apk &> /dev/null && command -v apk stats &> /dev/null; then
            UNREFERENCED_PKGS=$(apk stats --uninstalled --unreferenced)
            if [ -n "$UNREFERENCED_PKGS" ]; then
                sudo apk del --purge $UNREFERENCED_PKGS
            else
                echo "No unreferenced packages to remove."
            fi
        else
            echo "apk stats not found. Cannot remove unreferenced packages."
        fi
        ;;
esac
echo -e "${GREEN}Done!${NC}"

# Clean package cache
echo -e "${BLUE}Clearing package cache...${NC}"
case "$PACKAGE_MANAGER" in
    "apt")
        sudo apt clean
        ;;
    "dnf")
        sudo dnf clean all
        ;;
    "pacman")
        sudo pacman -Scc --noconfirm
        ;;
    "apk")
        sudo apk cache clean
        ;;
esac
echo -e "${GREEN}Done!${NC}"

echo ""
echo -e "${MAGENTA}--- Distribution Upgrade Check ---${NC}"
case "$PACKAGE_MANAGER" in
    "apt")
        # Flag to see if we found an upgrade
        UPGRADE_FOUND=false
        # First, try the Ubuntu/Ubuntu-like method silently
        if command -v do-release-upgrade &> /dev/null; then
            echo -e "${BLUE}Checking for a new distribution release (do-release-upgrade)...${NC}"
            UPGRADE_CHECK=$(sudo do-release-upgrade -c 2>&1)
            if echo "$UPGRADE_CHECK" | grep -q "New release"; then
                RELEASE_INFO=$(echo "$UPGRADE_CHECK" | grep "New release")
                echo -e "${YELLOW}A new distribution release is available: $RELEASE_INFO${NC}"
                echo -e "${YELLOW}To upgrade, run the following command:${NC}"
                echo -e "${CYAN}sudo do-release-upgrade${NC}"
                UPGRADE_FOUND=true
            fi
        fi
        
        # If the first method didn't find anything, try the Debian/dist-upgrade method
        if [ "$UPGRADE_FOUND" = false ]; then
            echo -e "${BLUE}Checking for major package changes (apt dist-upgrade)...${NC}"
            DIST_UPGRADE_CHECK=$(sudo apt -s dist-upgrade 2>&1)
            
            if echo "$DIST_UPGRADE_CHECK" | grep -q "upgraded, .* newly installed, .* to remove"; then
                SUMMARY=$(echo "$DIST_UPGRADE_CHECK" | grep "upgraded, .* newly installed, .* to remove")
                # Check if the summary line actually contains non-zero numbers
                if ! echo "$SUMMARY" | grep -q "0 upgraded, 0 newly installed, 0 to remove"; then
                    echo -e "${YELLOW}A distribution upgrade or major package change may be available.${NC}"
                    echo -e "${YELLOW}Summary: $SUMMARY${NC}"
                    echo -e "${YELLOW}To apply these changes, review them carefully and then run:${NC}"
                    echo -e "${CYAN}sudo apt full-upgrade${NC}"
                    UPGRADE_FOUND=true
                fi
            fi
        fi

        # If still no upgrade was found after all checks
        if [ "$UPGRADE_FOUND" = false ]; then
            echo -e "${GREEN}Your distribution is up to date. No new release or major changes found.${NC}"
        fi
        ;;
    "dnf")
        echo -e "${BLUE}For Fedora-based systems, distribution upgrades are done using the 'dnf-plugin-system-upgrade' plugin.${NC}"
        echo -e "${BLUE}To upgrade, you would typically run a command like:${NC}"
        echo -e "${CYAN}sudo dnf system-upgrade download --releasever=<version>${NC}"
        echo -e "${BLUE}Please consult your distribution's official documentation for the correct version number and instructions.${NC}"
        ;;
    "pacman")
        echo -e "${BLUE}Your system uses a rolling release model.${NC}"
        echo -e "${BLUE}Regular updates using 'sudo pacman -Syu' keep your system on the latest version.${NC}"
        echo -e "${GREEN}Your distribution is continuously up to date.${NC}"
        ;;
    "apk")
        echo -e "${BLUE}Your system uses a rolling release model.${NC}"
        echo -e "${BLUE}Regular updates using 'sudo apk upgrade' keep your system on the latest version.${NC}"
        echo -e "${BLUE}Major version upgrades for Alpine Linux typically involve manual changes to /etc/apk/repositories.${NC}"
        echo -e "${GREEN}Your distribution is continuously up to date.${NC}"
        ;;
    *)
        echo -e "${YELLOW}Could not determine the distribution upgrade method for '$OS'.${NC}"
        echo -e "${YELLOW}Please consult your distribution's official documentation.${NC}"
        ;;
esac

echo ""
echo -e "${MAGENTA}--- Clearing Old Logs ---${NC}"
if command -v journalctl &> /dev/null; then
    echo -e "${BLUE}Using journalctl to clear logs older than 10 days...${NC}"
    sudo journalctl --vacuum-time=10d
else
    echo -e "${YELLOW}Warning: 'journalctl' not found. Using 'find' to clear logs from /var/log.${NC}"
    echo -e "${BLUE}Clearing .log and .gz files older than 10 days from /var/log...${NC}"
    sudo find /var/log -type f -name "*.log" -mtime +10 -delete
    sudo find /var/log -type f -name "*.gz" -mtime +10 -delete
fi
echo -e "${GREEN}Old logs cleared.${NC}"

echo ""
echo -e "${MAGENTA}--- Firmware Update Check ---${NC}"
if command -v fwupdmgr &> /dev/null; then
    echo -n -e "${BLUE}Refreshing firmware metadata...${NC}"
    (sudo fwupdmgr refresh --force) >/dev/null 2>&1 &
    spinner $!
    echo -e "${GREEN}Done!${NC}"
    
    echo -e "${BLUE}Checking for firmware updates...${NC}"
    FIRMWARE_UPDATES=$(sudo fwupdmgr get-updates 2>&1)
    
    if echo "$FIRMWARE_UPDATES" | grep -q "No updatable devices"; then
        echo -e "${GREEN}No firmware updates available.${NC}"
    else
        echo -e "${YELLOW}Firmware updates available:${NC}"
        echo -e "${CYAN}$FIRMWARE_UPDATES${NC}"
        echo -e "${YELLOW}To apply these updates, run 'sudo fwupdmgr update'.${NC}"
    fi
else
    echo -e "${YELLOW}fwupdmgr not found. Skipping firmware update check.${NC}"
fi

# --- Open Ports on System ---
echo ""
echo -e "${MAGENTA}--- Open Ports on System ---${NC}"

# Check for lsof and install if not present
if ! command -v lsof &> /dev/null; then
    echo -e "${YELLOW}'lsof' command not found. Attempting to install...${NC}"
    case "$PACKAGE_MANAGER" in
        "apt")
            sudo apt install -y lsof
            ;;
        "dnf")
            sudo dnf install -y lsof
            ;;
        "pacman")
            sudo pacman -S --noconfirm lsof
            ;;
    esac
fi

# Now, list the ports if lsof is available
if command -v lsof &> /dev/null; then
    echo -e "${BLUE}Listing listening TCP and UDP ports (PID/Command/Address:Port)...${NC}"
    sudo lsof -i -P -n | grep LISTEN
else
    echo -e "${RED}Error: 'lsof' could not be installed. Cannot display open ports.${NC}"
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN} All updates completed successfully! ${NC}"
echo -e "${GREEN}=====================================${NC}"
echo -e "${CYAN}"
cat << "EOF"
  _   _   _   _   _   _   _   _   _
 / \ / \ / \ / \ / \ / \ / \ / \ / \
( C | o | m | p | l | e | t | e | d )
 \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/
EOF
echo -e "${NC}"
exit 0