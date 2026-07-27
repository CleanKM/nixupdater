#!/bin/bash

# Export robust PATH to ensure all tools (including Linuxbrew) are accessible in headless contexts
export PATH="/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

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

# Helper function to run commands as non-root user when elevated
run_as_user() {
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}

# Helper function to run Homebrew as the non-root user when elevated
run_brew() {
    run_as_user brew "$@"
}

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_VERSION="1.10.0"

# --- Self-Update Check ---
SKIP_SELF_UPDATE=false
if [ "$NIXUPDATER_SKIP_CHECK" = "true" ]; then
    SKIP_SELF_UPDATE=true
fi
for arg in "$@"; do
    if [ "$arg" == "noupdate" ]; then
        SKIP_SELF_UPDATE=true
        break
    fi
done

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")" # Get absolute path of the current script

if [ "$SKIP_SELF_UPDATE" = true ]; then
    if [ "$NIXUPDATER_SKIP_CHECK" != "true" ]; then
        echo -e "${YELLOW}Skipping self-update check due to 'noupdate' argument.${NC}"
    fi
else
    GITHUB_RAW_URL="https://raw.githubusercontent.com/CleanKM/nixupdater/main/linux/update.sh"
TEMP_SCRIPT_PATH=$(mktemp)
trap 'rm -f "$TEMP_SCRIPT_PATH"' EXIT

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Warning: 'curl' not found. Cannot check for script updates.${NC}"
    rm -f "$TEMP_SCRIPT_PATH"
    trap - EXIT
else
    # Download remote script with cache-busting and network timeouts
    CACHE_BUSTER=$(date +%s)
    if ! curl -sSfL --connect-timeout 5 --max-time 10 -H "Cache-Control: no-cache" "$GITHUB_RAW_URL?t=$CACHE_BUSTER" -o "$TEMP_SCRIPT_PATH"; then
        echo -e "${RED}Error: Failed to download remote script or network is down. Skipping self-update.${NC}"
        rm -f "$TEMP_SCRIPT_PATH"
        trap - EXIT
    else
        LOCAL_CHECKSUM=$(get_sha256 "$SCRIPT_PATH")
        REMOTE_CHECKSUM=$(get_sha256 "$TEMP_SCRIPT_PATH")

        if [ -z "$LOCAL_CHECKSUM" ] || [ -z "$REMOTE_CHECKSUM" ]; then
            echo -e "${RED}Error: Checksum utility not found or failed. Skipping self-update.${NC}"
            rm -f "$TEMP_SCRIPT_PATH"
            trap - EXIT
        elif [ "$LOCAL_CHECKSUM" != "$REMOTE_CHECKSUM" ]; then
            echo -e "${YELLOW}A new version of the script is available!${NC}"
            echo -e "${YELLOW}Do you want to update to the latest version? (y/n)${NC}"
            RESPONSE_IS_YES=false
            if [ -t 1 ]; then
                read -r response < /dev/tty
                if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    RESPONSE_IS_YES=true
                else
                    echo -e "${YELLOW}Skipping script update.${NC}"
                fi
            else
                echo -e "${YELLOW}Non-interactive mode detected. Skipping script update.${NC}"
            fi

            if [ "$RESPONSE_IS_YES" = true ]; then
                echo -e "${BLUE}Updating script...${NC}"
                if mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH"; then
                    chmod +x "$SCRIPT_PATH"
                    echo -e "${GREEN}Script updated successfully. Relaunching...${NC}"
                    export NIXUPDATER_SKIP_CHECK=true
                    trap - EXIT
                    exec "$SCRIPT_PATH" "$@" # Relaunch the updated script
                else
                    echo -e "${RED}Error: Failed to replace the script. Please update manually.${NC}"
                    rm -f "$TEMP_SCRIPT_PATH"
                    trap - EXIT
                fi
            else
                echo -e "${YELLOW}Skipping script update.${NC}"
                rm -f "$TEMP_SCRIPT_PATH"
                trap - EXIT
            fi
        else
            echo -e "${GREEN}Script is already up to date.${NC}"
            rm -f "$TEMP_SCRIPT_PATH"
            trap - EXIT
        fi
    fi
fi
fi

# --- Sudo check and prompt ---
SUDO=''
if [ "$EUID" -ne 0 ]; then
    # Not running as root
    echo -e "${BLUE}This script requires sudo privileges to run.${NC}"

    if id -Gn "${SUDO_USER:-$USER}" 2>/dev/null | grep -qE '\b(sudo|wheel)\b'; then
        # User is in the sudo group, offer to relaunch
        echo -e "${YELLOW}You are in the 'sudo' group. Do you want to relaunch this script with sudo? (y/n)${NC}"
        RESPONSE_IS_YES=false
        if [ -t 1 ]; then
            read -r response < /dev/tty # Ensure read from tty
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                RESPONSE_IS_YES=true
            else
                echo -e "${YELLOW}Sudo relaunch declined.${NC}"
            fi
        else
            echo -e "${YELLOW}Non-interactive mode detected. Sudo relaunch declined.${NC}"
        fi

        if [ "$RESPONSE_IS_YES" = true ]; then
            echo -e "${BLUE}Relaunching with sudo...${NC}"
            exec sudo NIXUPDATER_SKIP_CHECK=true "$SCRIPT_PATH" "$@" # Relaunch the script with sudo
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
    SUDO='' # We are root, no need to prefix with sudo internally
    echo -e "${GREEN}Sudo privileges obtained.${NC}"
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
    # Standalone running:
    STANDALONE_LIST=$($SUDO docker ps --filter "label!=com.docker.compose.project" --format "{{.Names}} ({{.ID}})" 2>/dev/null || true)
    # Compose running:
    COMPOSE_LIST=$($SUDO docker ps --filter "label=com.docker.compose.project" --format "{{.Names}} ({{.ID}}) [Compose Project: {{.Label \"com.docker.compose.project\"}}]" 2>/dev/null || true)
    
    if [ -n "$STANDALONE_LIST" ] || [ -n "$COMPOSE_LIST" ]; then
        echo -e "${MAGENTA}--- Running Docker Containers ---${NC}"
        if [ -n "$COMPOSE_LIST" ]; then
            echo -e "${CYAN}Docker Compose Containers:${NC}"
            echo -e "${CYAN}$COMPOSE_LIST${NC}"
        fi
        if [ -n "$STANDALONE_LIST" ]; then
            echo -e "${CYAN}Standalone Containers (docker run):${NC}"
            echo -e "${CYAN}$STANDALONE_LIST${NC}"
        fi
        echo ""
    fi
