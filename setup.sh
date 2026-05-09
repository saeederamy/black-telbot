#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           BLACK TELBOT — setup.sh                          ║
# ║      develop by Saeed Eramy                                ║
# ║      https://github.com/saeederamy                         ║
# ╚══════════════════════════════════════════════════════════════╝

set -uo pipefail

# ──────────────────────────────────────────────────────────────
# CONSTANTS
# ──────────────────────────────────────────────────────────────
BOT_DIR="/root/black_telbot"
SERVICE="blacktelbot.service"
VENV="$BOT_DIR/venv"
PYTHON="$VENV/bin/python3"
PIP="$VENV/bin/pip"
GITHUB_BASE="https://raw.githubusercontent.com/saeederamy/black-telbot/main"
SETUP_URL="$GITHUB_BASE/setup.sh"
BOT_URL="$GITHUB_BASE/main_bot.py"
SELF_PATH="/usr/local/bin/black-telbot"

# ──────────────────────────────────────────────────────────────
# COLORS
# ──────────────────────────────────────────────────────────────
R='\033[0m'
BOLD='\033[1m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'

# ──────────────────────────────────────────────────────────────
# SELF-INSTALL
# ──────────────────────────────────────────────────────────────
_register_command() {
    [[ -x "$SELF_PATH" ]] && return 0
    echo -e "${YELLOW}Registering 'black-telbot' command...${R}"
    if [[ ! -f "$0" || "$0" == "bash" || "$0" == "-bash" ]]; then
        wget -q -O "$SELF_PATH" "$SETUP_URL" && chmod +x "$SELF_PATH" \
            && echo -e "${GREEN}  'black-telbot' command installed.${R}" \
            || echo -e "${YELLOW}  Could not install command — no worries.${R}"
    else
        cp "$(realpath "$0")" "$SELF_PATH" && chmod +x "$SELF_PATH" \
            && echo -e "${GREEN}  'black-telbot' command installed.${R}"
    fi
}
_register_command

# ──────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${BOLD}${WHITE}"
    echo "  ██████╗ ██╗      █████╗  ██████╗██╗  ██╗"
    echo "  ██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝"
    echo "  ██████╔╝██║     ███████║██║     █████╔╝ "
    echo "  ██╔══██╗██║     ██╔══██║██║     ██╔═██╗ "
    echo "  ██████╔╝███████╗██║  ██║╚██████╗██║  ██╗"
    echo "  ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"
    echo -e "${GRAY}       T E L B O T   M A N A G E R"
    echo -e "       develop by Saeed Eramy${R}"
    echo
}

status_line() {
    local svc_label svc_color
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        svc_label="● running"; svc_color="$GREEN"
    elif systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
        svc_label="○ stopped"; svc_color="$YELLOW"
    else
        svc_label="✗ not installed"; svc_color="$RED"
    fi

    local drv_label drv_color
    if grep -q "DRIVE_FOLDER_DISABLED" "$BOT_DIR/main_bot.py" 2>/dev/null; then
        drv_label="✗ not configured"; drv_color="$GRAY"
    else
        drv_label="✓ active"; drv_color="$GREEN"
    fi

    echo -e "  Service:      ${svc_color}${svc_label}${R}"
    echo -e "  Google Drive: ${drv_color}${drv_label}${R}"
    echo
}

ok()      { echo -e "${GREEN}  ✓ $*${R}"; }
warn()    { echo -e "${YELLOW}  ! $*${R}"; }
err()     { echo -e "${RED}  ✗ $*${R}"; }
info()    { echo -e "${GRAY}  $*${R}"; }
section() { echo -e "\n${BOLD}${CYAN}── $* ──${R}"; }

ask() {
    local _var="$1" _prompt="$2" _default="${3:-}" _val
    while true; do
        if [[ -n "$_default" ]]; then
            read -rp "  $_prompt [$_default]: " _val
            _val="${_val:-$_default}"
        else
            read -rp "  $_prompt: " _val
        fi
        [[ -n "$_val" ]] && break
        echo -e "  ${RED}Required.${R}"
    done
    printf -v "$_var" '%s' "$_val"
}

