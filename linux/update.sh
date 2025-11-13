#!/bin/bash

# Function to get SHA256 checksum (cross-platform)
get_sha256() {
    if command -v sha256sum &> /dev/null; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "" # Indicate failure
    fi
}

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_VERSION="1.2"

# --- Self-Update Check ---
GITHUB_RAW_URL="https://raw.githubusercontent.com/CleanKM/nixupdater/main/linux/update.sh"
SCRIPT_PATH="$(readlink -f "$0")" # Get absolute path of the current script
TEMP_SCRIPT_PATH=$(mktemp)

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Warning: 'curl' not found. Cannot check for script updates.${NC}"
else
    # Download remote script
    if ! curl -s "$GITHUB_RAW_URL" -o "$TEMP_SCRIPT_PATH"; then
        echo -e "${RED}Error: Failed to download remote script for update check. Skipping self-update.${NC}"
        rm -f "$TEMP_SCRIPT_PATH"
    else
        LOCAL_CHECKSUM=$(get_sha256 "$SCRIPT_PATH")
        REMOTE_CHECKSUM=$(get_sha256 "$TEMP_SCRIPT_PATH")

        if [ -z "$LOCAL_CHECKSUM" ] || [ -z "$REMOTE_CHECKSUM" ]; then
            echo -e "${RED}Error: Checksum utility not found or failed. Skipping self-update.${NC}"
            rm -f "$TEMP_SCRIPT_PATH"
        elif [ "$LOCAL_CHECKSUM" != "$REMOTE_CHECKSUM" ]; then
            echo -e "${YELLOW}A new version of the script is available!${NC}"
            echo -e "${YELLOW}Do you want to update to the latest version? (y/n)${NC}"
            read -r response < /dev/tty
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                echo -e "${BLUE}Updating script...${NC}"
                if mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH"; then
                    chmod +x "$SCRIPT_PATH"
                    echo -e "${GREEN}Script updated successfully. Relaunching...${NC}"
                    exec "$SCRIPT_PATH" "$@" # Relaunch the updated script
                else
                    echo -e "${RED}Error: Failed to replace the script. Please update manually.${NC}"
                    rm -f "$TEMP_SCRIPT_PATH"
                fi
            else
                echo -e "${YELLOW}Skipping script update.${NC}"
                rm -f "$TEMP_SCRIPT_PATH"
            fi
        else
            echo -e "${GREEN}Script is already up to date.${NC}"
            rm -f "$TEMP_SCRIPT_PATH"
        fi
    fi
fi

# --- Sudo check and prompt ---
SUDO=''
if [ "$EUID" -ne 0 ]; then
    # Not running as root
    echo -e "${BLUE}This script requires sudo privileges to run.${NC}"

    if groups "$USER" | grep -q '\bsudo\b'; then
        # User is in the sudo group, offer to relaunch
        echo -e "${YELLOW}You are in the 'sudo' group. Do you want to relaunch this script with sudo? (y/n)${NC}"
        read -r response < /dev/tty # Ensure read from tty
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            echo -e "${BLUE}Relaunching with sudo...${NC}"
            exec sudo "$0" "$@" # Relaunch the script with sudo
        else
            echo -e "${RED}Sudo privileges declined. Exiting.${NC}"
            exit 1
        fi
    else
        # User is not in the sudo group
        echo -e "${RED}You are not currently root or in the 'sudo' group. Exiting.${NC}"
        exit 1
    fi
fi

# If we reach here, the script is either already running as root,
# or it was successfully relaunched with sudo.
# In either case, $EUID should now be 0.

if [ "$EUID" -eq 0 ]; then
    SUDO='sudo' # Set SUDO for consistency, even if already root
    # Verify sudo access (this will prompt for password if needed and not already cached)
    if ! sudo -v; then
        echo -e "${RED}Failed to obtain sudo privileges. Exiting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Sudo privileges obtained.${NC}"
    # Keep-alive: update existing sudo time stamp if set, otherwise do nothing.
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
else
    # This case should ideally not be reached if the logic above is correct.
    # It means $EUID is not 0, but we didn't exit or relaunch.
    echo -e "${RED}Unexpected state: Script is not running as root. Exiting.${NC}"
    exit 1
fi

# --- Script Banner ---
echo -e "${CYAN}------------------------------------------${NC}"
echo -e "${CYAN}  Linux System Update Script - v${SCRIPT_VERSION}  ${NC}"
echo -e "${CYAN}------------------------------------------${NC}"
echo ""

