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
    sudo apt-get install -y -qq python3 python3-pip python3-venv ffmpeg wget curl nano git tar
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
        bgutil-ytdlp-pot-provider \
        spotdl \
        google-api-python-client \
        google-auth-httplib2 \
        google-auth-oauthlib
    ok "Done."
}

install_nodejs() {
    if command -v node &>/dev/null; then
        ok "Node.js $(node -v)"
        return 0
    fi
    info "Installing Node.js 20..."
    sudo apt-get install -y -qq curl
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - &>/dev/null
    sudo apt-get install -y -qq nodejs
    command -v node &>/dev/null && ok "Node.js $(node -v)" \
        || { err "Node.js install failed."; return 1; }
}

# ──────────────────────────────────────────────────────────────
# bgutil PO Token provider  (HTTP server on :4416)
# ──────────────────────────────────────────────────────────────
# YouTube blocks datacenter / server IPs with a "Sign in to confirm
# you're not a bot" challenge. The fix is a Proof-of-Origin token,
# served locally by the bgutil provider running as a small Node
# HTTP server. main_bot.py + the bgutil-ytdlp-pot-provider yt-dlp
# plugin fetch the token from it automatically. No Google account,
# no VPN, no proxy needed.
BGUTIL_REPO="https://github.com/Brainicism/bgutil-ytdlp-pot-provider"
BGUTIL_DIR="$BOT_DIR/bgutil-pot"
BGUTIL_SERVICE="bgutil-pot.service"