ask_yn() {
    local _ans
    read -rp "  $1 [y/N]: " _ans
    [[ "${_ans,,}" == "y" ]]
}

press_enter() { echo; read -rp "  Press Enter to continue..." _ || true; }
patch()       { sed -i "s|$2|$3|g" "$1"; }

# ──────────────────────────────────────────────────────────────
# SHARED INSTALL STEPS
# ──────────────────────────────────────────────────────────────
install_packages() {
    section "System packages"
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3 python3-pip python3-venv ffmpeg wget curl nano
    ok "Done."
}

setup_venv() {
    section "Python environment"
    mkdir -p "$BOT_DIR/downloads" "$BOT_DIR/creds"
    python3 -m venv "$VENV"
    "$PIP" install -q --upgrade pip
    "$PIP" install -q \
        "python-telegram-bot>=20.0" \
        yt-dlp \
        spotdl \
        google-api-python-client \
        google-auth-httplib2 \
        google-auth-oauthlib
    ok "Done."
}

download_bot() {
    section "Bot code"
    wget -q -O "$BOT_DIR/main_bot.py" "$BOT_URL" \
        || { err "Download failed — check your internet connection."; return 1; }
    ok "main_bot.py downloaded."
}

create_service() {
    section "Systemd service"
    sudo tee "/etc/systemd/system/$SERVICE" > /dev/null <<EOF
[Unit]
Description=Black Telbot — develop by Saeed Eramy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
ExecStart=$PYTHON $BOT_DIR/main_bot.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE" --quiet
    sudo systemctl restart "$SERVICE"
    sleep 2

    if systemctl is-active --quiet "$SERVICE"; then
        ok "Service is running!"
    else
        warn "Service did not start. Check logs with option [4]."
        sudo journalctl -u "$SERVICE" -n 15 --no-pager || true
    fi
}

# ──────────────────────────────────────────────────────────────
# GOOGLE DRIVE SETUP  (completely optional — separate action)
# ──────────────────────────────────────────────────────────────
action_drive_setup() {
    banner
    echo -e "${BOLD}  ── Google Drive Setup (optional) ──${R}\n"
    echo -e "  What you need:"
    echo -e "  ${CYAN}1.${R} Google Cloud Project with Drive API enabled"
    echo -e "  ${CYAN}2.${R} A Service Account with a JSON key file"
    echo -e "  ${CYAN}3.${R} A Drive folder shared with the Service Account (Editor)\n"
    echo -e "  Steps:"
    echo -e "  ${GRAY}-> console.cloud.google.com -> APIs -> Drive API -> Enable${R}"
    echo -e "  ${GRAY}-> Credentials -> Service Account -> Keys -> JSON${R}"
    echo -e "  ${GRAY}-> Drive folder -> Share -> paste Service Account email -> Editor${R}"
    echo -e "  ${GRAY}-> Folder ID = last segment of the folder URL${R}\n"

    if ! ask_yn "Set up Google Drive now?"; then
        show_menu; return
    fi

    if [[ ! -f "$BOT_DIR/main_bot.py" ]]; then
        err "Bot is not installed yet. Install first."
        press_enter; show_menu; return
    fi

    ask FOLDER_ID "Google Drive Folder ID"
    patch "$BOT_DIR/main_bot.py" "DRIVE_FOLDER_DISABLED" "$FOLDER_ID"
    ok "Folder ID saved."

    sudo systemctl restart "$SERVICE" 2>/dev/null || true
    sleep 1
    ok "Bot restarted — Drive buttons will now appear in the bot menu."
    press_enter; show_menu
}