fi

# --- Spinner ---
spinner() {
    local pid=$1
    if [ ! -t 1 ]; then
        wait "$pid"
        return
    fi
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
elif [ -f /usr/lib/os-release ]; then
    . /usr/lib/os-release
else
    echo -e "${RED}Cannot detect Linux distribution.${NC}"
    exit 1
fi
OS=$NAME
DISTRO=$ID
echo -e "${GREEN}Done! ($OS)${NC}"

# --- Package Manager Detection ---
if [ -f /run/ostree-booted ] && command -v rpm-ostree &> /dev/null; then
    PACKAGE_MANAGER="rpm-ostree"
elif command -v transactional-update &> /dev/null; then
    PACKAGE_MANAGER="transactional-update"
elif command -v nixos-rebuild &> /dev/null; then
    PACKAGE_MANAGER="nixos"
else
    case "$DISTRO" in
        "ubuntu" | "debian" | "pop" | "linuxmint" | "zorin" | "elementary" | "raspbian" | "mx" | "kali")
            PACKAGE_MANAGER="apt"
            ;;
        "fedora" | "centos" | "rhel" | "nobara" | "rocky" | "almalinux")
            if command -v dnf5 &> /dev/null; then
                PACKAGE_MANAGER="dnf5"
            else
                PACKAGE_MANAGER="dnf"
            fi
            ;;
        "arch" | "manjaro" | "endeavouros" | "garuda")
            PACKAGE_MANAGER="pacman"
            ;;
        "alpine")
            PACKAGE_MANAGER="apk"
            ;;
        "opensuse"* | "suse" | "tumbleweed" | "leap")
            PACKAGE_MANAGER="zypper"
            ;;
        *)
            if echo "$ID_LIKE" | grep -qE '\b(ubuntu|debian)\b'; then
                PACKAGE_MANAGER="apt"
            elif echo "$ID_LIKE" | grep -qE '\b(fedora|rhel|centos)\b'; then
                if command -v dnf5 &> /dev/null; then PACKAGE_MANAGER="dnf5"; else PACKAGE_MANAGER="dnf"; fi
            elif echo "$ID_LIKE" | grep -qE '\b(arch)\b'; then
                PACKAGE_MANAGER="pacman"
            elif echo "$ID_LIKE" | grep -qE '\b(alpine)\b'; then
                PACKAGE_MANAGER="apk"
            elif echo "$ID_LIKE" | grep -qE '\b(suse|opensuse)\b'; then
                PACKAGE_MANAGER="zypper"
            elif command -v apt &> /dev/null; then
                PACKAGE_MANAGER="apt"
                echo -e "${GREEN}Found 'apt'. Proceeding.${NC}"
            elif command -v dnf5 &> /dev/null; then
                PACKAGE_MANAGER="dnf5"
                echo -e "${GREEN}Found 'dnf5'. Proceeding.${NC}"
            elif command -v dnf &> /dev/null; then
                PACKAGE_MANAGER="dnf"
                echo -e "${GREEN}Found 'dnf'. Proceeding.${NC}"
            elif command -v pacman &> /dev/null; then
                PACKAGE_MANAGER="pacman"
                echo -e "${GREEN}Found 'pacman'. Proceeding.${NC}"
            elif command -v apk &> /dev/null; then
                PACKAGE_MANAGER="apk"
                echo -e "${GREEN}Found 'apk'. Proceeding.${NC}"
            elif command -v zypper &> /dev/null; then
                PACKAGE_MANAGER="zypper"
                echo -e "${GREEN}Found 'zypper'. Proceeding.${NC}"
            else
                echo -e "${RED}Could not find a supported package manager. Exiting.${NC}"
                exit 1
            fi
            ;;
    esac
fi
echo -e "${BLUE}Using package manager: ${GREEN}$PACKAGE_MANAGER${NC}"

# Check for Arch AUR helpers
AUR_HELPER=""
if [ "$PACKAGE_MANAGER" = "pacman" ]; then
    if command -v yay &> /dev/null; then
        AUR_HELPER="yay"
        echo -e "${BLUE}Found Arch AUR helper: ${GREEN}yay${NC}"
    elif command -v paru &> /dev/null; then
        AUR_HELPER="paru"
        echo -e "${BLUE}Found Arch AUR helper: ${GREEN}paru${NC}"
    fi
