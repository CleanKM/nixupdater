#!/bin/bash
# Written for the bash 3.2 that ships with macOS: no associative arrays, mapfile or GNU-only flags.

# Export robust PATH to ensure Homebrew/MacPorts are accessible in headless contexts
export PATH="/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_VERSION="1.7.0"

# --- Temporary Files and Cleanup on Exit ---
TEMP_DIR=$(mktemp -d) || { echo -e "${RED}Error: Could not create a temporary directory. Exiting.${NC}"; exit 1; }
SUDO_KEEP_ALIVE_PID=""
cleanup() {
    rm -rf "$TEMP_DIR"
    [ -n "$SUDO_KEEP_ALIVE_PID" ] && kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null
}
trap cleanup EXIT

# --- Helpers ---

# Prompts are read from /dev/tty, so the script is interactive whenever a terminal can be
# opened, even if stdout is piped (e.g. to tee). Under launchd/cron there is no terminal.
if ( : < /dev/tty ) 2>/dev/null; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# ask_yes_no "Question" [y|n]: returns 0 for yes. The default is used for an empty
# answer and in non-interactive mode.
ask_yes_no() {
    local prompt="$1" default="${2:-n}" hint="y/N" answer
    [ "$default" = "y" ] && hint="Y/n"
    if [ "$INTERACTIVE" != true ]; then
        echo -e "${YELLOW}${prompt} [${hint}] Non-interactive mode detected. Using default: ${default}.${NC}"
        [ "$default" = "y" ]
        return
    fi
    echo -n -e "${YELLOW}${prompt} [${hint}]: ${NC}"
    read -r answer < /dev/tty
    [[ "${answer:-$default}" =~ ^([yY][eE][sS]|[yY])$ ]]
}

# Steps that failed, listed in the final summary.
FAILURES=()

# finish_step "Description" exit_status: prints the outcome and remembers failures.
finish_step() {
    local desc="$1" status="$2"
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}$desc complete.${NC}"
    else
        FAILURES+=("$desc")
        echo -e "${RED}$desc failed (exit code $status).${NC}"
    fi
}

