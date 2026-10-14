#!/bin/bash

# Make sure system tools are found in headless contexts (cron, minimal sudo PATH). User-writable
# directories such as Linuxbrew's are deliberately left out: this script runs as root, and
# anything placed there would shadow system commands.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_VERSION="1.12.0"

# --- Temporary Files (removed on exit) ---
TEMP_DIR=$(mktemp -d) || { echo -e "${RED}Error: Could not create a temporary directory. Exiting.${NC}"; exit 1; }
trap 'rm -rf "$TEMP_DIR"' EXIT

# --- Helpers ---

# Prompts are read from /dev/tty, so the script is interactive whenever a terminal can be
# opened, even if stdout is piped (e.g. to tee). Under cron there is no terminal.
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

# Returns 0 if version $1 is newer than version $2.
version_gt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

# Runs a command as the user who launched the script through sudo, with that user's tool
# directories on PATH (sudo would otherwise use its own secure_path). It runs from / so the
# user can always read the working directory.
run_as_user() {
    if [ "$EUID" -eq 0 ] && [ -n "$REAL_USER" ]; then
        (cd / && sudo -u "$REAL_USER" -H env PATH="$REAL_USER_PATH" "$@")
    else
        "$@"
    fi
}

# Returns 0 if the invoking user has the given command on their PATH.
user_has_command() {
    run_as_user sh -c 'command -v "$1"' _ "$1" > /dev/null 2>&1
}

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
GITHUB_RAW_URL="https://raw.githubusercontent.com/CleanKM/nixupdater/main/linux/update.sh"

if [ "$SKIP_SELF_UPDATE" = true ]; then
    if [ "$NIXUPDATER_SKIP_CHECK" != "true" ]; then
        echo -e "${YELLOW}Skipping self-update check due to 'noupdate' argument.${NC}"
    fi
elif ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Warning: 'curl' not found. Cannot check for script updates.${NC}"
else
    TEMP_SCRIPT_PATH="$TEMP_DIR/update.sh"
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
                # Keep the original file's permissions and owner.
                chmod --reference="$SCRIPT_PATH" "$TEMP_SCRIPT_PATH" 2>/dev/null
                chown --reference="$SCRIPT_PATH" "$TEMP_SCRIPT_PATH" 2>/dev/null
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
if [ "$EUID" -ne 0 ]; then
    echo -e "${BLUE}This script requires sudo privileges to run.${NC}"

    if id -Gn "${SUDO_USER:-$USER}" 2>/dev/null | grep -qE '\b(sudo|wheel)\b'; then
        if ask_yes_no "You are in the 'sudo' group. Do you want to relaunch this script with sudo?" n; then
            echo -e "${BLUE}Relaunching with sudo...${NC}"
            rm -rf "$TEMP_DIR" # exec skips the EXIT trap
            exec sudo NIXUPDATER_SKIP_CHECK=true bash "$SCRIPT_PATH" "$@" # Relaunch the script with sudo
        fi
        echo -e "${RED}Sudo privileges declined. Exiting.${NC}"
    else
        echo -e "${RED}You are not currently root or in the 'sudo' group. Exiting.${NC}"
    fi
    exit 1
fi
echo -e "${GREEN}Sudo privileges obtained.${NC}"

# The user who launched the script through sudo (empty when run directly as root). User-level
# tools (Flatpak --user, pipx, cargo, AUR helpers) are run as this user.
REAL_USER=""
REAL_HOME=""
REAL_USER_PATH="$PATH"
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
    REAL_USER_PATH="$REAL_HOME/.local/bin:$REAL_HOME/.cargo/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"
fi

# Homebrew refuses to run as root, so it runs as the owner of the installation. It is found by
# absolute path instead of through PATH (see the PATH note at the top).
BREW_BIN=""
BREW_USER=""
for candidate in /home/linuxbrew/.linuxbrew/bin/brew ${REAL_HOME:+"$REAL_HOME/.linuxbrew/bin/brew"}; do
    if [ -x "$candidate" ]; then
        BREW_BIN="$candidate"
        BREW_USER=$(stat -c %U "$(readlink -f "$BREW_BIN")")
        break
    fi
done

run_brew() {
    (cd / && sudo -u "$BREW_USER" -H "$BREW_BIN" "$@")
}

# --- Script Banner ---
echo -e "${CYAN}------------------------------------------${NC}"
echo -e "${CYAN}  Linux System Update Script - v${SCRIPT_VERSION}  ${NC}"
echo -e "${CYAN}------------------------------------------${NC}"
echo ""

# --- Docker Helpers ---
declare -A CONTAINER_NAMES CONTAINER_PROJECTS COMPOSE_STOPPED_IDS