fi
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
        $SUDO DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update >/dev/null 2>&1
        ;;
    "dnf5" | "dnf")
        ;;
    "pacman")
        if command -v checkupdates &> /dev/null; then
            :
        else
            $SUDO pacman -Sy >/dev/null 2>&1
        fi
        ;;
    "apk")
        $SUDO apk update >/dev/null 2>&1
        ;;
    "zypper")
        $SUDO zypper refresh >/dev/null 2>&1
        ;;
    "rpm-ostree")
        rpm-ostree upgrade --check >/dev/null 2>&1
        ;;
    "transactional-update" | "nixos")
        ;;
esac
) & 
spinner $!
echo -e "${GREEN}Done!${NC}"

# Security Advisory Audit Check
if command -v dnf5 &> /dev/null; then
    SEC_INFO=$($SUDO dnf5 advisory summary 2>/dev/null | grep -iE 'security|critical|important' || true)
    [ -n "$SEC_INFO" ] && echo -e "${YELLOW}Security Advisories (DNF5):${NC}\n${CYAN}$SEC_INFO${NC}\n"
elif command -v dnf &> /dev/null; then
    SEC_INFO=$($SUDO dnf updateinfo summary 2>/dev/null | grep -iE 'security|critical|important' || true)
    [ -n "$SEC_INFO" ] && echo -e "${YELLOW}Security Advisories (DNF):${NC}\n${CYAN}$SEC_INFO${NC}\n"
elif command -v arch-audit &> /dev/null; then
    SEC_INFO=$(arch-audit 2>/dev/null || true)
    [ -n "$SEC_INFO" ] && echo -e "${YELLOW}Vulnerabilities Detected (arch-audit):${NC}\n${RED}$SEC_INFO${NC}\n"
fi