# --- Docker Container Status ---
if command -v docker &> /dev/null; then
    RUNNING_DOCKER_CONTAINERS=$($SUDO docker ps --format "{{.Names}} ({{.ID}})" 2>/dev/null)
    if [ -n "$RUNNING_DOCKER_CONTAINERS" ]; then
        echo -e "${MAGENTA}--- Running Docker Containers ---${NC}"
        echo -e "${CYAN}The following Docker containers are currently running:${NC}"
        echo -e "${CYAN}$RUNNING_DOCKER_CONTAINERS${NC}"
        echo ""
    fi
fi

# --- Spinner ---
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p "$pid" > /dev/null; do
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

# --- Debian/Ubuntu Specific Checks ---
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    echo -e "${MAGENTA}--- Debian/Ubuntu Specific Checks ---${NC}"

    # Check for held packages
    echo -n -e "${BLUE}Checking for held packages...${NC}"
    HELD_PACKAGES=$(apt-mark showhold 2>/dev/null)
    if [ -n "$HELD_PACKAGES" ]; then
        echo -e "${YELLOW}Found held packages!${NC}"
        echo -e "${CYAN}$HELD_PACKAGES${NC}"
        echo -e "${YELLOW}These packages will NOT be upgraded.${NC}"
    else
        echo -e "${GREEN}Done! No held packages found.${NC}"
    fi

    echo ""
fi

# --- Update Checking ---
echo -n -e "${BLUE}Checking for system updates...${NC}"
(
case "$PACKAGE_MANAGER" in
    "apt")
        $SUDO apt update >/dev/null 2>&1
        ;;
    "dnf")
        # dnf check-update runs without sudo and is fast
        ;;
    "pacman")
        $SUDO pacman -Sy >/dev/null 2>&1
        ;;
    "apk")
        $SUDO apk update >/dev/null 2>&1
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
    FLATPAK_UPDATES=$(flatpak remote-ls --updates)
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${YELLOW}Flatpak not found. Skipping Flatpak check.${NC}"
fi

SNAP_UPDATES=""
if command -v snap &> /dev/null; then
    echo -n -e "${BLUE}Checking for Snap updates...${NC}"
    SNAP_OUTPUT_FILE=$(mktemp)
    ( $SUDO snap refresh --list > "$SNAP_OUTPUT_FILE" 2>&1 ) &
    SNAP_PID=$!
    spinner $SNAP_PID
    wait $SNAP_PID
    SNAP_UPDATES_RAW=$(cat "$SNAP_OUTPUT_FILE")
    rm "$SNAP_OUTPUT_FILE"
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
            $SUDO apt install -y pv
            ;;
        "dnf")
            $SUDO dnf install -y pv
            ;;
        "pacman")
            $SUDO pacman -S --noconfirm pv
            ;;
        "apk")
            $SUDO apk add pv
            ;;
    esac
    # Verify pv installation
    if ! command -v pv &> /dev/null; then
        echo -e "${RED}Failed to install 'pv'. Progress bars will not be displayed.${NC}"
    fi
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
        echo -e "${YELLOW}Docker-related update found.${NC}"
        RUNNING_CONTAINER_IDS=$($SUDO docker ps -q)
        if [ -n "$RUNNING_CONTAINER_IDS" ]; then
            echo -e "${BLUE}Stopping the following Docker containers for update:${NC}"
            $SUDO docker ps --filter "id=$RUNNING_CONTAINER_IDS" --format "{{.Names}} ({{.ID}})"
            
            # Store IDs for restart
            DOCKER_CONTAINERS_TO_RESTART="$RUNNING_CONTAINER_IDS"

            # Stop containers
            if $SUDO docker stop "$RUNNING_CONTAINER_IDS"; then
                echo -e "${GREEN}Containers stopped successfully.${NC}"
                # Verify stop
                STOPPED_CONTAINERS_CHECK=$($SUDO docker ps -q --filter "id=$RUNNING_CONTAINER_IDS")
                if [ -z "$STOPPED_CONTAINERS_CHECK" ]; then
                    echo -e "${GREEN}Confirmed: All specified containers are stopped.${NC}"
                else
                    echo -e "${YELLOW}Warning: Some containers might still be running after stop attempt: ${STOPPED_CONTAINERS_CHECK}${NC}"
                fi
            else
                echo -e "${RED}Error: Failed to stop Docker containers. Proceeding with update, but containers might be affected.${NC}"
                DOCKER_CONTAINERS_TO_RESTART="" # Clear for restart if stop failed
            fi
        else
            echo -e "${GREEN}No running Docker containers to stop.${NC}"
        fi
    fi