# Reads the running containers into STANDALONE_IDS, COMPOSE_IDS and COMPOSE_PROJECTS (unique
# project names), plus CONTAINER_NAMES / CONTAINER_PROJECTS keyed by container ID. One plain
# 'docker ps' call, so it works on engines without label!= filter support.
load_running_containers() {
    STANDALONE_IDS=()
    COMPOSE_IDS=()
    COMPOSE_PROJECTS=()
    CONTAINER_NAMES=()
    CONTAINER_PROJECTS=()
    local id name project
    while IFS='|' read -r id name project; do
        [ -z "$id" ] && continue
        CONTAINER_NAMES[$id]="$name"
        if [ -n "$project" ]; then
            CONTAINER_PROJECTS[$id]="$project"
            COMPOSE_IDS+=("$id")
            [[ " ${COMPOSE_PROJECTS[*]} " == *" $project "* ]] || COMPOSE_PROJECTS+=("$project")
        else
            STANDALONE_IDS+=("$id")
        fi
    done < <(docker ps --format '{{.ID}}|{{.Names}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null)
}

# Runs a Compose command on a project by name. It runs from / so a compose file in the current
# directory is never picked up; without one, Compose works from the containers' labels.
compose_project() {
    local project="$1"
    shift
    (cd / && docker compose -p "$project" "$@")
}

# Starts a stopped Compose project, falling back to starting its containers directly.
start_compose_project() {
    local project="$1"
    compose_project "$project" start && return 0
    echo -e "${YELLOW}Compose could not start '$project'; starting its containers directly.${NC}"
    [ -n "${COMPOSE_STOPPED_IDS[$project]}" ] || return 1
    # The ID list is word-split on purpose
    docker start ${COMPOSE_STOPPED_IDS[$project]} >/dev/null
}

# --- Docker Container Status ---
if command -v docker &> /dev/null; then
    load_running_containers
    if [ ${#STANDALONE_IDS[@]} -gt 0 ] || [ ${#COMPOSE_IDS[@]} -gt 0 ]; then
        echo -e "${MAGENTA}--- Running Docker Containers ---${NC}"
        if [ ${#COMPOSE_IDS[@]} -gt 0 ]; then
            echo -e "${CYAN}Docker Compose Containers:${NC}"
            for ID in "${COMPOSE_IDS[@]}"; do
                echo -e "${CYAN}${CONTAINER_NAMES[$ID]} ($ID) [Compose Project: ${CONTAINER_PROJECTS[$ID]}]${NC}"
            done
        fi
        if [ ${#STANDALONE_IDS[@]} -gt 0 ]; then
            echo -e "${CYAN}Standalone Containers (docker run):${NC}"
            for ID in "${STANDALONE_IDS[@]}"; do
                echo -e "${CYAN}${CONTAINER_NAMES[$ID]} ($ID)${NC}"
            done
        fi
        echo ""
    fi
fi

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
        "void")
            PACKAGE_MANAGER="xbps"
            ;;
        "gentoo")
            PACKAGE_MANAGER="emerge"
            ;;
        "solus")
            PACKAGE_MANAGER="eopkg"
            ;;
        "clear-linux-os")
            PACKAGE_MANAGER="swupd"
            ;;
        "guix")
            PACKAGE_MANAGER="guix"
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
            elif echo "$ID_LIKE" | grep -qE '\b(void)\b'; then
                PACKAGE_MANAGER="xbps"
            elif echo "$ID_LIKE" | grep -qE '\b(gentoo)\b'; then
                PACKAGE_MANAGER="emerge"
            elif command -v apt-get &> /dev/null; then
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
            elif command -v xbps-install &> /dev/null; then
                PACKAGE_MANAGER="xbps"
                echo -e "${GREEN}Found 'xbps'. Proceeding.${NC}"
            elif command -v emerge &> /dev/null; then
                PACKAGE_MANAGER="emerge"
                echo -e "${GREEN}Found 'emerge'. Proceeding.${NC}"
            elif command -v eopkg &> /dev/null; then
                PACKAGE_MANAGER="eopkg"
                echo -e "${GREEN}Found 'eopkg'. Proceeding.${NC}"
            elif command -v swupd &> /dev/null; then
                PACKAGE_MANAGER="swupd"
                echo -e "${GREEN}Found 'swupd'. Proceeding.${NC}"
            elif command -v guix &> /dev/null; then
                PACKAGE_MANAGER="guix"
                echo -e "${GREEN}Found 'guix'. Proceeding.${NC}"
            else
                echo -e "${RED}Could not find a supported package manager. Exiting.${NC}"
                exit 1
            fi
            ;;
    esac
fi
echo -e "${BLUE}Using package manager: ${GREEN}$PACKAGE_MANAGER${NC}"

# Check for Arch AUR helpers. They refuse to run as root, so they are only used when the
# script was launched through sudo by a regular user.
AUR_HELPER=""
if [ "$PACKAGE_MANAGER" = "pacman" ] && [ -n "$REAL_USER" ]; then
    if user_has_command yay; then
        AUR_HELPER="yay"
        echo -e "${BLUE}Found Arch AUR helper: ${GREEN}yay${NC}"
    elif user_has_command paru; then
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
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update >/dev/null 2>&1
        ;;
    "dnf5" | "dnf")
        ;;
    "pacman")
        if command -v checkupdates &> /dev/null; then
            :
        else
            pacman -Sy >/dev/null 2>&1
        fi
        ;;
    "apk")
        apk update >/dev/null 2>&1
        ;;
    "zypper")
        zypper refresh >/dev/null 2>&1
        ;;
    "xbps")
        xbps-install -S >/dev/null 2>&1
        ;;
    "emerge")
        emerge --sync >/dev/null 2>&1
        ;;
    "eopkg")
        eopkg update-repo >/dev/null 2>&1
        ;;
    "swupd")
        # 'swupd check-update' runs in the listing step below
        ;;
    "guix")
        guix pull --check >/dev/null 2>&1 || true
        ;;
    "rpm-ostree")
        rpm-ostree upgrade --check > "$TEMP_DIR/ostree-check" 2>&1
        ;;
    "transactional-update" | "nixos")
        ;;
esac
) &
if spinner $!; then
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${RED}Failed!${NC}"
    FAILURES+=("Checking for system updates")
    echo -e "${YELLOW}Continuing with possibly outdated package information.${NC}"
fi