SYSTEM_UPDATES=$(
case "$PACKAGE_MANAGER" in
    ("apt")
        apt-get --just-print upgrade 2>/dev/null | grep "^Inst "
        ;;
    ("dnf5")
        dnf5 check-update 2>/dev/null | tail -n +2
        ;;
    ("dnf")
        dnf check-update 2>/dev/null | tail -n +2
        ;;
    ("pacman")
        if command -v checkupdates &> /dev/null; then
            checkupdates 2>/dev/null
        else
            pacman -Qu 2>/dev/null
        fi
        ;;
    ("apk")
        apk list --upgradeable 2>/dev/null | tail -n +1
        ;;
    ("zypper")
        zypper list-updates 2>/dev/null | grep -E '^v \|'
        ;;
    ("rpm-ostree")
        rpm-ostree status -v | grep -q -E "AvailableUpdate: yes|Staged: yes" && echo "OSTree updates are available (pending deployment)."
        ;;
    ("transactional-update")
        echo "Transactional updates will be checked during the upgrade phase."
        ;;
    ("nixos")
        echo "NixOS channel/flake updates will be evaluated during the upgrade phase."
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

BREW_UPDATES=""
if command -v brew &> /dev/null; then
    echo -n -e "${BLUE}Checking for Homebrew updates...${NC}"
    BREW_UPDATES=$(run_brew outdated 2>/dev/null)
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${YELLOW}Homebrew not found. Skipping Homebrew check.${NC}"
fi
echo ""

# --- List Updates and Upgrade ---
if [ -z "$SYSTEM_UPDATES" ] && [ -z "$FLATPAK_UPDATES" ] && [ -z "$SNAP_UPDATES" ] && [ -z "$BREW_UPDATES" ]; then
    echo -e "${GREEN}=========================${NC}"
    echo -e "${GREEN} Your system is up to date. ${NC}"
    echo -e "${GREEN}=========================${NC}"
fi


# --- Docker Pre-Update Check ---
DOCKER_STANDALONE_TO_RESTART=""
DOCKER_COMPOSE_TO_RESTART=""
if command -v docker &> /dev/null; then
    ALL_UPDATES_TEXT="${SYSTEM_UPDATES}${SNAP_UPDATES}${BREW_UPDATES}"
    if echo "$ALL_UPDATES_TEXT" | grep -qiE '\b(docker|containerd)\b'; then
        echo -e "${YELLOW}Docker-related update found.${NC}"
        
        # 1. Identify Compose Project Configs (Running only)
        COMPOSE_CONFIGS=$($SUDO docker ps --filter "label=com.docker.compose.project.config_files" --format '{{.Label "com.docker.compose.project.config_files"}}' | awk 'NF' | sort -u)
        
        # 2. Identify Standalone Containers (Running only)
        # First grab all running, then omit compose ones
        ALL_RUNNING=$($SUDO docker ps -q)
        COMPOSE_RUNNING=$($SUDO docker ps -q --filter "label=com.docker.compose.project.config_files")
        if [ -n "$COMPOSE_RUNNING" ]; then
            STANDALONE_CONTAINERS=$(echo "$ALL_RUNNING" | grep -vF -f <(echo "$COMPOSE_RUNNING") || true)
        else
            STANDALONE_CONTAINERS="$ALL_RUNNING"
        fi
        
        if [ -n "$COMPOSE_CONFIGS" ] || [ -n "$STANDALONE_CONTAINERS" ]; then
            echo -e "${YELLOW}Docker containers are currently running, but a Docker/containerd update is available.${NC}"
            echo -e "${YELLOW}It is recommended to stop them before updating. Do you want to:${NC}"
            echo -e "${CYAN}[1] Stop ALL running containers automatically${NC}"
            echo -e "${CYAN}[2] Select which containers/projects to stop individually${NC}"
            echo -e "${CYAN}[3] Skip stopping containers${NC}"
            
            STOP_MODE="1"
            if [ -t 1 ]; then
                echo -n -e "${YELLOW}Enter your choice [1-3] (default 1): ${NC}"
                read -r response < /dev/tty
                if [[ "$response" == "2" ]]; then STOP_MODE="2"; fi
                if [[ "$response" == "3" ]]; then STOP_MODE="3"; fi
            else
                echo -e "${YELLOW}Non-interactive mode detected. Defaulting to [1] (Stop ALL).${NC}"
            fi

            if [ "$STOP_MODE" == "1" ] || [ "$STOP_MODE" == "2" ]; then
                if [ "$STOP_MODE" == "2" ]; then
                    # Interactive selection loop
                    SELECTED_COMPOSE=""
                    SELECTED_STANDALONE=""
                    
                    if [ -n "$COMPOSE_CONFIGS" ]; then
                        echo -e "${BLUE}--- Select Compose Projects ---${NC}"
                        while IFS= read -r CONF; do
                            [ -z "$CONF" ] && continue
                            echo -n -e "${CYAN}Stop Compose Project [$CONF]? (y/N): ${NC}"
                            read -r ans < /dev/tty
                            if [[ "$ans" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                                SELECTED_COMPOSE="$SELECTED_COMPOSE$CONF\n"
                            fi
                        done <<< "$COMPOSE_CONFIGS"
                        COMPOSE_CONFIGS=$(echo -e -n "$SELECTED_COMPOSE" | sed '/^$/d')
                    fi
                    
                    if [ -n "$STANDALONE_CONTAINERS" ]; then
                        echo -e "${BLUE}--- Select Standalone Containers ---${NC}"
                        for ID in $STANDALONE_CONTAINERS; do
                            [ -z "$ID" ] && continue
                            CNAME=$($SUDO docker inspect --format="{{.Name}}" "$ID" 2>/dev/null)
                            CNAME=${CNAME#/} # strip leading slash
                            echo -n -e "${CYAN}Stop Standalone Container $CNAME ($ID)? (y/N): ${NC}"
                            read -r ans < /dev/tty
                            if [[ "$ans" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                                SELECTED_STANDALONE="$SELECTED_STANDALONE$ID "
                            fi
                        done
                        STANDALONE_CONTAINERS=$(echo -n "$SELECTED_STANDALONE" | xargs)
                    fi
                fi

                echo -e "${BLUE}Stopping selected Docker containers prior to update...${NC}"
                
                # Stop Compose Projects
                if [ -n "$COMPOSE_CONFIGS" ]; then
                    DOCKER_COMPOSE_TO_RESTART="$COMPOSE_CONFIGS"
                    echo -e "${CYAN}Stopping Docker Compose environments:${NC}"
                    while IFS= read -r CONF_FILES; do
                        [ -z "$CONF_FILES" ] && continue
                        COMPOSE_ARGS=()
                        IFS=',' read -ra FILES <<< "$CONF_FILES"
                        for FILE in "${FILES[@]}"; do
                            COMPOSE_ARGS+=("-f" "$FILE")
                        done
                        echo -e " ${YELLOW}-> docker compose ${COMPOSE_ARGS[*]} stop${NC}"
                        $SUDO docker compose "${COMPOSE_ARGS[@]}" stop || true
                    done <<< "$COMPOSE_CONFIGS"
                fi
                
                # Stop Standalone Containers
                if [ -n "$STANDALONE_CONTAINERS" ]; then
                    DOCKER_STANDALONE_TO_RESTART="$STANDALONE_CONTAINERS"
                    echo -e "${CYAN}Stopping standalone containers:${NC}"
                    $SUDO docker stop $STANDALONE_CONTAINERS >/dev/null 2>&1 || true
                fi
                
                # Verify stop - only check targeted containers
                REMAINING_TARGETED=""
                for ID in $STANDALONE_CONTAINERS; do
                    [ -z "$ID" ] && continue
                    STILL_UP=$($SUDO docker ps -q --filter "id=$ID" 2>/dev/null)
                    [ -n "$STILL_UP" ] && REMAINING_TARGETED="$REMAINING_TARGETED $ID"
                done
                if [ -n "$COMPOSE_CONFIGS" ]; then
                    while IFS= read -r CONF_FILES_CHK; do
                        [ -z "$CONF_FILES_CHK" ] && continue
                        STILL_UP=$($SUDO docker ps -q --filter "label=com.docker.compose.project.config_files=$CONF_FILES_CHK" 2>/dev/null)
                        [ -n "$STILL_UP" ] && REMAINING_TARGETED="$REMAINING_TARGETED compose:$(basename "$(dirname "$CONF_FILES_CHK")")"
                    done <<< "$COMPOSE_CONFIGS"
                fi
                REMAINING_TARGETED=$(echo "$REMAINING_TARGETED" | xargs)
                if [ -z "$REMAINING_TARGETED" ]; then
                    echo -e "${GREEN}Confirmed: All targeted containers are stopped.${NC}"
                else
                    echo -e "${YELLOW}Warning: Some targeted containers may still be running: ${REMAINING_TARGETED}${NC}"
                fi
            else
                echo -e "${YELLOW}Skipping Docker container shutdown. Proceeding with update...${NC}"
            fi
        else
            echo -e "${GREEN}No running Docker containers to stop.${NC}"
        fi
    fi
fi

# --- Upgrade ---
if [ -n "$SYSTEM_UPDATES" ] || [ -n "$FLATPAK_UPDATES" ] || [ -n "$SNAP_UPDATES" ] || [ -n "$BREW_UPDATES" ]; then
    echo -e "${YELLOW}--- Pending Updates ---${NC}"
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
    if [ -n "$BREW_UPDATES" ]; then
        echo -e "${CYAN}--- Homebrew Updates ---""${NC}"
        echo "$BREW_UPDATES"
    fi
    echo ""
    echo -e "${MAGENTA}Starting automatic upgrade...${NC}"

    # System Upgrade
    if [ -n "$SYSTEM_UPDATES" ]; then
        echo -e "${BLUE}Upgrading system packages...${NC}"
        case "$PACKAGE_MANAGER" in
            "apt")
                $SUDO DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get upgrade -y
                ;;
            "dnf5")
                $SUDO dnf5 upgrade -y
                ;;
            "dnf")
                $SUDO dnf upgrade -y
                ;;
            "pacman")
                if [ -n "$AUR_HELPER" ]; then
                    echo -e "${BLUE}Upgrading system and AUR packages using $AUR_HELPER...${NC}"
                    run_as_user "$AUR_HELPER" -Syu --noconfirm
                else
                    $SUDO pacman -Syu --noconfirm
                fi
                ;;
            "apk")
                $SUDO apk upgrade
                ;;
            "zypper")
                if grep -q -i "tumbleweed" /etc/os-release 2>/dev/null; then
                    $SUDO zypper --non-interactive dup
                else
                    $SUDO zypper --non-interactive up
                fi
                ;;
            "rpm-ostree")
                if command -v bootc &> /dev/null && ! grep -q -E -e "LockLayering=false" /etc/rpm-ostreed.conf 2>/dev/null; then
                    $SUDO bootc upgrade
                else
                    $SUDO rpm-ostree upgrade
                fi
                ;;
            "transactional-update")
                $SUDO transactional-update dup
                ;;
            "nixos")
                if [ -f /etc/nixos/flake.nix ] || [ -f /etc/nixos/flake.lock ]; then
                    echo -e "${BLUE}Updating NixOS Flake...${NC}"
                    $SUDO nix flake update --flake /etc/nixos && $SUDO nixos-rebuild switch --upgrade
                else
                    $SUDO nix-channel --update && $SUDO nixos-rebuild switch --upgrade
                fi
                ;;
        esac
        echo -e "${GREEN}System upgrade complete.${NC}"

        # --- Docker Post-Update Restart ---
        if [ -n "$DOCKER_COMPOSE_TO_RESTART" ] || [ -n "$DOCKER_STANDALONE_TO_RESTART" ]; then
            # Build restart items list
            RESTART_COMPOSE=()
            while IFS= read -r line; do
                [ -n "$line" ] && RESTART_COMPOSE+=("$line")
            done <<< "$DOCKER_COMPOSE_TO_RESTART"

            RESTART_STANDALONE=()
            for ID in $DOCKER_STANDALONE_TO_RESTART; do
                [ -n "$ID" ] && RESTART_STANDALONE+=("$ID")
            done

            while [ ${#RESTART_COMPOSE[@]} -gt 0 ] || [ ${#RESTART_STANDALONE[@]} -gt 0 ]; do
                echo -e "\n${MAGENTA}--- Docker Post-Update Restart Menu ---${NC}"
                echo -e "${BLUE}The following containers/projects were stopped and await restart:${NC}"
                
                idx=1
                item_map=() # array to correlate choice index back to type and value
                
                # Print Compose
                for i in "${!RESTART_COMPOSE[@]}"; do
                    echo -e "${CYAN}[$idx] Compose Project: ${RESTART_COMPOSE[$i]}${NC}"
                    item_map[$idx]="compose|$i"
                    ((idx++))
                done
                
                # Print Standalone
                for i in "${!RESTART_STANDALONE[@]}"; do
                    ID="${RESTART_STANDALONE[$i]}"
                    CNAME=$($SUDO docker inspect --format="{{.Name}}" "$ID" 2>/dev/null)
                    CNAME=${CNAME#/}
                    echo -e "${CYAN}[$idx] Standalone: $CNAME ($ID)${NC}"
                    item_map[$idx]="standalone|$i"
                    ((idx++))
                done

                echo -e "${GREEN}[a] Restart all remaining items automatically${NC}"
                echo -e "${YELLOW}[d] Done (leave remaining items stopped)${NC}"
                
                if ! [ -t 1 ]; then
                    echo -e "${YELLOW}Non-interactive mode. Auto-restarting all.${NC}"
                    ans="a"
                else
                    echo -n -e "${YELLOW}Select an option to restart it now: ${NC}"
                    read -r ans < /dev/tty
                fi

                if [[ "$ans" == "a" || "$ans" == "A" ]]; then
                    # Bulk start remaining
                    if [ ${#RESTART_COMPOSE[@]} -gt 0 ]; then
                        echo -e "${BLUE}Restarting remaining Compose environments...${NC}"
                        for CONF_FILES in "${RESTART_COMPOSE[@]}"; do
                            COMPOSE_ARGS=()
                            IFS=',' read -ra FILES <<< "$CONF_FILES"
                            for FILE in "${FILES[@]}"; do COMPOSE_ARGS+=("-f" "$FILE"); done
                            echo -e " ${CYAN}-> docker compose ${COMPOSE_ARGS[*]} up -d${NC}"
                            $SUDO docker compose "${COMPOSE_ARGS[@]}" up -d || true
                        done
                    fi
                    if [ ${#RESTART_STANDALONE[@]} -gt 0 ]; then
                        echo -e "${BLUE}Restarting remaining standalone Docker containers...${NC}"
                        $SUDO docker start "${RESTART_STANDALONE[@]}" >/dev/null 2>&1
                    fi
                    echo -e "${GREEN}All leftover containers restarted.${NC}"
                    break
                elif [[ "$ans" == "d" || "$ans" == "D" ]]; then
                    echo -e "${YELLOW}Leaving remaining items stopped.${NC}"
                    break
                elif [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -lt "$idx" ]; then
                    # Parse selection
                    item_type="${item_map[$ans]%|*}"
                    arr_idx="${item_map[$ans]#*|}"
                    
                    if [ "$item_type" == "compose" ]; then
                        CONF_FILES="${RESTART_COMPOSE[$arr_idx]}"
                        COMPOSE_ARGS=()
                        IFS=',' read -ra FILES <<< "$CONF_FILES"
                        for FILE in "${FILES[@]}"; do COMPOSE_ARGS+=("-f" "$FILE"); done
                        echo -e "${BLUE}Starting Compose Project: $CONF_FILES${NC}"
                        $SUDO docker compose "${COMPOSE_ARGS[@]}" up -d || true
                        unset 'RESTART_COMPOSE[$arr_idx]'
                        # Rebuild array to fix indices
                        RESTART_COMPOSE=("${RESTART_COMPOSE[@]}")
                    elif [ "$item_type" == "standalone" ]; then
                        ID="${RESTART_STANDALONE[$arr_idx]}"
                        echo -e "${BLUE}Starting Standalone Container: $ID${NC}"
                        $SUDO docker start "$ID" >/dev/null 2>&1 || true
                        unset 'RESTART_STANDALONE[$arr_idx]'
                        RESTART_STANDALONE=("${RESTART_STANDALONE[@]}")
                    fi
                    echo -e "${GREEN}Item started!${NC}"
                else
                    echo -e "${RED}Invalid selection. Please try again.${NC}"
                fi
            done
        fi
    fi

    # Flatpak Upgrade
    if [ -n "$FLATPAK_UPDATES" ]; then
        echo -e "${BLUE}Upgrading Flatpak packages...${NC}"
        flatpak update -y
        echo -e "${BLUE}Removing unused Flatpak runtimes...${NC}"
        flatpak uninstall --unused -y 2>/dev/null || true
        echo -e "${GREEN}Flatpak upgrade complete.${NC}"
    fi

    # Snap Upgrade
    if [ -n "$SNAP_UPDATES" ]; then
        echo -e "${BLUE}Upgrading Snap packages...${NC}"
        $SUDO snap refresh
        echo -e "${GREEN}Snap upgrade complete.${NC}"
    fi

    # Homebrew Upgrade
    if [ -n "$BREW_UPDATES" ]; then
        echo -e "${BLUE}Upgrading Homebrew packages...${NC}"
        run_brew upgrade
        run_brew cleanup
        echo -e "${GREEN}Homebrew upgrade complete.${NC}"
    fi

    # Developer Package Managers Upgrade (pipx, cargo, npm)
    if command -v pipx &> /dev/null; then
        echo -e "${BLUE}Upgrading pipx packages...${NC}"
        run_as_user pipx upgrade-all 2>/dev/null || true
        echo -e "${GREEN}pipx upgrade complete.${NC}"
    fi

    if command -v cargo &> /dev/null && cargo install-update --help &> /dev/null; then
        echo -e "${BLUE}Upgrading Cargo packages...${NC}"
        run_as_user cargo install-update -a 2>/dev/null || true
        echo -e "${GREEN}Cargo upgrade complete.${NC}"
    fi

    if command -v npm &> /dev/null; then
        echo -e "${BLUE}Upgrading global npm packages...${NC}"
        $SUDO npm update -g 2>/dev/null || true
        echo -e "${GREEN}npm global upgrade complete.${NC}"
    fi
fi

echo ""
echo -e "${MAGENTA}--- Reboot & Service Restart Check ---${NC}"
# Service Restart Audit (Services running outdated in-memory libraries)
if command -v dnf5 &> /dev/null; then
    SERVICES_TO_RESTART=$($SUDO dnf5 needs-restarting -s 2>/dev/null || true)
    [ -n "$SERVICES_TO_RESTART" ] && echo -e "${YELLOW}Services running outdated libraries (consider restarting):${NC}\n${CYAN}$SERVICES_TO_RESTART${NC}"
elif command -v dnf &> /dev/null && command -v needs-restarting &> /dev/null; then
    SERVICES_TO_RESTART=$($SUDO dnf needs-restarting -s 2>/dev/null || true)
    [ -n "$SERVICES_TO_RESTART" ] && echo -e "${YELLOW}Services running outdated libraries (consider restarting):${NC}\n${CYAN}$SERVICES_TO_RESTART${NC}"
elif command -v needrestart &> /dev/null; then
    echo -e "${BLUE}Auditing running services with needrestart...${NC}"
    $SUDO needrestart -b 2>/dev/null || true
fi

REBOOT_NEEDED=false
case "$PACKAGE_MANAGER" in
    "apt")
        if [ -f /var/run/reboot-required ]; then
            REBOOT_NEEDED=true
            REBOOT_REASON_PKGS=$(cat /var/run/reboot-required.pkgs 2>/dev/null)
        fi
        ;;
    "dnf5" | "dnf")
        if command -v dnf5 &> /dev/null; then
            if $SUDO dnf5 needs-restarting -r > /dev/null 2>&1; then
                :
            else
                REBOOT_NEEDED=true
            fi
        else
            if ! command -v needs-restarting &> /dev/null; then
                echo -e "${YELLOW}'needs-restarting' command not found. Attempting to install 'dnf-utils'...${NC}"
                $SUDO dnf install -y dnf-utils >/dev/null 2>&1
            fi
            if command -v needs-restarting &> /dev/null; then
                if $SUDO needs-restarting -r > /dev/null 2>&1; then
                    :
                else
                    REBOOT_NEEDED=true
                fi
            fi
        fi
        ;;
    "zypper")
        if $SUDO zypper ps -s 2>/dev/null | grep -qi "reboot"; then
            REBOOT_NEEDED=true
        fi
        ;;
    "rpm-ostree")
        if rpm-ostree status | grep -q -E "(pending)|Staged: yes"; then
            REBOOT_NEEDED=true
        fi
        ;;
    "transactional-update")
        if [ -n "$SYSTEM_UPDATES" ]; then
            REBOOT_NEEDED=true
        fi
        ;;
    "pacman" | "apk")
        if [ ! -d "/usr/lib/modules/$(uname -r)" ] && [ -d "/usr/lib/modules" ]; then
            REBOOT_NEEDED=true
        else
            echo -e "${YELLOW}Reboot check not automated for this package manager. Please reboot manually if a kernel was updated.${NC}"
        fi
        ;;
    "nixos")
        echo -e "${YELLOW}Reboot check not automated for this package manager. Please reboot manually if a kernel was updated.${NC}"
        ;;