fi

# --- Upgrade ---
if [ -n "$SYSTEM_UPDATES" ] || [ -n "$FLATPAK_UPDATES" ] || [ -n "$SNAP_UPDATES" ]; then
    echo -e "${YELLOW}--- Pending Updates ---""${NC}"
    if [ -n "$SYSTEM_UPDATES" ]; then
        echo -e "${CYAN}--- System Updates ---""${NC}"
        echo "$SYSTEM_UPDATES"
    fi
    if [ -n "$FLATPAK_UPDATES" ]; then
        echo -e "${CYAN}--- Flatpak Updates ---""${NC}"
        echo "$FLATPAK_UPDATES"
    fi
    if [ -n "$SNAP_UPDATES" ]; then
        echo -e "${CYAN}--- Snap Updates ---""${NC}"
        echo "$SNAP_UPDATES"
    fi
    echo ""
    echo -e "${MAGENTA}Starting automatic upgrade...${NC}"

    # System Upgrade
    if [ -n "$SYSTEM_UPDATES" ]; then
        echo -e "${BLUE}Upgrading system packages...${NC}"
        case "$PACKAGE_MANAGER" in
            "apt")
                $SUDO apt upgrade -y
                ;;
            "dnf")
                     $SUDO dnf upgrade -y
                ;;
            "pacman")
                    $SUDO pacman -Syu --noconfirm
                ;;
            "apk")
                    $SUDO apk upgrade
                ;;
        esac
        echo -e "${GREEN}System upgrade complete.${NC}"

        # --- Docker Post-Update Restart ---
        if [ -n "$DOCKER_CONTAINERS_TO_RESTART" ]; then
            echo -e "${BLUE}Restarting previously running Docker containers...${NC}"
            $SUDO docker start "$DOCKER_CONTAINERS_TO_RESTART"
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
        $SUDO snap refresh
        echo -e "${GREEN}Snap upgrade complete.${NC}"
    fi
fi

echo ""
echo -e "${MAGENTA}--- Reboot Check ---${NC}"
REBOOT_NEEDED=false
case "$PACKAGE_MANAGER" in
    "apt")
        if [ -f /var/run/reboot-required ]; then
            REBOOT_NEEDED=true
            REBOOT_REASON_PKGS=$(cat /var/run/reboot-required.pkgs 2>/dev/null)
        fi
        ;;
    "dnf")
        # needs-restarting is in dnf-utils
        if ! command -v needs-restarting &> /dev/null; then
            echo -e "${YELLOW}'needs-restarting' command not found. Attempting to install 'dnf-utils'...${NC}"
            $SUDO dnf install -y dnf-utils >/dev/null 2>&1
        fi
        if command -v needs-restarting &> /dev/null; then
            # Exit code 1 means reboot is required.
            if $SUDO needs-restarting -r >/dev/null 2>&1; then
                : # Exit code 0, no reboot needed
            else
                REBOOT_NEEDED=true
            fi
        fi
        ;;
esac

if [ "$REBOOT_NEEDED" = true ]; then
    echo -e "${YELLOW}A system reboot is required to complete the updates.${NC}"
    [ -n "$REBOOT_REASON_PKGS" ] && echo -e "${YELLOW}Packages requiring reboot:${NC}\n${CYAN}$REBOOT_REASON_PKGS${NC}"
else
    echo -e "${GREEN}No reboot is required.${NC}"
fi

echo ""
echo -e "${MAGENTA}--- Cleaning up system ---""${NC}"

# Old Kernel Cleanup (Debian-based systems)
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    echo -e "${BLUE}Checking for old kernels to remove...${NC}"
    # Get the current kernel version to ensure we don't remove it
    CURRENT_KERNEL=$(uname -r)
    
    # Find all installed kernel packages, excluding the current one
    OLD_KERNELS=$(dpkg --list | grep -E 'linux-(image|headers)-[0-9]+' | awk '{ print $2 }' | grep -vF "$CURRENT_KERNEL")

    if [ -n "$OLD_KERNELS" ]; then
        echo -e "${YELLOW}Found old kernel packages that can be removed:${NC}"
        echo -e "${CYAN}$OLD_KERNELS${NC}"
        echo -e "${YELLOW}Do you want to remove these old kernels? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            echo -e "${BLUE}Removing old kernels...${NC}"
            $SUDO apt-get purge -y $OLD_KERNELS
            echo -e "${GREEN}Old kernels removed.${NC}"
        else
            echo -e "${YELLOW}Skipping old kernel removal.${NC}"
        fi
    else
        echo -e "${GREEN}No old kernels found to remove.${NC}"
    fi