action_drive_disable() {
    banner
    echo -e "${BOLD}  ── Disable Google Drive ──${R}\n"

    if [[ ! -f "$BOT_DIR/main_bot.py" ]]; then
        warn "Bot is not installed."; press_enter; show_menu; return
    fi

    if grep -q "DRIVE_FOLDER_DISABLED" "$BOT_DIR/main_bot.py" 2>/dev/null; then
        warn "Drive is already disabled."
        press_enter; show_menu; return
    fi

    if ! ask_yn "Disable Drive integration?"; then
        show_menu; return
    fi

    local current_id
    current_id=$(grep -oP 'DEFAULT_DRIVE_FOLDER_ID\s*=\s*"\K[^"]+' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "")
    [[ -n "$current_id" ]] && patch "$BOT_DIR/main_bot.py" "$current_id" "DRIVE_FOLDER_DISABLED"

    sudo systemctl restart "$SERVICE" 2>/dev/null || true
    sleep 1
    ok "Drive disabled — buttons removed from bot menu."
    press_enter; show_menu
}

# ──────────────────────────────────────────────────────────────
# INSTALL ACTIONS
# ──────────────────────────────────────────────────────────────
action_install_standard() {
    banner
    echo -e "${BOLD}  ── Standard Install (50 MB limit) ──${R}\n"
    echo -e "  You only need a Bot Token:"
    echo -e "  ${GRAY}-> @BotFather -> /newbot -> copy token${R}\n"

    ask BOT_TOKEN "Bot Token"

    install_packages
    setup_venv
    download_bot
    patch "$BOT_DIR/main_bot.py" "YOUR_BOT_TOKEN_HERE" "$BOT_TOKEN"
    create_service

    echo
    ok "Installation complete! Bot is live."
    echo
    if ask_yn "Set up Google Drive now? (optional)"; then
        action_drive_setup; return
    fi
    info "You can set up Drive later with option [5]."
    press_enter; show_menu
}

action_install_heavy() {
    banner
    echo -e "${BOLD}  ── Heavy Install (2 GB limit + Docker) ──${R}\n"
    echo -e "  You need:"
    echo -e "  ${GRAY}-> Bot Token  : @BotFather${R}"
    echo -e "  ${GRAY}-> API ID     : my.telegram.org${R}"
    echo -e "  ${GRAY}-> API Hash   : my.telegram.org${R}\n"

    ask BOT_TOKEN "Bot Token"
    ask API_ID    "Telegram API ID"
    ask API_HASH  "Telegram API Hash"

    install_packages

    section "Docker"
    sudo apt-get install -y -qq docker.io
    sudo systemctl enable --now docker --quiet
    sudo docker rm -f telegram-bot-api 2>/dev/null || true
    sudo docker run -d \
        --name telegram-bot-api \
        --restart always \
        -p 8081:8081 \
        -e TELEGRAM_API_ID="$API_ID" \
        -e TELEGRAM_API_HASH="$API_HASH" \
        aiogram/telegram-bot-api:latest
    ok "Local API server started on port 8081."

    setup_venv
    download_bot
    patch "$BOT_DIR/main_bot.py" "YOUR_BOT_TOKEN_HERE"  "$BOT_TOKEN"
    patch "$BOT_DIR/main_bot.py" "USE_LOCAL_API = False" "USE_LOCAL_API = True"
    create_service

    echo
    ok "Heavy install complete — 2 GB limit is active."
    echo
    if ask_yn "Set up Google Drive now? (optional)"; then
        action_drive_setup; return
    fi
    info "You can set up Drive later with option [5]."
    press_enter; show_menu
}