esac

if [ "$REBOOT_NEEDED" = true ]; then
    echo -e "${YELLOW}A system reboot is required to complete the updates.${NC}"
    [ -n "$REBOOT_REASON_PKGS" ] && echo -e "${YELLOW}Packages requiring reboot:${NC}\n${CYAN}$REBOOT_REASON_PKGS${NC}"
else
    echo -e "${GREEN}No reboot is required.${NC}"
fi

echo ""
echo -e "${MAGENTA}--- Cleaning up system ---${NC}"

# Old Kernel Cleanup (Debian-based systems)
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    echo -e "${BLUE}Checking for old kernels to remove...${NC}"
    # Get the running kernel version and highest installed kernel version to prevent purging newly upgraded kernels
    CURRENT_KERNEL=$(uname -r)
    LATEST_KERNEL=$(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' 2>/dev/null | grep -E '^linux-image-[0-9]' | sed 's/linux-image-//' | sort -V | tail -n 1)
    
    # Find all installed kernel packages (state 'ii'), excluding running and newest kernel
    mapfile -t OLD_KERNELS < <(dpkg --list | grep -E '^\s*ii\s+linux-(image|headers)-[0-9]+' | awk '{ print $2 }' | grep -vF "$CURRENT_KERNEL" | { if [ -n "$LATEST_KERNEL" ]; then grep -vF "$LATEST_KERNEL"; else cat; fi; })

    if [ ${#OLD_KERNELS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Found old kernel packages that can be removed:${NC}"
        printf "${CYAN}%s${NC}\n" "${OLD_KERNELS[@]}"
        echo -e "${YELLOW}Do you want to remove these old kernels? (y/n)${NC}"
        RESPONSE_IS_YES=false
        if [ -t 1 ]; then
            read -r response < /dev/tty
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                RESPONSE_IS_YES=true
            fi
        else
            echo -e "${YELLOW}Non-interactive mode detected. Skipping old kernel removal.${NC}"
        fi

        if [ "$RESPONSE_IS_YES" = true ]; then
            echo -e "${BLUE}Removing old kernels...${NC}"
            $SUDO apt-get purge -y "${OLD_KERNELS[@]}"
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
        $SUDO DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
        ;;
    "dnf5")
        $SUDO dnf5 autoremove -y
        ;;
    "dnf")
        $SUDO dnf autoremove -y
        ;;
    "pacman")
        if [[ -n $($SUDO pacman -Qdtq) ]]; then
            $SUDO pacman -Qdtq | xargs $SUDO pacman -Rns --noconfirm
        else
            echo "No orphaned packages to remove."
        fi
        ;;
    "apk")
        echo "apk does not have a direct 'autoremove' equivalent."
        ;;
    "zypper")
        echo "zypper manages dependencies automatically during upgrades."
        ;;
    "rpm-ostree")
        echo "rpm-ostree images are managed atomically. No autoremove required."
        ;;
    "transactional-update")
        echo "Transactional snapshots will be cleaned up during the next phase."
        ;;
    "nixos")
        $SUDO nix-collect-garbage -d
        echo -e "${BLUE}Optimizing Nix store...${NC}"
        $SUDO nix-store --optimise
        ;;