fi

# Autoremove unnecessary packages
echo -e "${BLUE}Removing unnecessary packages...${NC}"
case "$PACKAGE_MANAGER" in
    "apt")
        $SUDO apt autoremove -y
        ;;
    "dnf")
        $SUDO dnf autoremove -y
        ;;
    "pacman")
        # First, find orphaned packages, then remove them if any exist.
        if [[ -n $($SUDO pacman -Qdtq) ]]; then
            $SUDO pacman -Rns "$($SUDO pacman -Qdtq)" --noconfirm
        else
            echo "No orphaned packages to remove."
        fi
        ;;
    "apk")
        # apk does not have a direct 'autoremove' equivalent like apt/dnf.
        # Users typically manage explicitly installed packages and their dependencies.
        echo "apk does not have a direct 'autoremove' equivalent."
        echo "Consider manually removing unneeded packages if necessary."
        ;;
esac
echo -e "${GREEN}Done!${NC}"

# Clean package cache
echo -e "${BLUE}Clearing package cache...${NC}"
case "$PACKAGE_MANAGER" in
    "apt")
        $SUDO apt clean
        ;;
    "dnf")
        $SUDO dnf clean all
        ;;
    "pacman")
        $SUDO pacman -Scc --noconfirm # -Scc removes all cached packages. Use -Sc to keep the latest versions.
        ;;
    "apk")
        $SUDO apk cache clean
        ;;
esac
echo -e "${GREEN}Done!${NC}"

echo ""
echo -e "${MAGENTA}--- Distribution Upgrade Check ---""${NC}"
case "$PACKAGE_MANAGER" in
    "apt")
        # Flag to see if we found an upgrade
        UPGRADE_FOUND=false
        # First, try the Ubuntu/Ubuntu-like method silently
        if command -v do-release-upgrade &> /dev/null; then
            echo -e "${BLUE}Checking for a new distribution release (do-release-upgrade)...${NC}"
            UPGRADE_CHECK=$($SUDO do-release-upgrade -c 2>&1)
            if echo "$UPGRADE_CHECK" | grep -q "New release"; then
                RELEASE_INFO=$(echo "$UPGRADE_CHECK" | grep "New release")
                echo -e "${YELLOW}A new distribution release is available: $RELEASE_INFO${NC}"
                echo -e "${YELLOW}To upgrade, run the following command:${NC}"
                echo -e "${CYAN}$SUDO do-release-upgrade${NC}"
                UPGRADE_FOUND=true
            fi
        fi
        
        # If the first method didn't find anything, try the Debian/dist-upgrade method
        if [ "$UPGRADE_FOUND" = false ]; then
            echo -e "${BLUE}Checking for major package changes (apt dist-upgrade)...${NC}"
            DIST_UPGRADE_CHECK=$($SUDO apt -s dist-upgrade 2>&1)
            
            if echo "$DIST_UPGRADE_CHECK" | grep -q "upgraded, .* newly installed, .* to remove"; then
                SUMMARY=$(echo "$DIST_UPGRADE_CHECK" | grep "upgraded, .* newly installed, .* to remove")
                # Check if the summary line actually contains non-zero numbers
                if ! echo "$SUMMARY" | grep -q "0 upgraded, 0 newly installed, 0 to remove"; then
                    echo -e "${YELLOW}A distribution upgrade or major package change may be available.${NC}"
                    echo -e "${YELLOW}Summary: $SUMMARY${NC}"
                    echo -e "${YELLOW}To apply these changes, review them carefully and then run:${NC}"
                    echo -e "${CYAN}$SUDO apt full-upgrade${NC}"
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
        echo -e "${CYAN}$SUDO dnf system-upgrade download --releasever=<version>${NC}"
        echo -e "${BLUE}Please consult your distribution's official documentation for the correct version number and instructions.${NC}"
        ;;
    "pacman")
        echo -e "${BLUE}Your system uses a rolling release model.${NC}"
        echo -e "${BLUE}Regular updates using '$SUDO pacman -Syu' keep your system on the latest version.${NC}"
        echo -e "${GREEN}Your distribution is continuously up to date.${NC}"
        ;;
    "apk")
        echo -e "${BLUE}Your system uses a rolling release model.${NC}"
        echo -e "${BLUE}Regular updates using '$SUDO apk upgrade' keep your system on the latest version.${NC}"
        echo -e "${BLUE}Major version upgrades for Alpine Linux typically involve manual changes to /etc/apk/repositories.${NC}"
        echo -e "${GREEN}Your distribution is continuously up to date.${NC}"
        ;;
    *)
        echo -e "${YELLOW}Could not determine the distribution upgrade method for '$OS'.${NC}"
        echo -e "${YELLOW}Please consult your distribution's official documentation.${NC}"
        ;;
