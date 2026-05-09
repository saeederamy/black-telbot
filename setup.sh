#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           BLACK TELBOT — setup.sh                          ║
# ║      develop by Saeed Eramy                                ║
# ║      https://github.com/saeederamy                         ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# CONSTANTS
# ──────────────────────────────────────────────────────────────
BOT_DIR="/root/black_telbot"
SERVICE="blacktelbot.service"
VENV="$BOT_DIR/venv"
PYTHON="$VENV/bin/python3"
PIP="$VENV/bin/pip"
RAW_URL="https://raw.githubusercontent.com/saeederamy/black-telbot/main/main_bot.py"
SELF_PATH="/usr/local/bin/black-telbot"

# ── Colors ──────────────────────────────────────────────────
C_BLACK='\033[0;30m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;37m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_RESET='\033[0m'
C_BOLD='\033[1m'

# ──────────────────────────────────────────────────────────────
# SELF-INSTALL  (run once — copies itself to /usr/local/bin)
# ──────────────────────────────────────────────────────────────
if [[ "$(realpath "$0")" != "$SELF_PATH" ]]; then
    echo -e "${C_YELLOW}Installing 'black-telbot' command…${C_RESET}"
    sudo cp "$(realpath "$0")" "$SELF_PATH"
    sudo chmod +x "$SELF_PATH"
    echo -e "${C_GREEN}Done. You can now run 'black-telbot' from anywhere.${C_RESET}"
fi

# ──────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${C_BOLD}${C_WHITE}"
    echo "  ██████╗ ██╗      █████╗  ██████╗██╗  ██╗"
    echo "  ██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝"
    echo "  ██████╔╝██║     ███████║██║     █████╔╝ "
    echo "  ██╔══██╗██║     ██╔══██║██║     ██╔═██╗ "
    echo "  ██████╔╝███████╗██║  ██║╚██████╗██║  ██╗"
    echo "  ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"
    echo -e "${C_GRAY}       T E L B O T   M A N A G E R"
    echo -e "       develop by Saeed Eramy${C_RESET}"
    echo
}

status_line() {
    local svc_status="●"
    local svc_color="$C_RED"
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        svc_status="● running"
        svc_color="$C_GREEN"
    elif systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
        svc_status="○ stopped"
        svc_color="$C_YELLOW"
    else
        svc_status="✗ not installed"
    fi
    echo -e "  Service: ${svc_color}${svc_status}${C_RESET}"
    echo
}

die() { echo -e "\n${C_RED}Error: $*${C_RESET}\n" >&2; exit 1; }
ok()  { echo -e "${C_GREEN}✓ $*${C_RESET}"; }
info(){ echo -e "${C_GRAY}  $*${C_RESET}"; }

ask() {
    # ask <var_name> <prompt> [default]
    local var="$1" prompt="$2" default="${3:-}"
    local val
    if [[ -n "$default" ]]; then
        read -rp "  $prompt [$default]: " val
        val="${val:-$default}"
    else
        while true; do
            read -rp "  $prompt: " val
            [[ -n "$val" ]] && break
            echo -e "  ${C_RED}This field is required.${C_RESET}"
        done
    fi
    printf -v "$var" '%s' "$val"
}

press_enter() { echo; read -rp "  Press Enter to continue…" _; }

# ──────────────────────────────────────────────────────────────
# SYSTEM PREP  (shared between standard and heavy install)
# ──────────────────────────────────────────────────────────────
prepare_system() {
    echo -e "\n${C_BOLD}Installing system packages…${C_RESET}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3 python3-pip python3-venv ffmpeg wget curl nano

    echo -e "\n${C_BOLD}Creating bot directories…${C_RESET}"
    mkdir -p "$BOT_DIR/downloads" "$BOT_DIR/creds"

    echo -e "\n${C_BOLD}Setting up Python virtual environment…${C_RESET}"
    python3 -m venv "$VENV"
    "$PIP" install -q --upgrade pip
    "$PIP" install -q \
        "python-telegram-bot>=20.0" \
        yt-dlp \
        google-api-python-client \
        google-auth-httplib2 \
        google-auth-oauthlib

    echo -e "\n${C_BOLD}Downloading latest bot code…${C_RESET}"
    wget -q -O "$BOT_DIR/main_bot.py" "$RAW_URL" \
        || die "Could not download main_bot.py — check your internet connection."
    ok "main_bot.py downloaded."
}