esac
echo -e "${GREEN}Done!${NC}"

# Clean package cache & disabled snaps
echo -e "${BLUE}Clearing package cache...${NC}"
case "$PACKAGE_MANAGER" in
    "apt")
        $SUDO apt-get clean
        ;;
    "dnf5")
        $SUDO dnf5 clean all
        ;;
    "dnf")
        $SUDO dnf clean all
        ;;
    "pacman")
        if command -v paccache &> /dev/null; then
            echo -e "${BLUE}Cleaning pacman cache retaining last 3 versions (paccache)...${NC}"
            $SUDO paccache -r >/dev/null 2>&1 || true
        else
            $SUDO pacman -Sc --noconfirm
        fi
        ;;
    "apk")
        $SUDO apk cache purge 2>/dev/null || $SUDO apk cache clean
        ;;
    "zypper")
        $SUDO zypper clean -a
        ;;
    "rpm-ostree")
        $SUDO rpm-ostree cleanup -m
        ;;
    "transactional-update")
        $SUDO transactional-update cleanup
        ;;
    "nixos")
        echo "NixOS store optimize complete."
        ;;
esac

# Clean disabled Snap revisions
if command -v snap &> /dev/null; then
    echo -e "${BLUE}Checking for disabled Snap revisions to clean up...${NC}"
    DISABLED_SNAPS=$($SUDO snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}')
    if [ -n "$DISABLED_SNAPS" ]; then
        echo "$DISABLED_SNAPS" | while read -r snapname revision; do
            [ -n "$snapname" ] && [ -n "$revision" ] && $SUDO snap remove "$snapname" --revision="$revision" >/dev/null 2>&1 || true
        done
        echo -e "${GREEN}Disabled Snap revisions cleaned.${NC}"
    fi