# Security Advisory Audit Check
if command -v dnf5 &> /dev/null; then
    SEC_INFO=$(dnf5 advisory summary 2>/dev/null | grep -iE 'security|critical|important' || true)
    [ -n "$SEC_INFO" ] && echo -e "${YELLOW}Security Advisories (DNF5):${NC}\n${CYAN}$SEC_INFO${NC}\n"
elif command -v dnf &> /dev/null; then
    SEC_INFO=$(dnf updateinfo summary 2>/dev/null | grep -iE 'security|critical|important' || true)
    [ -n "$SEC_INFO" ] && echo -e "${YELLOW}Security Advisories (DNF):${NC}\n${CYAN}$SEC_INFO${NC}\n"
elif command -v arch-audit &> /dev/null; then
    SEC_INFO=$(arch-audit 2>/dev/null || true)
    [ -n "$SEC_INFO" ] && echo -e "${YELLOW}Vulnerabilities Detected (arch-audit):${NC}\n${RED}$SEC_INFO${NC}\n"
fi

SYSTEM_UPDATES=$(
case "$PACKAGE_MANAGER" in
    ("apt")
        # --with-new-pkgs lets kernel updates (which come as new packages) through
        apt-get --just-print --with-new-pkgs upgrade 2>/dev/null | grep "^Inst "
        ;;
    ("dnf5" | "dnf")
        # Exit code 100 means updates are available; -q leaves only the package list.
        DNF_OUTPUT=$("$PACKAGE_MANAGER" -q check-update 2>/dev/null)
        [ $? -eq 100 ] && echo "$DNF_OUTPUT" | awk 'NF'
        ;;
    ("pacman")
        if command -v checkupdates &> /dev/null; then
            checkupdates 2>/dev/null
        else
            pacman -Qu 2>/dev/null
        fi
        # checkupdates and pacman only see repository packages
        [ -n "$AUR_HELPER" ] && run_as_user "$AUR_HELPER" -Qua 2>/dev/null
        ;;
    ("apk")
        apk list --upgradeable 2>/dev/null
        ;;
    ("zypper")
        zypper list-updates 2>/dev/null | grep -E '^v \|'
        ;;
    ("xbps")
        xbps-install -un 2>/dev/null
        ;;
    ("emerge")
        emerge -pv --update --deep --newuse @world 2>/dev/null | grep '^\[ebuild'
        ;;
    ("eopkg")
        eopkg list-upgrades 2>/dev/null | grep -vi "no packages to upgrade"
        ;;
    ("swupd")
        swupd check-update 2>/dev/null
        ;;
    ("guix")
        echo "Guix packages will be upgraded during the upgrade phase."
        ;;
    ("rpm-ostree")
        if grep -q "AvailableUpdate" "$TEMP_DIR/ostree-check" 2>/dev/null; then
            echo "OSTree update available:"
            sed -n '/AvailableUpdate/,$p' "$TEMP_DIR/ostree-check" | tail -n +2
        elif ! grep -qi "No updates available" "$TEMP_DIR/ostree-check" 2>/dev/null; then
            # Unrecognized output: run the upgrade anyway, it does nothing if there is no update.
            echo "Could not determine whether an OSTree update is available; the upgrade will check."
        fi
        ;;
    ("transactional-update")
        echo "Transactional updates will be checked during the upgrade phase."
        ;;
    ("nixos")
        echo "NixOS channel/flake updates will be evaluated during the upgrade phase."
        ;;
esac
)

FLATPAK_SYSTEM_UPDATES=""
FLATPAK_USER_UPDATES=""
if command -v flatpak &> /dev/null; then
    echo -n -e "${BLUE}Checking for Flatpak updates...${NC}"
    FLATPAK_SYSTEM_UPDATES=$(flatpak remote-ls --system --updates 2>/dev/null)
    if [ -n "$REAL_USER" ]; then
        FLATPAK_USER_UPDATES=$(run_as_user flatpak remote-ls --user --updates 2>/dev/null)
    fi
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${YELLOW}Flatpak not found. Skipping Flatpak check.${NC}"
fi

SNAP_UPDATES=""
if command -v snap &> /dev/null; then
    echo -n -e "${BLUE}Checking for Snap updates...${NC}"
    SNAP_OUTPUT_FILE="$TEMP_DIR/snap-updates"
    snap refresh --list > "$SNAP_OUTPUT_FILE" 2>&1 &
    spinner $!
    SNAP_UPDATES=$(grep -v "All snaps are up to date." "$SNAP_OUTPUT_FILE" | tail -n +2)
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${YELLOW}Snap not found. Skipping Snap check.${NC}"
fi

BREW_UPDATES=""
if [ -z "$BREW_BIN" ]; then
    echo -e "${YELLOW}Homebrew not found. Skipping Homebrew check.${NC}"
elif [ "$BREW_USER" = "root" ]; then
    echo -e "${YELLOW}Homebrew is owned by root and refuses to run as root. Skipping Homebrew check.${NC}"
    BREW_BIN=""
else
    echo -n -e "${BLUE}Checking for Homebrew updates (as $BREW_USER)...${NC}"
    run_brew update --quiet >/dev/null 2>&1
    BREW_UPDATES=$(run_brew outdated 2>/dev/null)
    echo -e "${GREEN}Done!${NC}"
fi
echo ""

# --- List Updates and Upgrade ---
if [ -z "$SYSTEM_UPDATES" ] && [ -z "$FLATPAK_SYSTEM_UPDATES" ] && [ -z "$FLATPAK_USER_UPDATES" ] && [ -z "$SNAP_UPDATES" ] && [ -z "$BREW_UPDATES" ]; then
    echo -e "${GREEN}=========================${NC}"
    echo -e "${GREEN} Your system is up to date. ${NC}"
    echo -e "${GREEN}=========================${NC}"