esac

echo ""
echo -e "${MAGENTA}--- Clearing Old Logs ---""${NC}"
if command -v journalctl &> /dev/null; then
    echo -e "${BLUE}Using journalctl to clear logs older than 10 days...${NC}"
    $SUDO journalctl --vacuum-time=10d
else
    echo -e "${YELLOW}Warning: 'journalctl' not found. Using 'find' to clear logs from /var/log.${NC}"
    echo -e "${BLUE}Clearing .log and .gz files older than 10 days from /var/log...${NC}"
    $SUDO find /var/log -type f -name "*.log" -mtime +10 -delete
    $SUDO find /var/log -type f -name "*.gz" -mtime +10 -delete
fi
echo -e "${GREEN}Old logs cleared.${NC}"

echo ""
echo -e "${MAGENTA}--- Firmware Update Check ---""${NC}"
if command -v fwupdmgr &> /dev/null; then
    echo -n -e "${BLUE}Refreshing firmware metadata...${NC}"
    ($SUDO fwupdmgr refresh --force) >/dev/null 2>&1 &
    spinner $!
    echo -e "${GREEN}Done!${NC}"
    
    echo -e "${BLUE}Checking for firmware updates...${NC}"
    FIRMWARE_UPDATES=$($SUDO fwupdmgr get-updates 2>&1)
    
    if echo "$FIRMWARE_UPDATES" | grep -q "No updatable devices" || echo "$FIRMWARE_UPDATES" | grep -q "No updates available"; then
        echo -e "${GREEN}No firmware updates available.${NC}"
    else
        echo -e "${YELLOW}Firmware updates available:${NC}"
        echo -e "${CYAN}$FIRMWARE_UPDATES${NC}"
        echo -e "${YELLOW}To apply these updates, run '$SUDO fwupdmgr update'.${NC}"
    fi
else
    echo -e "${YELLOW}fwupdmgr not found. Skipping firmware update check.${NC}"
fi

# --- Open Ports on System ---
echo ""
echo -e "${MAGENTA}--- Open Ports on System ---""${NC}"

# Check for lsof and install if not present
if ! command -v lsof &> /dev/null; then
    echo -e "${YELLOW}'lsof' command not found. Attempting to install...${NC}"
    case "$PACKAGE_MANAGER" in
        "apt")
            $SUDO apt install -y lsof
            ;;
        "dnf")
            $SUDO dnf install -y lsof
            ;;
        "pacman")
            $SUDO pacman -S --noconfirm lsof
            ;;
        "apk")
            $SUDO apk add lsof
            ;;
    esac
    # Verify lsof installation
    if ! command -v lsof &> /dev/null; then
        echo -e "${RED}Failed to install 'lsof'. Open ports will not be displayed.${NC}"
    fi
fi

# Now, list the ports
if command -v lsof &> /dev/null; then
    echo -e "${BLUE}Listing listening TCP and UDP ports with lsof...${NC}"
    $SUDO lsof -i -P -n | grep LISTEN
elif command -v ss &> /dev/null; then
    echo -e "${BLUE}lsof not found. Using 'ss' to list listening TCP and UDP ports...${NC}"
    $SUDO ss -tuln
elif command -v netstat &> /dev/null; then
    echo -e "${BLUE}lsof and ss not found. Using 'netstat' to list listening TCP and UDP ports...${NC}"
    $SUDO netstat -tuln
else
    echo -e "${RED}Error: Could not find lsof, ss, or netstat. Cannot display open ports.${NC}"
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN} All updates completed successfully! ${NC}"
echo -e "${GREEN}=====================================${NC}"
exit 0