action_update() {
    banner
    echo -e "${BOLD}  ── Update ──${R}\n"

    if [[ ! -f "$BOT_DIR/main_bot.py" ]]; then
        warn "Bot is not installed yet."; press_enter; show_menu; return
    fi

    local token folder_id local_api
    token=$(grep -oP 'BOT_TOKEN\s*=\s*"\K[^"]+' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "")
    folder_id=$(grep -oP 'DEFAULT_DRIVE_FOLDER_ID\s*=\s*"\K[^"]+' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "")
    local_api=$(grep -oP 'USE_LOCAL_API\s*=\s*\K(True|False)' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "False")

    info "Downloading latest bot code..."
    wget -q -O "$BOT_DIR/main_bot.py" "$BOT_URL" \
        || { err "Download failed."; press_enter; show_menu; return; }

    [[ -n "$token" ]] && \
        patch "$BOT_DIR/main_bot.py" "YOUR_BOT_TOKEN_HERE" "$token"
    [[ -n "$folder_id" && "$folder_id" != "DRIVE_FOLDER_DISABLED" ]] && \
        patch "$BOT_DIR/main_bot.py" "DRIVE_FOLDER_DISABLED" "$folder_id"
    [[ "$local_api" == "True" ]] && \
        patch "$BOT_DIR/main_bot.py" "USE_LOCAL_API = False" "USE_LOCAL_API = True"

    info "Updating yt-dlp and spotdl..."
    "$PIP" install -q --upgrade yt-dlp spotdl
    ok "yt-dlp and spotdl updated."

    sudo systemctl restart "$SERVICE"
    sleep 1
    ok "Bot updated and restarted."
    press_enter; show_menu
}

action_logs() {
    banner
    echo -e "${BOLD}  ── Live Logs  (Ctrl+C to stop) ──${R}\n"
    sudo journalctl -u "$SERVICE" -f --no-pager || true
    show_menu
}

action_stop()    { sudo systemctl stop    "$SERVICE" && ok "Bot stopped."    || warn "Service not found."; press_enter; show_menu; }
action_restart() { sudo systemctl restart "$SERVICE" && ok "Bot restarted." || warn "Service not found."; press_enter; show_menu; }

action_wipe() {
    banner
    echo -e "${RED}${BOLD}  !! COMPLETE WIPE — cannot be undone !!${R}\n"
    echo -e "  Removes: bot files, service, Docker container, 'black-telbot' command.\n"
    read -rp "  Type YES to confirm: " confirm
    [[ "$confirm" != "YES" ]] && { warn "Aborted."; press_enter; show_menu; return; }

    sudo systemctl stop    "$SERVICE" 2>/dev/null || true
    sudo systemctl disable "$SERVICE" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$SERVICE"
    sudo systemctl daemon-reload
    sudo docker stop  telegram-bot-api 2>/dev/null || true
    sudo docker rm    telegram-bot-api 2>/dev/null || true
    sudo rm -rf "$BOT_DIR"
    sudo rm -f  "$SELF_PATH"
    ok "Complete wipe done."
    exit 0
}

# ──────────────────────────────────────────────────────────────
# MAIN MENU
# ──────────────────────────────────────────────────────────────
show_menu() {
    banner
    status_line
    echo -e "  ${BOLD}[1]${R} Install — Standard    ${GRAY}50 MB limit${R}"
    echo -e "  ${BOLD}[2]${R} Install — Heavy       ${GRAY}2 GB + Docker${R}"
    echo -e "  ${BOLD}[3]${R} Update                ${GRAY}code + yt-dlp + spotdl${R}"
    echo -e "  ${BOLD}[4]${R} Live logs"
    echo -e "  ${BOLD}[5]${R} Google Drive setup    ${CYAN}optional${R}"
    echo -e "  ${BOLD}[6]${R} Disable Drive"
    echo -e "  ${BOLD}[7]${R} Stop bot"
    echo -e "  ${BOLD}[8]${R} Restart bot"
    echo -e "  ${BOLD}[9]${R} Complete wipe         ${RED}danger${R}"
    echo -e "  ${BOLD}[0]${R} Exit"
    echo
    read -rp "  Select [0-9]: " choice
    echo

    case "${choice:-}" in
        1) action_install_standard ;;
        2) action_install_heavy    ;;
        3) action_update           ;;
        4) action_logs             ;;
        5) action_drive_setup      ;;
        6) action_drive_disable    ;;
        7) action_stop             ;;
        8) action_restart          ;;
        9) action_wipe             ;;
        0) exit 0                  ;;
        *) show_menu               ;;
    esac
}

show_menu