fi


# --- Docker Pre-Update Check ---
DOCKER_STANDALONE_TO_RESTART=()
DOCKER_COMPOSE_TO_RESTART=()
if command -v docker &> /dev/null; then
    ALL_UPDATES_TEXT="${SYSTEM_UPDATES}${SNAP_UPDATES}${BREW_UPDATES}"
    # Fedora ships Docker as moby-engine; runc and containerd updates also restart the daemon.
    if echo "$ALL_UPDATES_TEXT" | grep -qiE '\b(docker|containerd|moby|runc)\b'; then
        echo -e "${YELLOW}Docker-related update found.${NC}"
        load_running_containers

        if [ ${#COMPOSE_PROJECTS[@]} -gt 0 ] || [ ${#STANDALONE_IDS[@]} -gt 0 ]; then
            echo -e "${YELLOW}Docker containers are currently running, but a Docker/containerd update is available.${NC}"
            echo -e "${YELLOW}It is recommended to stop them before updating. Do you want to:${NC}"
            echo -e "${CYAN}[1] Stop ALL running containers automatically${NC}"
            echo -e "${CYAN}[2] Select which containers/projects to stop individually${NC}"
            echo -e "${CYAN}[3] Skip stopping containers${NC}"

            STOP_MODE="1"
            if [ "$INTERACTIVE" = true ]; then
                echo -n -e "${YELLOW}Enter your choice [1-3] (default 1): ${NC}"
                read -r response < /dev/tty
                if [[ "$response" == "2" ]]; then STOP_MODE="2"; fi
                if [[ "$response" == "3" ]]; then STOP_MODE="3"; fi
            else
                echo -e "${YELLOW}Non-interactive mode detected. Defaulting to [1] (Stop ALL).${NC}"
            fi

            if [ "$STOP_MODE" != "3" ]; then
                SELECTED_COMPOSE=("${COMPOSE_PROJECTS[@]}")
                SELECTED_STANDALONE=("${STANDALONE_IDS[@]}")

                if [ "$STOP_MODE" == "2" ]; then
                    SELECTED_COMPOSE=()
                    SELECTED_STANDALONE=()
                    if [ ${#COMPOSE_PROJECTS[@]} -gt 0 ]; then
                        echo -e "${BLUE}--- Select Compose Projects ---${NC}"
                        for PROJECT in "${COMPOSE_PROJECTS[@]}"; do
                            ask_yes_no "Stop Compose project [$PROJECT]?" n && SELECTED_COMPOSE+=("$PROJECT")
                        done
                    fi
                    if [ ${#STANDALONE_IDS[@]} -gt 0 ]; then
                        echo -e "${BLUE}--- Select Standalone Containers ---${NC}"
                        for ID in "${STANDALONE_IDS[@]}"; do
                            ask_yes_no "Stop standalone container ${CONTAINER_NAMES[$ID]} ($ID)?" n && SELECTED_STANDALONE+=("$ID")
                        done
                    fi
                fi

                echo -e "${BLUE}Stopping selected Docker containers prior to update...${NC}"

                # Stop Compose projects. Container IDs are kept as a fallback for restarting.
                if [ ${#SELECTED_COMPOSE[@]} -gt 0 ]; then
                    echo -e "${CYAN}Stopping Docker Compose projects:${NC}"
                    for PROJECT in "${SELECTED_COMPOSE[@]}"; do
                        COMPOSE_STOPPED_IDS[$PROJECT]=$(docker ps -q --filter "label=com.docker.compose.project=$PROJECT" | xargs)
                        echo -e " ${YELLOW}-> docker compose -p $PROJECT stop${NC}"
                        if ! compose_project "$PROJECT" stop; then
                            echo -e "${YELLOW}Compose could not stop '$PROJECT'; stopping its containers directly.${NC}"
                            # The ID list is word-split on purpose
                            [ -n "${COMPOSE_STOPPED_IDS[$PROJECT]}" ] && docker stop ${COMPOSE_STOPPED_IDS[$PROJECT]} >/dev/null
                        fi
                        DOCKER_COMPOSE_TO_RESTART+=("$PROJECT")
                    done
                fi

                # Stop standalone containers
                if [ ${#SELECTED_STANDALONE[@]} -gt 0 ]; then
                    echo -e "${CYAN}Stopping standalone containers:${NC}"
                    docker stop "${SELECTED_STANDALONE[@]}" >/dev/null 2>&1 || true
                    DOCKER_STANDALONE_TO_RESTART=("${SELECTED_STANDALONE[@]}")
                fi

                # Verify stop - only check targeted containers
                REMAINING_TARGETED=()
                for ID in "${SELECTED_STANDALONE[@]}"; do
                    [ -n "$(docker ps -q --filter "id=$ID" 2>/dev/null)" ] && REMAINING_TARGETED+=("${CONTAINER_NAMES[$ID]}")
                done
                for PROJECT in "${SELECTED_COMPOSE[@]}"; do
                    [ -n "$(docker ps -q --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null)" ] && REMAINING_TARGETED+=("compose:$PROJECT")
                done
                if [ ${#REMAINING_TARGETED[@]} -eq 0 ]; then
                    echo -e "${GREEN}Confirmed: All targeted containers are stopped.${NC}"
                else
                    echo -e "${YELLOW}Warning: Some targeted containers may still be running: ${REMAINING_TARGETED[*]}${NC}"
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
upgrade_system() {
    case "$PACKAGE_MANAGER" in
        "apt")
            local apt_opts=(-y --with-new-pkgs)
            if [ "$INTERACTIVE" != true ]; then
                # Keep existing config files rather than stopping at dpkg's prompt.
                apt_opts+=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
            fi
            DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get upgrade "${apt_opts[@]}"
            ;;
        "dnf5")
            dnf5 upgrade -y
            ;;
        "dnf")
            dnf upgrade -y
            ;;
        "pacman")
            if [ -n "$AUR_HELPER" ]; then
                echo -e "${BLUE}Upgrading system and AUR packages using $AUR_HELPER...${NC}"
                run_as_user "$AUR_HELPER" -Syu --noconfirm
            else
                pacman -Syu --noconfirm
            fi
            ;;
        "apk")
            apk upgrade
            ;;
        "zypper")
            if grep -q -i "tumbleweed" /etc/os-release 2>/dev/null; then
                zypper --non-interactive dup
            else
                zypper --non-interactive up
            fi
            ;;
        "xbps")
            xbps-install -Syu -y
            ;;
        "emerge")
            emerge -uDNv @world
            ;;
        "eopkg")
            eopkg upgrade -y
            ;;
        "swupd")
            swupd update
            ;;
        "guix")
            guix pull && guix package -u
            ;;
        "rpm-ostree")
            if command -v bootc &> /dev/null && ! grep -q -E -e "LockLayering=false" /etc/rpm-ostreed.conf 2>/dev/null; then
                bootc upgrade
            else
                rpm-ostree upgrade
            fi
            ;;
        "transactional-update")
            transactional-update dup
            ;;
        "nixos")
            if [ -f /etc/nixos/flake.nix ] || [ -f /etc/nixos/flake.lock ]; then
                echo -e "${BLUE}Updating NixOS Flake...${NC}"
                nix flake update --flake /etc/nixos && nixos-rebuild switch --upgrade
            else
                nix-channel --update && nixos-rebuild switch --upgrade
            fi
            ;;
    esac
}