fi
echo -e "${GREEN}Done!${NC}"

echo ""
echo -e "${MAGENTA}--- Systemd Service Status Audit ---${NC}"
if command -v systemctl &> /dev/null; then
    FAILED_UNITS=$(systemctl --failed --no-legend --plain 2>/dev/null || true)
    if [ -n "$FAILED_UNITS" ]; then
        echo -e "${RED}Warning: The following systemd units are in a failed state:${NC}"
        echo -e "${RED}$FAILED_UNITS${NC}"
    else
        echo -e "${GREEN}All systemd services are running normally.${NC}"
    fi
else
    echo -e "${YELLOW}systemctl not found. Skipping systemd service audit.${NC}"
fi

echo ""
echo -e "${MAGENTA}--- Distribution Upgrade Check ---${NC}"
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
echo -e "${MAGENTA}--- Clearing Old Logs ---${NC}"
if command -v journalctl &> /dev/null; then
    echo -e "${BLUE}Using journalctl to clear logs older than 10 days...${NC}"
    $SUDO journalctl --vacuum-time=10d 2>/dev/null || true
else
    echo -e "${YELLOW}Warning: 'journalctl' not found. Using 'find' to clear logs from /var/log.${NC}"
    echo -e "${BLUE}Clearing .log and .gz files older than 10 days from /var/log...${NC}"
    $SUDO find /var/log -type f -name "*.log" -mtime +10 -delete
    $SUDO find /var/log -type f -name "*.gz" -mtime +10 -delete