# Returns 0 if version $1 is newer than version $2 (numeric, dot-separated).
version_gt() {
    local IFS=.
    local -a a=($1) b=($2)
    local i x y
    for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
        x=${a[i]//[^0-9]/}
        y=${b[i]//[^0-9]/}
        x=$((10#${x:-0}))
        y=$((10#${y:-0}))
        ((x > y)) && return 0
        ((x < y)) && return 1
    done
    return 1
}

# Runs a command as the user who launched the script through sudo (Homebrew, mas and
# simulators belong to that user), or directly when not elevated.
run_as_user() {
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}

run_brew() {
    run_as_user brew "$@"
}

run_mas() {
    run_as_user mas "$@"
}

# Home directory of the real user, even when the script runs elevated through sudo.
USER_HOME="$HOME"
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    USER_HOME=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    [ -n "$USER_HOME" ] || USER_HOME="/Users/$SUDO_USER"
fi

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
GITHUB_RAW_URL="https://raw.githubusercontent.com/CleanKM/nixupdater/main/macos/update_macos.sh"

if [ "$SKIP_SELF_UPDATE" = true ]; then
    if [ "$NIXUPDATER_SKIP_CHECK" != "true" ]; then
        echo -e "${YELLOW}Skipping self-update check due to 'noupdate' argument.${NC}"
    fi
elif ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Warning: 'curl' not found. Cannot check for script updates.${NC}"
else
    TEMP_SCRIPT_PATH="$TEMP_DIR/update_macos.sh"
    # Download remote script with cache-busting and network timeouts
    if ! curl -sSfL --connect-timeout 5 --max-time 10 -H "Cache-Control: no-cache" "$GITHUB_RAW_URL?t=$(date +%s)" -o "$TEMP_SCRIPT_PATH"; then
        echo -e "${RED}Error: Failed to download remote script or network is down. Skipping self-update.${NC}"
    else
        REMOTE_VERSION=$(sed -n 's/^SCRIPT_VERSION="\(.*\)"$/\1/p' "$TEMP_SCRIPT_PATH" | head -n 1)

        if [ -z "$REMOTE_VERSION" ] || ! bash -n "$TEMP_SCRIPT_PATH" 2>/dev/null; then
            echo -e "${RED}Error: The downloaded script looks invalid. Skipping self-update.${NC}"
        elif version_gt "$REMOTE_VERSION" "$SCRIPT_VERSION"; then
            echo -e "${YELLOW}A new version of the script is available: v${SCRIPT_VERSION} -> v${REMOTE_VERSION}${NC}"
            if ask_yes_no "Do you want to update to the latest version?" n; then
                echo -e "${BLUE}Updating script...${NC}"
                # Keep the original file's permissions and owner (BSD stat syntax).
                chmod "$(stat -f %Lp "$SCRIPT_PATH")" "$TEMP_SCRIPT_PATH" 2>/dev/null
                chown "$(stat -f %u:%g "$SCRIPT_PATH")" "$TEMP_SCRIPT_PATH" 2>/dev/null
                if mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH"; then
                    echo -e "${GREEN}Script updated successfully. Relaunching...${NC}"
                    export NIXUPDATER_SKIP_CHECK=true
                    rm -rf "$TEMP_DIR" # exec skips the EXIT trap
                    exec bash "$SCRIPT_PATH" "$@" # Relaunch the updated script
                else
                    echo -e "${RED}Error: Failed to replace the script. Please update manually.${NC}"
                fi
            else
                echo -e "${YELLOW}Skipping script update.${NC}"
            fi
        elif version_gt "$SCRIPT_VERSION" "$REMOTE_VERSION"; then
            echo -e "${YELLOW}Local version (v${SCRIPT_VERSION}) is newer than the published one (v${REMOTE_VERSION}). Skipping self-update.${NC}"
        else
            echo -e "${GREEN}Script is already up to date (v${SCRIPT_VERSION}).${NC}"
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
fi

# --- Script Banner ---
echo -e "${CYAN}------------------------------------------${NC}"
echo -e "${CYAN}  macOS System Update Script - v${SCRIPT_VERSION}  ${NC}"
echo -e "${CYAN}------------------------------------------${NC}"
echo ""

# --- Spinner ---
# spinner pid: animates while the process runs, then returns its exit status.
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
    wait "$pid"
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
        if ask_yes_no "Do you want to install 'mas' using Homebrew to manage App Store apps?" n; then
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
RAW_SYS_UPDATES_FILE="$TEMP_DIR/softwareupdate.txt"
$SUDO softwareupdate -l > "$RAW_SYS_UPDATES_FILE" 2>&1 &
spinner $!
SYSTEM_UPDATES=""
if grep -q "Software Update found the following new or updated software:" "$RAW_SYS_UPDATES_FILE"; then
    echo -e "${GREEN}Done!${NC}"
    SYSTEM_UPDATES=$(awk '/Software Update found the following new or updated software:/{found=1; next} found' "$RAW_SYS_UPDATES_FILE")
elif grep -q "No new software available" "$RAW_SYS_UPDATES_FILE"; then
    echo -e "${GREEN}Done!${NC}"
else
    # Neither result was reported, e.g. no network or the update server was unreachable.
    echo -e "${RED}Failed!${NC}"
    tail -n 5 "$RAW_SYS_UPDATES_FILE"
    FAILURES+=("Checking for macOS updates")
fi

BREW_UPDATES=""
BREW_CASK_UPDATES=""
if [[ " ${PACKAGE_MANAGERS[*]} " =~ " brew " ]]; then
    echo -n -e "${BLUE}Checking for Homebrew updates...${NC}"
    run_brew update >/dev/null 2>&1 &
    if spinner $!; then
        echo -e "${GREEN}Done!${NC}"
    else
        echo -e "${RED}Failed! Continuing with possibly outdated Homebrew data.${NC}"
        FAILURES+=("Updating Homebrew")
    fi
    # Plain 'brew outdated' also lists casks, which are handled separately below.
    BREW_UPDATES=$(run_brew outdated --formula)
    BREW_CASK_UPDATES=$(run_brew outdated --cask)
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
    $SUDO port selfupdate >/dev/null 2>&1 &
    if spinner $!; then
        echo -e "${GREEN}Done!${NC}"
    else
        echo -e "${RED}Failed! Continuing with possibly outdated MacPorts data.${NC}"
        FAILURES+=("Updating MacPorts")
    fi
    # -q prints only the outdated port names, and nothing when everything is current.
    PORT_UPDATES=$(port -q outdated)
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

    # System Upgrade. Each update is confirmed individually so major OS upgrades are never
    # installed by accident. The loop reads from a process substitution rather than a pipe so
    # that REBOOT_NEEDED_AFTER_UPDATE survives the loop.
    if [ -n "$SYSTEM_UPDATES" ]; then
        while IFS= read -r line; do
            label=$(echo "$line" | sed -nE 's/^[[:space:]]*\*[[:space:]]*(Label:[[:space:]]*)?([^,]+).*/\2/p' | sed -E 's/[[:space:]]+$//')
            if [ -n "$label" ]; then
                if ask_yes_no "Do you want to install update: '$label'?" n; then
                    echo -e "${BLUE}Installing update: '$label'...${NC}"
                    $SUDO softwareupdate -i "$label"
                    STATUS=$?
                    finish_step "macOS update '$label'" $STATUS
                    if [ $STATUS -eq 0 ] && echo "$SYSTEM_UPDATES" | grep -A 2 -F "$line" | grep -q -i "restart"; then
                        REBOOT_NEEDED_AFTER_UPDATE=true
                    fi
                else
                    echo -e "${YELLOW}Skipping update: '$label'.${NC}"
                fi
            fi
        done < <(printf '%s\n' "$SYSTEM_UPDATES")
        echo -e "${GREEN}All macOS updates processed.${NC}"
    fi

    # Homebrew Upgrade
    if [[ " ${PACKAGE_MANAGERS[*]} " =~ " brew " ]]; then
        if [ -n "$BREW_UPDATES" ]; then
            echo -e "${BLUE}Upgrading Homebrew formulae...${NC}"
            run_brew upgrade --formula
            finish_step "Homebrew formulae upgrade" $?
        fi
        if [ -n "$BREW_CASK_UPDATES" ]; then
            echo -e "${BLUE}Upgrading Homebrew casks...${NC}"
            GREEDY_FLAG=""
            if ask_yes_no "Include casks with internal auto-updaters (greedy mode: --greedy)?" n; then
                GREEDY_FLAG="--greedy"
            fi
            run_brew upgrade --cask $GREEDY_FLAG
            finish_step "Homebrew cask upgrade" $?
        fi
    fi

    # App Store Upgrade
    if [ "$MAS_INSTALLED" = true ] && [ -n "$MAS_UPDATES" ]; then
        echo -e "${BLUE}Upgrading App Store applications...${NC}"
        # The spinner is not ideal here as mas can prompt for password
        run_mas upgrade
        finish_step "App Store upgrade" $?
    fi

    # MacPorts Upgrade
    if [[ " ${PACKAGE_MANAGERS[*]} " =~ " port " ]]; then
        if [ -n "$PORT_UPDATES" ]; then
            echo -e "${BLUE}Upgrading MacPorts packages...${NC}"
            $SUDO port upgrade outdated
            finish_step "MacPorts upgrade" $?
        fi
    fi
fi

echo ""
echo -e "${MAGENTA}--- Cleaning up system ---${NC}"

# Homebrew Cleanup (-s also scrubs the download cache)
if [[ " ${PACKAGE_MANAGERS[*]} " =~ " brew " ]]; then
    echo -e "${BLUE}Cleaning up Homebrew and clearing its cache...${NC}"
    run_brew autoremove && run_brew cleanup -s
    finish_step "Homebrew cleanup" $?
fi

# MacPorts Cleanup
if [[ " ${PACKAGE_MANAGERS[*]} " =~ " port " ]]; then
    echo -e "${BLUE}Cleaning up MacPorts...${NC}"
    $SUDO port uninstall inactive 2>/dev/null || true
    if [ "$INTERACTIVE" = true ]; then
        $SUDO port reclaim 2>/dev/null || true
    fi
    echo -e "${BLUE}Clearing MacPorts cache...${NC}"
    # 'installed', not 'all': 'all' would clean every port in the ports tree.
    $SUDO port clean --all installed
    finish_step "MacPorts cleanup" $?
fi

# Xcode Developer Cache Cleanup. /usr/bin/xcrun exists on every Mac as a stub that opens the
# developer tools installer, so check for real developer tools first.
HAS_SIMCTL=false
if xcode-select -p &> /dev/null && xcrun --find simctl &> /dev/null; then
    HAS_SIMCTL=true
fi
if [ -d "$USER_HOME/Library/Developer/Xcode/DerivedData" ] || [ "$HAS_SIMCTL" = true ]; then
    if ask_yes_no "Clean Xcode DerivedData & unavailable iOS Simulators?" n; then
        if [ -d "$USER_HOME/Library/Developer/Xcode/DerivedData" ]; then
            echo -e "${BLUE}Clearing Xcode DerivedData...${NC}"
            rm -rf "$USER_HOME/Library/Developer/Xcode/DerivedData"/* 2>/dev/null || true
        fi
        if [ "$HAS_SIMCTL" = true ]; then
            echo -e "${BLUE}Deleting unavailable iOS simulators...${NC}"
            # Simulators belong to the user, not root
            run_as_user xcrun simctl delete unavailable 2>/dev/null || true
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

# Native BSD Periodic Maintenance
echo -e "${BLUE}Running macOS native periodic maintenance (daily, weekly, monthly)...${NC}"
$SUDO periodic daily weekly monthly 2>/dev/null || true

# Flush DNS Resolver Cache
echo -e "${BLUE}Flushing DNS resolver cache...${NC}"
$SUDO dscacheutil -flushcache 2>/dev/null || true
$SUDO killall -HUP mDNSResponder 2>/dev/null || true
echo -e "${GREEN}System maintenance complete.${NC}"

echo ""
echo -e "${MAGENTA}--- LaunchAgent & LaunchDaemon Audit ---${NC}"
echo -e "${BLUE}Checking for broken plist symlinks...${NC}"
BROKEN_LAUNCH_LINKS=$(find "$USER_HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons -type l ! -exec test -e {} \; -print 2>/dev/null || true)
if [ -n "$BROKEN_LAUNCH_LINKS" ]; then
    echo -e "${YELLOW}Warning: Found broken launch agent/daemon symlinks:${NC}"
    echo -e "${CYAN}$BROKEN_LAUNCH_LINKS${NC}"
else
    echo -e "${GREEN}No broken launch symlinks found.${NC}"
fi


echo ""
echo -e "${MAGENTA}--- Clearing Old Logs ---${NC}"
if ask_yes_no "Do you want to clear .log and .gz files older than 10 days from /var/log and ~/Library/Logs?" n; then
    echo -e "${BLUE}Clearing .log and .gz files older than 10 days from /var/log and ~/Library/Logs...${NC}"
    $SUDO find /var/log -type f \( -name "*.log" -o -name "*.gz" \) -mtime +10 -delete
    if [ -d "$USER_HOME/Library/Logs" ]; then
        find "$USER_HOME/Library/Logs" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +10 -delete
    fi
    echo -e "${GREEN}Old logs cleared.${NC}"
else
    echo -e "${YELLOW}Skipping log cleanup.${NC}"
fi

# --- Open Ports on System ---
echo ""
echo -e "${MAGENTA}--- Open Ports on System ---${NC}"

# Check for lsof
if command -v lsof &> /dev/null; then
    echo -e "${BLUE}Listing listening TCP and UDP ports with lsof...${NC}"
    $SUDO lsof -i -P -n | grep -E 'COMMAND|LISTEN|UDP'
elif command -v netstat &> /dev/null; then
    echo -e "${BLUE}lsof not found. Using 'netstat' to list listening TCP and UDP ports...${NC}"
    # UDP sockets have no LISTEN state, so match them separately.
    $SUDO netstat -anv | grep -E '^Proto|LISTEN|^udp'
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
if [ ${#FAILURES[@]} -eq 0 ]; then
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN} All updates completed successfully! ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    exit 0
fi

echo -e "${RED}=====================================${NC}"
echo -e "${RED} Finished with ${#FAILURES[@]} failed step(s):${NC}"
printf "${RED} - %s${NC}\n" "${FAILURES[@]}"
echo -e "${RED}=====================================${NC}"
exit 1