if [ -n "$SYSTEM_UPDATES" ] || [ -n "$FLATPAK_SYSTEM_UPDATES" ] || [ -n "$FLATPAK_USER_UPDATES" ] || [ -n "$SNAP_UPDATES" ] || [ -n "$BREW_UPDATES" ]; then
    echo -e "${YELLOW}--- Pending Updates ---${NC}"
    if [ -n "$SYSTEM_UPDATES" ]; then
        echo -e "${CYAN}--- System Updates ---${NC}"
        echo "$SYSTEM_UPDATES"
    fi
    if [ -n "$FLATPAK_SYSTEM_UPDATES" ]; then
        echo -e "${CYAN}--- Flatpak Updates (system) ---${NC}"
        echo "$FLATPAK_SYSTEM_UPDATES"
    fi
    if [ -n "$FLATPAK_USER_UPDATES" ]; then
        echo -e "${CYAN}--- Flatpak Updates (user: $REAL_USER) ---${NC}"
        echo "$FLATPAK_USER_UPDATES"
    fi
    if [ -n "$SNAP_UPDATES" ]; then
        echo -e "${CYAN}--- Snap Updates ---${NC}"
        echo "$SNAP_UPDATES"
    fi
    if [ -n "$BREW_UPDATES" ]; then
        echo -e "${CYAN}--- Homebrew Updates ---${NC}"
        echo "$BREW_UPDATES"
    fi
    echo ""
    echo -e "${MAGENTA}Starting automatic upgrade...${NC}"

    # System Upgrade
    if [ -n "$SYSTEM_UPDATES" ]; then
        echo -e "${BLUE}Upgrading system packages...${NC}"
        upgrade_system
        finish_step "System upgrade" $?
    fi

    # Flatpak Upgrade
    if [ -n "$FLATPAK_SYSTEM_UPDATES" ]; then
        echo -e "${BLUE}Upgrading system Flatpak packages...${NC}"
        flatpak update --system -y
        finish_step "System Flatpak upgrade" $?
        echo -e "${BLUE}Removing unused Flatpak runtimes...${NC}"
        flatpak uninstall --system --unused -y 2>/dev/null || true
    fi
    if [ -n "$FLATPAK_USER_UPDATES" ]; then
        echo -e "${BLUE}Upgrading Flatpak packages for $REAL_USER...${NC}"
        run_as_user flatpak update --user -y
        finish_step "User Flatpak upgrade" $?
        run_as_user flatpak uninstall --user --unused -y 2>/dev/null || true
    fi

    # Snap Upgrade
    if [ -n "$SNAP_UPDATES" ]; then
        echo -e "${BLUE}Upgrading Snap packages...${NC}"
        snap refresh
        finish_step "Snap upgrade" $?
    fi

    # Homebrew Upgrade
    if [ -n "$BREW_UPDATES" ]; then
        echo -e "${BLUE}Upgrading Homebrew packages (as $BREW_USER)...${NC}"
        run_brew upgrade
        finish_step "Homebrew upgrade" $?
        run_brew cleanup
    fi
fi