patch_token() {
    local token="$1"
    sed -i "s|YOUR_BOT_TOKEN_HERE|$token|g" "$BOT_DIR/main_bot.py"
}

patch_folder_id() {
    local folder_id="$1"
    sed -i "s|YOUR_SHARED_FOLDER_ID_HERE|$folder_id|g" "$BOT_DIR/main_bot.py"
}

create_service() {
    echo -e "\n${C_BOLD}Creating systemd service…${C_RESET}"
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
    sudo systemctl enable "$SERVICE"
    sudo systemctl restart "$SERVICE"
    sleep 2

    if systemctl is-active --quiet "$SERVICE"; then
        ok "Service is running!"
    else
        echo -e "${C_RED}Service failed to start. Check logs:${C_RESET}"
        sudo journalctl -u "$SERVICE" -n 20 --no-pager
    fi
}

# ──────────────────────────────────────────────────────────────
# MENU ACTIONS
# ──────────────────────────────────────────────────────────────
action_install_standard() {
    banner
    echo -e "${C_BOLD}  ── Standard Install (50 MB file limit) ──${C_RESET}\n"
    echo -e "  You need:"
    echo -e "  • A Telegram Bot Token  (from @BotFather)"
    echo -e "  • Your Google Drive shared folder ID\n"

    ask BOT_TOKEN     "Bot Token"
    ask FOLDER_ID     "Drive Folder ID (from the folder's URL)"

    prepare_system
    patch_token    "$BOT_TOKEN"
    patch_folder_id "$FOLDER_ID"
    create_service

    echo
    ok "Installation complete!"
    info "Run 'black-telbot' anytime to open this menu."
    press_enter; show_menu
}

action_install_heavy() {
    banner
    echo -e "${C_BOLD}  ── Heavy Install (2 GB file limit via Docker) ──${C_RESET}\n"
    echo -e "  You need:"
    echo -e "  • A Telegram Bot Token  (from @BotFather)"
    echo -e "  • Telegram API ID       (from my.telegram.org)"
    echo -e "  • Telegram API Hash     (from my.telegram.org)"
    echo -e "  • Your Google Drive shared folder ID\n"

    ask BOT_TOKEN  "Bot Token"
    ask API_ID     "Telegram API ID"
    ask API_HASH   "Telegram API Hash"
    ask FOLDER_ID  "Drive Folder ID"

    echo -e "\n${C_BOLD}Installing Docker…${C_RESET}"
    sudo apt-get install -y -qq docker.io
    sudo systemctl enable --now docker

    echo -e "\n${C_BOLD}Starting Telegram Local API server…${C_RESET}"
    sudo docker rm -f telegram-bot-api 2>/dev/null || true
    sudo docker run -d \
        --name telegram-bot-api \
        --restart always \
        -p 8081:8081 \
        -e TELEGRAM_API_ID="$API_ID" \
        -e TELEGRAM_API_HASH="$API_HASH" \
        aiogram/telegram-bot-api:latest
    ok "Local API server started on port 8081."

    prepare_system
    patch_token "$BOT_TOKEN"
    patch_folder_id "$FOLDER_ID"
    sed -i "s|USE_LOCAL_API = False|USE_LOCAL_API = True|g" "$BOT_DIR/main_bot.py"
    create_service

    echo
    ok "Heavy installation complete! 2 GB file limit is active."
    press_enter; show_menu
}

