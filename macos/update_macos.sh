#!/bin/bash

# Export robust PATH to ensure Homebrew/MacPorts are accessible in headless contexts
export PATH="/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

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

# Helper function to run Homebrew as the non-root user when elevated
run_brew() {
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" brew "$@"
    else
        brew "$@"
    fi
}

# Helper function to run App Store CLI (mas) as the non-root user when elevated
run_mas() {
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" mas "$@"
    else
        mas "$@"
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

SCRIPT_VERSION="1.5.0"

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
    GITHUB_RAW_URL="https://raw.githubusercontent.com/CleanKM/nixupdater/main/macos/update_macos.sh"
TEMP_SCRIPT_PATH=$(mktemp)
trap 'rm -f "$TEMP_SCRIPT_PATH"' EXIT

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Warning: 'curl' not found. Cannot check for script updates.${NC}"
else
    # Download remote script with cache-busting and network timeouts
    CACHE_BUSTER=$(date +%s)
    if ! curl -sSfL --connect-timeout 5 --max-time 10 -H "Cache-Control: no-cache" "$GITHUB_RAW_URL?t=$CACHE_BUSTER" -o "$TEMP_SCRIPT_PATH"; then
        echo -e "${RED}Error: Failed to download remote script or network is down. Skipping self-update.${NC}"
        rm -f "$TEMP_SCRIPT_PATH"
    else
        LOCAL_CHECKSUM=$(get_sha256 "$SCRIPT_PATH")
        REMOTE_CHECKSUM=$(get_sha256 "$TEMP_SCRIPT_PATH")

        if [ -z "$LOCAL_CHECKSUM" ] || [ -z "$REMOTE_CHECKSUM" ]; then
            echo -e "${RED}Error: Checksum utility not found or failed. Skipping self-update.${NC}"
            rm -f "$TEMP_SCRIPT_PATH"
        elif [ "$LOCAL_CHECKSUM" != "$REMOTE_CHECKSUM" ]; then
            echo -e "${YELLOW}A new version of the script is available!${NC}"
            RESPONSE_IS_YES=false
            if [ -t 1 ]; then
                echo -e "${YELLOW}Do you want to update to the latest version? (y/n)${NC}"
                read -r response < /dev/tty
                if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    RESPONSE_IS_YES=true
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
fi

# --- Sudo check and prompt ---
SUDO=''
if [ "$EUID" -ne 0 ]; then
    SUDO='sudo'
    echo -e "${BLUE}This script requires sudo privileges to run.${NC}"
    if ! sudo -v; then
        echo -e "${RED}Failed to obtain sudo privileges. Exiting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Sudo privileges obtained.${NC}"
    # Keep-alive: update existing sudo time stamp if set, otherwise do nothing.
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_KEEP_ALIVE_PID=$!
    trap 'kill $SUDO_KEEP_ALIVE_PID 2>/dev/null' EXIT
fi

# --- Script Banner ---
echo -e "${CYAN}------------------------------------------${NC}"
echo -e "${CYAN}  macOS System Update Script - v${SCRIPT_VERSION}  ${NC}"
echo -e "${CYAN}------------------------------------------${NC}"
echo ""

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

# --- macOS Detection ---
echo -n -e "${BLUE}Detecting macOS version...${NC}"
if [ "$(uname)" == "Darwin" ]; then
    OS_VERSION=$(sw_vers -productVersion)
    OS_NAME=$(sw_vers -productName)
    echo -e "${GREEN}Done! ($OS_NAME $OS_VERSION)${NC}"
else
    echo -e "${RED}This script is intended for macOS only.${NC}"
    exit 1
fi

# --- Package Manager Detection ---
PACKAGE_MANAGERS=()
if command -v brew &> /dev/null; then
    PACKAGE_MANAGERS+=("brew")
fi
if command -v port &> /dev/null; then
    PACKAGE_MANAGERS+=("port")
fi

if [ ${#PACKAGE_MANAGERS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No supported package manager (Homebrew or MacPorts) found.${NC}"
    echo -e "${YELLOW}Please install Homebrew (https://brew.sh) or MacPorts (https://www.macports.org).${NC}"
    # exit 1 # Commented out to allow system updates to run
else
    echo -e "${BLUE}Using package managers: ${GREEN}${PACKAGE_MANAGERS[*]}${NC}"
fi

# --- App Store CLI (mas) Detection ---
MAS_INSTALLED=false
if command -v mas &> /dev/null; then
    MAS_INSTALLED=true
    echo -e "${BLUE}Found Mac App Store CLI: ${GREEN}mas${NC}"
else
    echo -e "${YELLOW}Mac App Store CLI 'mas' not found.${NC}"
    if [[ " ${PACKAGE_MANAGERS[*]} " =~ " brew " ]]; then
        RESPONSE_IS_YES=false
        if [ -t 1 ]; then
            echo -e "${YELLOW}Do you want to install 'mas' using Homebrew to manage App Store apps? (y/n)${NC}"
            read -r response < /dev/tty
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                RESPONSE_IS_YES=true
            fi
        else
            echo -e "${YELLOW}Non-interactive mode detected. Skipping 'mas' installation.${NC}"
        fi

        if [ "$RESPONSE_IS_YES" = true ]; then
            echo -e "${BLUE}Installing 'mas'...${NC}"
            run_brew install mas
            if command -v mas &> /dev/null; then
                MAS_INSTALLED=true
                echo -e "${GREEN}'mas' installed successfully.${NC}"
            else
                echo -e "${RED}Failed to install 'mas'. Skipping App Store updates.${NC}"
            fi
        else
            echo -e "${YELLOW}Skipping 'mas' installation. App Store apps will not be updated.${NC}"
        fi
    fi
fi
echo ""

# --- Update Checking ---
echo -n -e "${BLUE}Checking for macOS updates...${NC}"
RAW_SYS_UPDATES_FILE=$(mktemp)
( $SUDO softwareupdate -l > "$RAW_SYS_UPDATES_FILE" 2>&1 ) &
SYS_UPDATES_PID=$!
spinner $SYS_UPDATES_PID
wait $SYS_UPDATES_PID
echo -e "${GREEN}Done!${NC}"

SYSTEM_UPDATES=$(awk '/Software Update found the following new or updated software:/{found=1; next} found' "$RAW_SYS_UPDATES_FILE")
rm -f "$RAW_SYS_UPDATES_FILE"

BREW_UPDATES=""
BREW_CASK_UPDATES=""
if [[ " ${PACKAGE_MANAGERS[*]} " =~ " brew " ]]; then
    echo -n -e "${BLUE}Checking for Homebrew updates...${NC}"
    (run_brew update >/dev/null 2>&1) &
    spinner $!
    BREW_UPDATES=$(run_brew outdated)
    BREW_CASK_UPDATES=$(run_brew outdated --cask)
    echo -e "${GREEN}Done!${NC}"
fi

MAS_UPDATES=""
if [ "$MAS_INSTALLED" = true ]; then
    echo -n -e "${BLUE}Checking for App Store updates...${NC}"
    MAS_UPDATES=$(run_mas outdated)
    echo -e "${GREEN}Done!${NC}"
fi

PORT_UPDATES=""
if [[ " ${PACKAGE_MANAGERS[*]} " =~ " port " ]]; then
    echo -n -e "${BLUE}Checking for MacPorts updates...${NC}"
    ($SUDO port selfupdate >/dev/null 2>&1) &
    spinner $!
    PORT_UPDATES=$(port outdated)
    echo -e "${GREEN}Done!${NC}"
fi
echo ""

# --- List Updates and Upgrade ---
if [ -z "$SYSTEM_UPDATES" ] && [ -z "$BREW_UPDATES" ] && [ -z "$BREW_CASK_UPDATES" ] && [ -z "$PORT_UPDATES" ] && [ -z "$MAS_UPDATES" ]; then
    echo -e "${GREEN}=========================${NC}"
    echo -e "${GREEN} Your system is up to date. ${NC}"
    echo -e "${GREEN}=========================${NC}"
fi

# --- Upgrade ---
REBOOT_NEEDED_AFTER_UPDATE=false
if [ -n "$SYSTEM_UPDATES" ] || [ -n "$BREW_UPDATES" ] || [ -n "$BREW_CASK_UPDATES" ] || [ -n "$PORT_UPDATES" ] || [ -n "$MAS_UPDATES" ]; then
    echo -e "${YELLOW}--- Pending Updates ---${NC}"
    if [ -n "$SYSTEM_UPDATES" ]; then
        echo -e "${CYAN}--- macOS Updates ---${NC}"
        echo "$SYSTEM_UPDATES"
    fi
    if [ -n "$BREW_UPDATES" ]; then
        echo -e "${CYAN}--- Homebrew Formulae Updates ---${NC}"
        echo "$BREW_UPDATES"
    fi
    if [ -n "$BREW_CASK_UPDATES" ]; then
        echo -e "${CYAN}--- Homebrew Cask Updates ---${NC}"
        echo "$BREW_CASK_UPDATES"
    fi
    if [ -n "$MAS_UPDATES" ]; then
        echo -e "${CYAN}--- App Store Updates ---${NC}"
        echo "$MAS_UPDATES"
    fi
    if [ -n "$PORT_UPDATES" ]; then
        echo -e "${CYAN}--- MacPorts Updates ---${NC}"
        echo "$PORT_UPDATES"
    fi
    echo ""
    echo -e "${MAGENTA}Starting automatic upgrade...${NC}"

    # System Upgrade
    if [ -n "$SYSTEM_UPDATES" ]; then
        echo "$SYSTEM_UPDATES" | while IFS= read -r line; do
            label=$(echo "$line" | sed -nE 's/^[[:space:]]*\*[[:space:]]*(Label:[[:space:]]*)?([^,]+).*/\2/p' | xargs)
            if [ -n "$label" ]; then
                RESPONSE_IS_YES=false
                if [ -t 1 ]; then
                    echo -e "${YELLOW}Do you want to install update: ${BLUE}'$label'${YELLOW}? (y/n)${NC}"
                    read -r response_individual < /dev/tty
                    if [[ "$response_individual" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                        RESPONSE_IS_YES=true
                    fi
                else
                    echo -e "${YELLOW}Non-interactive mode detected. Skipping installation of update: '$label'.${NC}"
                fi

                if [ "$RESPONSE_IS_YES" = true ]; then
                    echo -e "${BLUE}Installing update: '$label'...${NC}"
                    $SUDO softwareupdate -i "$label"
                    if echo "$SYSTEM_UPDATES" | grep -A 2 -F "$line" | grep -q -i "restart"; then
                        REBOOT_NEEDED_AFTER_UPDATE=true
                    fi
                    echo -e "${GREEN}Update '$label' complete.${NC}"
                else
                    echo -e "${YELLOW}Skipping update: '$label'.${NC}"
                fi
            fi
        done
        echo -e "${GREEN}All macOS updates processed.${NC}"
    fi

    # Homebrew Upgrade
    if [[ " ${PACKAGE_MANAGERS[*]} " =~ " brew " ]]; then
        if [ -n "$BREW_UPDATES" ]; then
            echo -e "${BLUE}Upgrading Homebrew formulae...${NC}"
            run_brew upgrade
            echo -e "${GREEN}Homebrew formulae upgrade complete.${NC}"
        fi
        if [ -n "$BREW_CASK_UPDATES" ]; then
            echo -e "${BLUE}Upgrading Homebrew casks...${NC}"
            GREEDY_FLAG=""
            if [ -t 1 ]; then
                echo -e "${YELLOW}Include casks with internal auto-updaters (greedy mode: --greedy)? (y/N)${NC}"
                read -r response < /dev/tty
                if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    GREEDY_FLAG="--greedy"
                fi
            fi
            run_brew upgrade --cask $GREEDY_FLAG
            echo -e "${GREEN}Homebrew cask upgrade complete.${NC}"
        fi
    fi

    # App Store Upgrade
    if [ "$MAS_INSTALLED" = true ] && [ -n "$MAS_UPDATES" ]; then
        echo -e "${BLUE}Upgrading App Store applications...${NC}"
        # The spinner is not ideal here as mas can prompt for password
        run_mas upgrade
        echo -e "${GREEN}App Store upgrade complete.${NC}"
    fi

    # MacPorts Upgrade
    if [[ " ${PACKAGE_MANAGERS[*]} " =~ " port " ]]; then
        if [ -n "$PORT_UPDATES" ]; then
            echo -e "${BLUE}Upgrading MacPorts packages...${NC}"
            $SUDO port upgrade outdated
            echo -e "${GREEN}MacPorts upgrade complete.${NC}"
        fi
    fi
fi

echo ""
echo -e "${MAGENTA}--- Cleaning up system ---${NC}"

# Homebrew Cleanup
if [[ " ${PACKAGE_MANAGERS[*]} " =~ " brew " ]]; then
    echo -e "${BLUE}Cleaning up Homebrew...${NC}"
    run_brew cleanup
    run_brew autoremove
    echo -e "${GREEN}Done!${NC}"
fi

# MacPorts Cleanup
if [[ " ${PACKAGE_MANAGERS[*]} " =~ " port " ]]; then
    echo -e "${BLUE}Cleaning up MacPorts...${NC}"
    $SUDO port uninstall inactive 2>/dev/null || true
    if [ -t 1 ]; then
        $SUDO port reclaim 2>/dev/null || true
    fi
    echo -e "${GREEN}Done!${NC}"
fi

# Clean package cache
if [[ " ${PACKAGE_MANAGERS[*]} " =~ " brew " ]]; then
    echo -e "${BLUE}Clearing Homebrew cache...${NC}"
    run_brew cleanup -s
    echo -e "${GREEN}Done!${NC}"
fi

if [[ " ${PACKAGE_MANAGERS[*]} " =~ " port " ]]; then
    echo -e "${BLUE}Clearing MacPorts cache...${NC}"
    $SUDO port clean --all all
    echo -e "${GREEN}Done!${NC}"
fi

# Xcode Developer Cache Cleanup
USER_HOME="${HOME}"
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
fi
if [ -d "$USER_HOME/Library/Developer/Xcode/DerivedData" ] || command -v xcrun &> /dev/null; then
    RESPONSE_IS_YES=false
    if [ -t 1 ]; then
        echo -e "${YELLOW}Clean Xcode DerivedData & unavailable iOS Simulators? (y/N)${NC}"
        read -r response < /dev/tty
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            RESPONSE_IS_YES=true
        fi
    fi
    if [ "$RESPONSE_IS_YES" = true ]; then
        if [ -d "$USER_HOME/Library/Developer/Xcode/DerivedData" ]; then
            echo -e "${BLUE}Clearing Xcode DerivedData...${NC}"
            rm -rf "$USER_HOME/Library/Developer/Xcode/DerivedData"/* 2>/dev/null || true
        fi
        if command -v xcrun &> /dev/null; then
            echo -e "${BLUE}Deleting unavailable iOS simulators...${NC}"
            xcrun simctl delete unavailable 2>/dev/null || true
        fi
        echo -e "${GREEN}Developer caches cleaned.${NC}"
    fi
fi

# Time Machine Snapshot Thinning if free disk space is low (<20GB)
FREE_SPACE_GB=$(df -g / 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$FREE_SPACE_GB" ] && [ "$FREE_SPACE_GB" -lt 20 ] 2>/dev/null; then
    echo -e "${YELLOW}Low disk space detected (<20GB). Thinning local Time Machine snapshots...${NC}"
    $SUDO tmutil thinLocalSnapshots / 10000000000 4 2>/dev/null || true
fi


echo ""
echo -e "${MAGENTA}--- Clearing Old Logs ---${NC}"
echo -e "${BLUE}Clearing .log and .gz files older than 10 days from /var/log and ~/Library/Logs...${NC}"
$SUDO find /var/log -type f \( -name "*.log" -o -name "*.gz" \) -mtime +10 -delete
USER_HOME="${HOME}"
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
fi
if [ -d "$USER_HOME/Library/Logs" ]; then
    find "$USER_HOME/Library/Logs" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +10 -delete
fi
echo -e "${GREEN}Old logs cleared.${NC}"

# --- Open Ports on System ---
echo ""
echo -e "${MAGENTA}--- Open Ports on System ---${NC}"

# Check for lsof
if command -v lsof &> /dev/null; then
    echo -e "${BLUE}Listing listening TCP and UDP ports with lsof...${NC}"
    $SUDO lsof -i -P -n | grep -E 'COMMAND|LISTEN|UDP'
elif command -v netstat &> /dev/null; then
    echo -e "${BLUE}lsof not found. Using 'netstat' to list listening TCP and UDP ports...${NC}"
    $SUDO netstat -anv | grep LISTEN
else
    echo -e "${RED}Error: Could not find lsof or netstat. Cannot display open ports.${NC}"
fi

# --- Reboot Check ---
echo ""
echo -e "${MAGENTA}--- Reboot Check ---${NC}"
if [ "$REBOOT_NEEDED_AFTER_UPDATE" = true ]; then
    echo -e "${YELLOW}A system reboot is required to complete the macOS updates.${NC}"
else
    echo -e "${GREEN}No reboot is required for the updates that were installed.${NC}"
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN} All updates completed successfully! ${NC}"
echo -e "${GREEN}=====================================${NC}"
exit 0