# --- Docker Post-Update Restart ---
# Runs whenever containers were stopped, even if an upgrade step failed.
RESTART_COMPOSE=("${DOCKER_COMPOSE_TO_RESTART[@]}")
RESTART_STANDALONE=("${DOCKER_STANDALONE_TO_RESTART[@]}")

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
        echo -e "${CYAN}[$idx] Standalone: ${CONTAINER_NAMES[$ID]} ($ID)${NC}"
        item_map[$idx]="standalone|$i"
        ((idx++))
    done

    echo -e "${GREEN}[a] Restart all remaining items automatically${NC}"
    echo -e "${YELLOW}[d] Done (leave remaining items stopped)${NC}"

    if [ "$INTERACTIVE" != true ]; then
        echo -e "${YELLOW}Non-interactive mode. Auto-restarting all.${NC}"
        ans="a"
    else
        echo -n -e "${YELLOW}Select an option to restart it now: ${NC}"
        read -r ans < /dev/tty
    fi

    if [[ "$ans" == "a" || "$ans" == "A" ]]; then
        # Bulk start remaining
        if [ ${#RESTART_COMPOSE[@]} -gt 0 ]; then
            echo -e "${BLUE}Restarting remaining Compose projects...${NC}"
            for PROJECT in "${RESTART_COMPOSE[@]}"; do
                echo -e " ${CYAN}-> docker compose -p $PROJECT start${NC}"
                start_compose_project "$PROJECT" || FAILURES+=("Restarting Compose project '$PROJECT'")
            done
        fi
        if [ ${#RESTART_STANDALONE[@]} -gt 0 ]; then
            echo -e "${BLUE}Restarting remaining standalone Docker containers...${NC}"
            docker start "${RESTART_STANDALONE[@]}" >/dev/null || FAILURES+=("Restarting standalone containers")
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
            PROJECT="${RESTART_COMPOSE[$arr_idx]}"
            echo -e "${BLUE}Starting Compose Project: $PROJECT${NC}"
            if start_compose_project "$PROJECT"; then
                echo -e "${GREEN}Item started!${NC}"
            else
                echo -e "${RED}Failed to start Compose project '$PROJECT'.${NC}"
                FAILURES+=("Restarting Compose project '$PROJECT'")
            fi
            unset 'RESTART_COMPOSE[$arr_idx]'
            # Rebuild array to fix indices
            RESTART_COMPOSE=("${RESTART_COMPOSE[@]}")
        elif [ "$item_type" == "standalone" ]; then
            ID="${RESTART_STANDALONE[$arr_idx]}"
            echo -e "${BLUE}Starting Standalone Container: ${CONTAINER_NAMES[$ID]} ($ID)${NC}"
            if docker start "$ID" >/dev/null; then
                echo -e "${GREEN}Item started!${NC}"
            else
                echo -e "${RED}Failed to start container ${CONTAINER_NAMES[$ID]}.${NC}"
                FAILURES+=("Restarting container '${CONTAINER_NAMES[$ID]}'")
            fi
            unset 'RESTART_STANDALONE[$arr_idx]'
            RESTART_STANDALONE=("${RESTART_STANDALONE[@]}")
        fi
    else
        echo -e "${RED}Invalid selection. Please try again.${NC}"
    fi
done

# --- Developer Package Managers Upgrade (pipx, cargo, npm) ---
# These have no cheap "anything outdated?" check, so they run on every invocation.
if user_has_command pipx; then
    echo -e "${BLUE}Upgrading pipx packages...${NC}"
    run_as_user pipx upgrade-all
    finish_step "pipx upgrade" $?
fi

if run_as_user cargo install-update --help &> /dev/null; then
    echo -e "${BLUE}Upgrading Cargo packages...${NC}"
    run_as_user cargo install-update -a
    finish_step "Cargo upgrade" $?
fi

if command -v npm &> /dev/null; then
    echo -e "${BLUE}Upgrading global npm packages...${NC}"
    npm update -g
    finish_step "npm global upgrade" $?
fi

echo ""
echo -e "${MAGENTA}--- Reboot & Service Restart Check ---${NC}"
# Service Restart Audit (Services running outdated in-memory libraries)
if command -v dnf5 &> /dev/null; then
    SERVICES_TO_RESTART=$(dnf5 needs-restarting -s 2>/dev/null || true)
    [ -n "$SERVICES_TO_RESTART" ] && echo -e "${YELLOW}Services running outdated libraries (consider restarting):${NC}\n${CYAN}$SERVICES_TO_RESTART${NC}"
elif command -v dnf &> /dev/null && command -v needs-restarting &> /dev/null; then
    SERVICES_TO_RESTART=$(dnf needs-restarting -s 2>/dev/null || true)
    [ -n "$SERVICES_TO_RESTART" ] && echo -e "${YELLOW}Services running outdated libraries (consider restarting):${NC}\n${CYAN}$SERVICES_TO_RESTART${NC}"
elif command -v needrestart &> /dev/null; then
    echo -e "${BLUE}Auditing running services with needrestart...${NC}"
    needrestart -b 2>/dev/null || true
fi

REBOOT_STATUS="no" # yes | no | unknown
REBOOT_REASON=""
case "$PACKAGE_MANAGER" in
    "apt")
        if [ -f /var/run/reboot-required ]; then
            REBOOT_STATUS="yes"
            REBOOT_REASON=$(cat /var/run/reboot-required.pkgs 2>/dev/null)
        fi
        ;;
    "dnf5" | "dnf")
        # The output is checked rather than the exit code, which is also non-zero when the
        # needs-restarting plugin is missing.
        if command -v dnf5 &> /dev/null; then
            NEEDS_RESTARTING=$(dnf5 needs-restarting -r 2>&1)
        elif command -v needs-restarting &> /dev/null; then
            NEEDS_RESTARTING=$(needs-restarting -r 2>&1)
        else
            NEEDS_RESTARTING=$(dnf needs-restarting -r 2>&1)
        fi
        if echo "$NEEDS_RESTARTING" | grep -qi "reboot is required"; then
            REBOOT_STATUS="yes"
        elif ! echo "$NEEDS_RESTARTING" | grep -qi "no core libraries or services have been updated"; then
            REBOOT_STATUS="unknown"
            REBOOT_REASON="'needs-restarting' is not available (install dnf5-plugins, or dnf-plugins-core on dnf4)."
        fi
        ;;
    "zypper")
        # Exit code 102 means a reboot is needed.
        zypper needs-rebooting >/dev/null 2>&1
        case $? in
            102) REBOOT_STATUS="yes" ;;
            0) ;;
            *)
                if zypper ps -s 2>/dev/null | grep -qi "reboot"; then
                    REBOOT_STATUS="yes"
                fi
                ;;
        esac
        ;;
    "rpm-ostree")
        if rpm-ostree status | grep -q -E "(pending)|Staged: yes"; then
            REBOOT_STATUS="yes"
        fi
        ;;
    "transactional-update")
        if [ -n "$SYSTEM_UPDATES" ]; then
            REBOOT_STATUS="yes"
        fi
        ;;
    "pacman" | "apk")
        # A kernel upgrade removes the running kernel's modules. /lib/modules covers Alpine,
        # where modules are not under /usr/lib.
        if ! compgen -G "/lib/modules/*/kernel" > /dev/null; then
            REBOOT_STATUS="unknown"
            REBOOT_REASON="No kernel modules found in /lib/modules (container or custom kernel?)."
        elif [ ! -d "/lib/modules/$(uname -r)/kernel" ]; then
            REBOOT_STATUS="yes"
            REBOOT_REASON="The running kernel ($(uname -r)) has been replaced by an update."
        fi
        ;;
    "nixos")
        for component in kernel initrd kernel-modules; do
            if [ "$(readlink -f "/run/booted-system/$component")" != "$(readlink -f "/run/current-system/$component")" ]; then
                REBOOT_STATUS="yes"
                REBOOT_REASON="The booted system's $component differs from the current system."
                break
            fi
        done
        ;;
    *)
        REBOOT_STATUS="unknown"
        ;;