action_update() {
    banner
    echo -e "${C_BOLD}  ── Update Bot Code ──${C_RESET}\n"

    if [[ ! -f "$BOT_DIR/main_bot.py" ]]; then
        echo -e "${C_RED}Bot is not installed yet.${C_RESET}"
        press_enter; show_menu; return
    fi

    # Preserve token, folder ID, and local API setting
    local token folder_id local_api
    token=$(grep -oP "(?<=BOT_TOKEN\s{5}= \")[^\"]*" "$BOT_DIR/main_bot.py" || true)
    folder_id=$(grep -oP "(?<=DEFAULT_DRIVE_FOLDER_ID = \")[^\"]*" "$BOT_DIR/main_bot.py" || true)
    local_api=$(grep -oP "(?<=USE_LOCAL_API = )(True|False)" "$BOT_DIR/main_bot.py" || echo "False")

    echo -e "  Downloading latest version…"
    wget -q -O "$BOT_DIR/main_bot.py" "$RAW_URL" \
        || die "Download failed."

    [[ -n "$token"     ]] && patch_token "$token"
    [[ -n "$folder_id" ]] && patch_folder_id "$folder_id"
    [[ "$local_api" == "True" ]] && \
        sed -i "s|USE_LOCAL_API = False|USE_LOCAL_API = True|g" "$BOT_DIR/main_bot.py"

    # Also update yt-dlp to latest (most common reason downloads break)
    echo -e "  Updating yt-dlp…"
    "$PIP" install -q --upgrade yt-dlp
    ok "yt-dlp updated."

    sudo systemctl restart "$SERVICE"
    sleep 1
    ok "Bot updated and restarted."
    press_enter; show_menu
}

action_logs() {
    banner
    echo -e "${C_BOLD}  ── Live Logs (Ctrl+C to stop) ──${C_RESET}\n"
    sudo journalctl -u "$SERVICE" -f --no-pager || true
    show_menu
}

action_stop() {
    sudo systemctl stop "$SERVICE" && ok "Bot stopped." || true
    press_enter; show_menu
}

action_restart() {
    sudo systemctl restart "$SERVICE" && ok "Bot restarted." || true
    press_enter; show_menu
}

action_wipe() {
    banner
    echo -e "${C_RED}${C_BOLD}  !! COMPLETE WIPE — this cannot be undone !!${C_RESET}\n"
    echo -e "  This will remove:"
    echo -e "  • The bot service and all files in $BOT_DIR"
    echo -e "  • The Docker container (if running)"
    echo -e "  • The 'black-telbot' command\n"
    read -rp "  Type YES to confirm: " confirm
    [[ "$confirm" != "YES" ]] && { echo "Aborted."; press_enter; show_menu; return; }

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
    echo -e "  ${C_BOLD}[1]${C_RESET} Install — Standard   ${C_GRAY}(50 MB limit)${C_RESET}"
    echo -e "  ${C_BOLD}[2]${C_RESET} Install — Heavy      ${C_GRAY}(2 GB limit + Docker)${C_RESET}"
    echo -e "  ${C_BOLD}[3]${C_RESET} Update bot code      ${C_GRAY}(also updates yt-dlp)${C_RESET}"
    echo -e "  ${C_BOLD}[4]${C_RESET} View live logs"
    echo -e "  ${C_BOLD}[5]${C_RESET} Stop bot"
    echo -e "  ${C_BOLD}[6]${C_RESET} Restart bot"
    echo -e "  ${C_BOLD}[7]${C_RESET} Complete wipe        ${C_RED}(danger)${C_RESET}"
    echo -e "  ${C_BOLD}[8]${C_RESET} Exit"
    echo
    read -rp "  Select [1-8]: " choice
    echo

    case "$choice" in
        1) action_install_standard ;;
        2) action_install_heavy    ;;
        3) action_update           ;;
        4) action_logs             ;;
        5) action_stop             ;;
        6) action_restart          ;;
        7) action_wipe             ;;
        8) exit 0                  ;;
        *) show_menu               ;;
    esac
}

show_menu