fi
echo -e "${GREEN}Old logs cleared.${NC}"

echo ""
echo -e "${MAGENTA}--- Firmware Update Check ---${NC}"
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
echo -e "${MAGENTA}--- Open Ports on System ---${NC}"

# Check for lsof and install if the user consents
LSOF_INSTALL_SUCCESS=false
if ! command -v lsof &> /dev/null; then
    echo -e "${YELLOW}'lsof' command not found.${NC}"
    
    RESPONSE_IS_YES=false
    if [ -t 1 ]; then
        echo -e "${YELLOW}Would you like to install 'lsof' to list open ports? (y/n)${NC}"
        read -r response < /dev/tty
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            RESPONSE_IS_YES=true
        fi
    else
        echo -e "${YELLOW}Non-interactive mode detected. Skipping 'lsof' installation.${NC}"
    fi

    if [ "$RESPONSE_IS_YES" = true ]; then
        echo -e "${BLUE}Attempting to install 'lsof'...${NC}"
        case "$PACKAGE_MANAGER" in
            "apt")
                $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y lsof
                ;;
            "dnf5")
                $SUDO dnf5 install -y lsof
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
            "zypper")
                $SUDO zypper --non-interactive in lsof
                ;;
            *)
                echo -e "${YELLOW}Automatic installation of 'lsof' is not supported for $PACKAGE_MANAGER.${NC}"
                ;;
        esac
        # Verify lsof installation
        if ! command -v lsof &> /dev/null; then
            echo -e "${RED}Failed to install 'lsof'. Falling back to alternative port listing tools.${NC}"
            LSOF_INSTALL_SUCCESS=false
        else
            LSOF_INSTALL_SUCCESS=true
        fi
    else
        LSOF_INSTALL_SUCCESS=false
    fi
else
    # lsof was found initially, confirm success
    LSOF_INSTALL_SUCCESS=true
fi

# Now, list the ports
if [ "$LSOF_INSTALL_SUCCESS" = true ]; then
    echo -e "${BLUE}Listing listening TCP and UDP ports with lsof...${NC}"
    $SUDO lsof -i -P -n | grep -E 'COMMAND|LISTEN|UDP'
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