esac

case "$REBOOT_STATUS" in
    "yes")
        echo -e "${YELLOW}A system reboot is required to complete the updates.${NC}"
        [ -n "$REBOOT_REASON" ] && echo -e "${YELLOW}Reason:${NC}\n${CYAN}$REBOOT_REASON${NC}"
        ;;
    "unknown")
        echo -e "${YELLOW}Could not determine whether a reboot is required. Please reboot if the kernel or core libraries were updated.${NC}"
        [ -n "$REBOOT_REASON" ] && echo -e "${YELLOW}$REBOOT_REASON${NC}"
        ;;
    *)
        echo -e "${GREEN}No reboot is required.${NC}"
        ;;
esac

echo ""
echo -e "${MAGENTA}--- Cleaning up system ---${NC}"

# Autoremove unnecessary packages. On Debian/Ubuntu this also removes old kernels, keeping
# the running one plus the newest and previous ones as fallbacks.
autoremove_packages() {
    case "$PACKAGE_MANAGER" in
        "apt")
            DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
            ;;
        "dnf5")
            dnf5 autoremove -y
            ;;
        "dnf")
            dnf autoremove -y
            ;;
        "pacman")
            local orphans
            mapfile -t orphans < <(pacman -Qdtq)
            if [ ${#orphans[@]} -gt 0 ]; then
                pacman -Rns --noconfirm "${orphans[@]}"
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
        "xbps")
            xbps-remove -Oo 2>/dev/null || true
            vkpurge rm all 2>/dev/null || true
            ;;
        "emerge")
            emerge --depclean 2>/dev/null || true
            eclean-dist 2>/dev/null || true
            ;;
        "eopkg")
            eopkg rmo 2>/dev/null || true
            ;;
        "swupd")
            swupd clean 2>/dev/null || true
            ;;
        "guix")
            guix gc 2>/dev/null || true
            ;;
        "rpm-ostree")
            echo "rpm-ostree images are managed atomically. No autoremove required."
            ;;
        "transactional-update")
            echo "Transactional snapshots will be cleaned up during the next phase."
            ;;
        "nixos")
            nix-collect-garbage -d || return
            echo -e "${BLUE}Optimizing Nix store...${NC}"
            nix-store --optimise
            ;;
    esac
}

clean_package_cache() {
    case "$PACKAGE_MANAGER" in
        "apt")
            apt-get clean
            ;;
        "dnf5")
            dnf5 clean all
            ;;
        "dnf")
            dnf clean all
            ;;
        "pacman")
            if command -v paccache &> /dev/null; then
                echo -e "${BLUE}Cleaning pacman cache retaining last 3 versions (paccache)...${NC}"
                paccache -r >/dev/null 2>&1 || true
            else
                pacman -Sc --noconfirm
            fi
            ;;
        "apk")
            apk cache purge 2>/dev/null || apk cache clean
            ;;
        "zypper")
            zypper clean -a
            ;;
        "rpm-ostree")
            rpm-ostree cleanup -m
            ;;
        "transactional-update")
            transactional-update cleanup
            ;;
        "nixos")
            echo "NixOS store optimize complete."
            ;;
    esac
}

echo -e "${BLUE}Removing unnecessary packages...${NC}"
autoremove_packages
finish_step "Removing unnecessary packages" $?

echo -e "${BLUE}Clearing package cache...${NC}"
clean_package_cache
finish_step "Clearing package cache" $?