setup_bgutil_pot() {
    install_nodejs || return 1

    section "bgutil PO Token provider"
    rm -rf "$BGUTIL_DIR"
    if ! git clone --depth 1 "$BGUTIL_REPO" "$BGUTIL_DIR" 2>/dev/null; then
        info "git clone failed — trying tarball download..."
        mkdir -p "$BGUTIL_DIR"
        if ! wget -qO- "$BGUTIL_REPO/archive/refs/heads/master.tar.gz" \
                | tar xz -C "$BGUTIL_DIR" --strip-components=1 2>/dev/null; then
            err "Could not download bgutil provider (GitHub may be filtered)."
            info "YouTube will fall back to cookies — use option [6]."
            return 1
        fi
    fi

    if [[ ! -d "$BGUTIL_DIR/server" ]]; then
        err "Unexpected bgutil layout — 'server/' not found."
        return 1
    fi

    info "Building provider server (npm install + tsc)..."
    ( cd "$BGUTIL_DIR/server" && npm install --silent 2>/dev/null && npx tsc 2>/dev/null )

    if [[ ! -f "$BGUTIL_DIR/server/build/main.js" ]]; then
        err "Build failed — $BGUTIL_DIR/server/build/main.js missing."
        return 1
    fi
    ok "Provider built."

    info "Installing yt-dlp PO Token plugin into venv..."
    "$PIP" install -q --upgrade bgutil-ytdlp-pot-provider
    ok "Plugin installed."

    local NODE_BIN
    NODE_BIN="$(command -v node)"
    sudo tee "/etc/systemd/system/$BGUTIL_SERVICE" > /dev/null <<EOF
[Unit]
Description=bgutil PO Token provider (Black Telbot)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$BGUTIL_DIR/server
ExecStart=$NODE_BIN $BGUTIL_DIR/server/build/main.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$BGUTIL_SERVICE" --quiet
    sudo systemctl restart "$BGUTIL_SERVICE"
    sleep 3

    if curl -s -m 4 http://127.0.0.1:4416/ping | grep -q version; then
        ok "PO Token server is running on :4416."
        return 0
    fi
    warn "PO Token server did not respond. Check: journalctl -u $BGUTIL_SERVICE"
    return 1
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
# YOUTUBE AUTH  (PO Token provider + cookies fallback)
# ──────────────────────────────────────────────────────────────
#
# Why this is needed:
#   YouTube blocks datacenter / server IPs with a "Sign in to confirm
#   you're not a bot" challenge. Two solutions work without a VPN:
#
#   1. PO Token provider (preferred) — a small local Node HTTP server
#      (bgutil-ytdlp-pot-provider) that mints Proof-of-Origin tokens
#      on demand. Runs as bgutil-pot.service; the matching yt-dlp
#      plugin fetches tokens automatically. No Google account, set
#      up once, refreshes itself.
#
#   2. cookies.txt (fallback) — export your YouTube cookies from a
#      browser where you are logged in. Requires a Google account.
#
# main_bot.py uses the PO Token server first and falls back to
# cookies.txt automatically when present.
# ──────────────────────────────────────────────────────────────

action_yt_po_token() {
    banner
    echo -e "${BOLD}  ── YouTube PO Token Provider ──${R}\n"
    echo -e "  Installs a local token server so YouTube works from a server IP."
    echo -e "  No Google account, no proxy, no VPN. Set up once.\n"

    if [[ ! -f "$BOT_DIR/main_bot.py" ]]; then
        err "Bot is not installed yet."; press_enter; show_menu; return
    fi

    if setup_bgutil_pot; then
        sudo systemctl restart "$SERVICE" 2>/dev/null || true
        sleep 1
        ok "Bot restarted — YouTube downloads should work now."
    else
        warn "PO Token provider not active. Use option [6] (cookies) instead."
    fi
    press_enter; show_menu
}

action_yt_cookies() {
    banner
    echo -e "${BOLD}  ── YouTube Cookies Setup ──${R}\n"
    echo -e "  How to get cookies.txt:"
    echo -e "  ${CYAN}1.${R} Install browser extension: 'Get cookies.txt LOCALLY'"
    echo -e "     ${GRAY}Chrome: https://chrome.google.com/webstore/search/get+cookies.txt${R}"
    echo -e "  ${CYAN}2.${R} Log in to YouTube in your browser"
    echo -e "  ${CYAN}3.${R} Go to youtube.com, click the extension, export cookies"
    echo -e "  ${CYAN}4.${R} Copy the file content\n"
    echo -e "  ${YELLOW}Note: cookies expire periodically — re-run this option to refresh.${R}\n"

    if ! ask_yn "Open editor to paste cookies.txt content now?"; then
        show_menu; return
    fi

    if [[ ! -f "$BOT_DIR/main_bot.py" ]]; then
        err "Bot is not installed yet."; press_enter; show_menu; return
    fi

    echo -e "\n  ${GRAY}Editor opening — paste content, then Ctrl+O Enter Ctrl+X to save.${R}"
    sleep 2
    nano "$BOT_DIR/cookies.txt"

    if [[ -s "$BOT_DIR/cookies.txt" ]]; then
        ok "cookies.txt saved."
        sudo systemctl restart "$SERVICE" 2>/dev/null || true
        sleep 1
        ok "Bot restarted."
    else
        warn "File is empty — cookies not saved."
    fi
    press_enter; show_menu
}

# ──────────────────────────────────────────────────────────────
# VPN / PROXY FOR DOWNLOADS
# ──────────────────────────────────────────────────────────────
# When YouTube has flagged the server IP, the only fully reliable
# fix is to route downloads through a residential VPN/proxy. This
# sets YTDLP_PROXY in main_bot.py; it is applied to BOTH yt-dlp
# (YouTube) and spotdl (Spotify) downloads.
#
# Run your VPN so it exposes a local proxy port, then enter it here.
#   HTTP proxy : http://127.0.0.1:8080
#   SOCKS proxy: socks5://127.0.0.1:1080
# Just a number is treated as http://127.0.0.1:<port>.
# ──────────────────────────────────────────────────────────────
action_set_proxy() {
    banner
    echo -e "${BOLD}  ── VPN / Proxy for downloads ──${R}\n"

    if [[ ! -f "$BOT_DIR/main_bot.py" ]]; then
        err "Bot is not installed yet."; press_enter; show_menu; return
    fi

    # Stale code guard: old main_bot.py has no YTDLP_PROXY line, so the
    # sed below would silently do nothing and the proxy would never apply.
    if ! grep -q '^YTDLP_PROXY = ' "$BOT_DIR/main_bot.py"; then
        err "Installed bot code is outdated (no proxy support)."
        info "Run option [3] Update FIRST, then set the proxy again."
        press_enter; show_menu; return
    fi

    local current
    current=$(grep -oP 'YTDLP_PROXY\s*=\s*"\K[^"]*' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "")
    if [[ -n "$current" ]]; then
        echo -e "  Current: ${GREEN}$current${R}\n"
    else
        echo -e "  Current: ${GRAY}(none — direct connection)${R}\n"
    fi
    echo -e "  Examples:"
    echo -e "  ${GRAY}  http://127.0.0.1:8080   socks5://127.0.0.1:1080   8080${R}"
    echo -e "  ${GRAY}Enter '-' to disable the proxy.${R}\n"

    local input
    read -rp "  Proxy URL / port (blank = keep current): " input
    [[ -z "$input" ]] && { info "Unchanged."; press_enter; show_menu; return; }

    local proxy
    if [[ "$input" == "-" ]]; then
        proxy=""
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        proxy="http://127.0.0.1:$input"
    elif [[ "$input" =~ ^(https?|socks[45]):// ]]; then
        proxy="$input"
    elif [[ "$input" =~ ^[^/]+:[0-9]+$ ]]; then
        proxy="http://$input"
    else
        err "Unrecognized format. Use http://host:port, socks5://host:port, or a port number."
        press_enter; show_menu; return
    fi

    if [[ "$proxy" == *"|"* || "$proxy" == *"&"* ]]; then
        err "Proxy contains unsupported characters ( | or & )."
        press_enter; show_menu; return
    fi

    sed -i "s|^YTDLP_PROXY = .*|YTDLP_PROXY = \"$proxy\"|" "$BOT_DIR/main_bot.py"

    # Confirm the change really landed in the file.
    local saved
    saved=$(grep -oP 'YTDLP_PROXY\s*=\s*"\K[^"]*' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "")
    if [[ "$saved" != "$proxy" ]]; then
        err "Failed to write the proxy into main_bot.py."
        press_enter; show_menu; return
    fi

    if [[ -n "$proxy" ]]; then
        ok "Saved. Downloads will now go through: $proxy"

        # Live test: show the IP YouTube will actually see through this
        # proxy. If it fails or matches the server's own IP, the proxy
        # is the problem — not the bot.
        section "Proxy check"
        local direct_ip proxy_ip
        direct_ip=$(curl -s -m 10 https://api.ipify.org 2>/dev/null \
                    || curl -s -m 10 https://ifconfig.me 2>/dev/null || echo "?")
        proxy_ip=$(curl -s -m 15 --proxy "$proxy" https://api.ipify.org 2>/dev/null \
                   || curl -s -m 15 --proxy "$proxy" https://ifconfig.me 2>/dev/null || echo "")

        info "Server direct IP : ${direct_ip:-?}"
        if [[ -z "$proxy_ip" ]]; then
            err "Could NOT reach the internet through the proxy."
            info "The VPN/proxy is not running or the port/address is wrong."
            info "Fix the proxy first, then re-run this option."
        elif [[ "$proxy_ip" == "$direct_ip" ]]; then
            warn "Proxy exit IP == server IP ($proxy_ip)."
            info "This proxy does NOT change your route — YouTube will"
            info "still see the flagged server IP. Use a real VPN whose"
            info "exit is a residential IP."
        else
            ok "Proxy exit IP: $proxy_ip  (different from server — good)"
            info "If YouTube still blocks, this proxy's IP is also flagged;"
            info "try a different VPN endpoint or add cookies (option [6])."
        fi
    else
        ok "Proxy disabled — downloads use a direct connection."
    fi

    sudo systemctl restart "$SERVICE" 2>/dev/null || true
    sleep 1
    ok "Bot restarted."
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

    setup_bgutil_pot || warn "YouTube PO Token setup incomplete — retry with option [5]."
    sudo systemctl restart "$SERVICE" 2>/dev/null || true

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

    setup_bgutil_pot || warn "YouTube PO Token setup incomplete — retry with option [5]."
    sudo systemctl restart "$SERVICE" 2>/dev/null || true

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

    local token folder_id local_api proxy
    token=$(grep -oP 'BOT_TOKEN\s*=\s*"\K[^"]+' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "")
    folder_id=$(grep -oP 'DEFAULT_DRIVE_FOLDER_ID\s*=\s*"\K[^"]+' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "")
    local_api=$(grep -oP 'USE_LOCAL_API\s*=\s*\K(True|False)' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "False")
    proxy=$(grep -oP 'YTDLP_PROXY\s*=\s*"\K[^"]*' "$BOT_DIR/main_bot.py" 2>/dev/null || echo "")

    info "Downloading latest bot code..."
    wget -q -O "$BOT_DIR/main_bot.py" "$BOT_URL" \
        || { err "Download failed."; press_enter; show_menu; return; }

    [[ -n "$token" ]] && \
        patch "$BOT_DIR/main_bot.py" "YOUR_BOT_TOKEN_HERE" "$token"
    [[ -n "$folder_id" && "$folder_id" != "DRIVE_FOLDER_DISABLED" ]] && \
        patch "$BOT_DIR/main_bot.py" "DRIVE_FOLDER_DISABLED" "$folder_id"
    [[ "$local_api" == "True" ]] && \
        patch "$BOT_DIR/main_bot.py" "USE_LOCAL_API = False" "USE_LOCAL_API = True"
    [[ -n "$proxy" ]] && \
        sed -i "s|^YTDLP_PROXY = .*|YTDLP_PROXY = \"$proxy\"|" "$BOT_DIR/main_bot.py"

    info "Updating yt-dlp, PO Token plugin and spotdl..."
    "$PIP" install -q --upgrade yt-dlp bgutil-ytdlp-pot-provider spotdl
    ok "yt-dlp, plugin and spotdl updated."

    # Self-heal: make sure the YouTube PO Token provider is installed
    # and actually responding. If not, set it up now — this makes
    # Update a one-step fix with no extra menu steps needed.
    if curl -s -m 4 http://127.0.0.1:4416/ping 2>/dev/null | grep -q version; then
        sudo systemctl restart "$BGUTIL_SERVICE" 2>/dev/null || true
        ok "YouTube PO Token server OK."
    else
        info "YouTube PO Token provider missing — setting it up now..."
        setup_bgutil_pot \
            || warn "PO Token setup incomplete — use option [6] (cookies) as fallback."
    fi

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
    sudo systemctl stop    "$BGUTIL_SERVICE" 2>/dev/null || true
    sudo systemctl disable "$BGUTIL_SERVICE" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$BGUTIL_SERVICE"
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
    echo -e "  ${BOLD}[5]${R} YouTube — PO Token    ${CYAN}fix bot-check${R}"
    echo -e "  ${BOLD}[6]${R} YouTube — Cookies     ${CYAN}alternative fix${R}"
    echo -e "  ${BOLD}[p]${R} VPN / Proxy           ${CYAN}route downloads via VPN${R}"
    echo -e "  ${BOLD}[7]${R} Google Drive setup    ${CYAN}optional${R}"
    echo -e "  ${BOLD}[8]${R} Disable Drive"
    echo -e "  ${BOLD}[9]${R} Stop bot"
    echo -e "  ${BOLD}[r]${R} Restart bot"
    echo -e "  ${BOLD}[w]${R} Complete wipe         ${RED}danger${R}"
    echo -e "  ${BOLD}[0]${R} Exit"
    echo
    read -rp "  Select: " choice
    echo

    case "${choice:-}" in
        1) action_install_standard ;;
        2) action_install_heavy    ;;
        3) action_update           ;;
        4) action_logs             ;;
        5) action_yt_po_token      ;;
        6) action_yt_cookies       ;;
        p|P) action_set_proxy      ;;
        7) action_drive_setup      ;;
        8) action_drive_disable    ;;
        9) action_stop             ;;
        r) action_restart          ;;
        w) action_wipe             ;;
        0) exit 0                  ;;
        *) show_menu               ;;
    esac
}

show_menu