# Clean disabled Snap revisions
if command -v snap &> /dev/null; then
    echo -e "${BLUE}Checking for disabled Snap revisions to clean up...${NC}"
    DISABLED_SNAPS=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}')
    if [ -n "$DISABLED_SNAPS" ]; then
        echo "$DISABLED_SNAPS" | while read -r snapname revision; do
            [ -n "$snapname" ] && [ -n "$revision" ] && snap remove "$snapname" --revision="$revision" >/dev/null 2>&1 || true
        done
        echo -e "${GREEN}Disabled Snap revisions cleaned.${NC}"
    fi
fi

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
            UPGRADE_CHECK=$(do-release-upgrade -c 2>&1)
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
            DIST_UPGRADE_CHECK=$(apt-get -s dist-upgrade 2>&1)

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
    "dnf5" | "dnf")
        echo -e "${BLUE}For Fedora-based systems, distribution upgrades are done using the 'system-upgrade' command.${NC}"
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
echo -e "${MAGENTA}--- Storage Health Check ---${NC}"
if command -v zpool &> /dev/null; then
    echo -e "${BLUE}Checking ZFS pool health...${NC}"
    ZPOOL_HEALTH=$(zpool status -x 2>/dev/null || true)
    echo -e "${CYAN}$ZPOOL_HEALTH${NC}"
fi
if command -v btrfs &> /dev/null; then
    echo -e "${BLUE}Checking Btrfs filesystem status...${NC}"
    btrfs device stats / 2>/dev/null || true
fi

echo ""
echo -e "${MAGENTA}--- Clearing Old Logs & Coredumps ---${NC}"
if ask_yes_no "Do you want to clear logs and crash dumps older than 10 days?" n; then
    if command -v journalctl &> /dev/null; then
        echo -e "${BLUE}Using journalctl to clear logs older than 10 days or exceeding 500MB...${NC}"
        journalctl --vacuum-time=10d --vacuum-size=500M 2>/dev/null || true
    else
        echo -e "${YELLOW}Warning: 'journalctl' not found. Using 'find' to clear logs from /var/log.${NC}"
        echo -e "${BLUE}Clearing .log and .gz files older than 10 days from /var/log...${NC}"
        find /var/log -type f -name "*.log" -mtime +10 -delete
        find /var/log -type f -name "*.gz" -mtime +10 -delete
    fi

    # Clean coredumps & crash reports
    if [ -d /var/crash ] || [ -d /var/lib/systemd/coredump ]; then
        echo -e "${BLUE}Clearing crash dumps older than 10 days...${NC}"
        find /var/crash /var/lib/systemd/coredump -type f -mtime +10 -delete 2>/dev/null || true
    fi
    echo -e "${GREEN}Old logs cleared.${NC}"
else
    echo -e "${YELLOW}Skipping log and crash dump cleanup.${NC}"
fi

echo ""
echo -e "${MAGENTA}--- Firmware Update Check ---${NC}"
if command -v fwupdmgr &> /dev/null; then
    echo -n -e "${BLUE}Refreshing firmware metadata...${NC}"
    fwupdmgr refresh --force >/dev/null 2>&1 &
    spinner $!
    echo -e "${GREEN}Done!${NC}"

    echo -e "${BLUE}Checking for firmware updates...${NC}"
    FIRMWARE_UPDATES=$(fwupdmgr get-updates 2>&1)

    if echo "$FIRMWARE_UPDATES" | grep -q "No updatable devices" || echo "$FIRMWARE_UPDATES" | grep -q "No updates available"; then
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

# ss ships with iproute2 on virtually every system; lsof is only needed without it.
PORT_TOOL=""
if command -v ss &> /dev/null; then
    PORT_TOOL="ss"
elif command -v lsof &> /dev/null; then
    PORT_TOOL="lsof"
else
    echo -e "${YELLOW}Neither 'ss' nor 'lsof' found.${NC}"
    if ask_yes_no "Would you like to install 'lsof' to list open ports?" n; then
        echo -e "${BLUE}Attempting to install 'lsof'...${NC}"
        case "$PACKAGE_MANAGER" in
            "apt")
                DEBIAN_FRONTEND=noninteractive apt-get install -y lsof
                ;;
            "dnf5")
                dnf5 install -y lsof
                ;;
            "dnf")
                dnf install -y lsof
                ;;
            "pacman")
                pacman -S --noconfirm lsof
                ;;
            "apk")
                apk add lsof
                ;;
            "zypper")
                zypper --non-interactive in lsof
                ;;
            *)
                echo -e "${YELLOW}Automatic installation of 'lsof' is not supported for $PACKAGE_MANAGER.${NC}"
                ;;
        esac
        # Verify lsof installation
        if command -v lsof &> /dev/null; then
            PORT_TOOL="lsof"
        else
            echo -e "${RED}Failed to install 'lsof'. Falling back to alternative port listing tools.${NC}"
        fi
    fi
fi

if [ "$PORT_TOOL" = "ss" ]; then
    echo -e "${BLUE}Listing listening TCP and UDP ports with ss...${NC}"
    ss -tulpn
elif [ "$PORT_TOOL" = "lsof" ]; then
    echo -e "${BLUE}Listing listening TCP and UDP ports with lsof...${NC}"
    lsof -i -P -n | grep -E 'COMMAND|LISTEN|UDP'
elif command -v netstat &> /dev/null; then
    echo -e "${BLUE}ss and lsof not found. Using 'netstat' to list listening TCP and UDP ports...${NC}"
    netstat -tulpn
else
    echo -e "${RED}Error: Could not find ss, lsof, or netstat. Cannot display open ports.${NC}"
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
