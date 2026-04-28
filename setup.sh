#!/bin/bash

BOT_DIR="/root/black_telbot"
SERVICE_NAME="blacktelbot.service"
GITHUB_RAW_URL="https://raw.githubusercontent.com/saeederamy/black-telbot/main/main_bot.py"

if [[ "$0" != "/usr/local/bin/black-telbot" ]]; then
    sudo cp "$0" /usr/local/bin/black-telbot
    sudo chmod +x /usr/local/bin/black-telbot
fi

function show_menu() {
    clear
    echo -e "🖤 🤍 🖤 🤍 🖤 🤍 🖤 🤍 🖤 🤍 🖤"
    echo -e "       B L A C K  T E L B O T       "
    echo -e "🖤 🤍 🖤 🤍 🖤 🤍 🖤 🤍 🖤 🤍 🖤"
    echo "1. 🚀 Install Bot (Standard - 50MB Limit - NO API Keys Needed)"
    echo "2. 🚀 Install Bot (Heavy - 2GB Limit - Needs API Keys & Docker)"
    echo "3. 🛑 Stop Bot"
    echo "4. 🔄 Restart Bot"
    echo "5. 🗑️ Delete Everything"
    echo "6. 📥 Update Source Code"
    echo "7. ❌ Exit"
    echo -e "------------------------------------"
    read -p "Select an option [1-7]: " choice
    handle_choice $choice
}

function handle_choice() {
    case $1 in
        1) install_standard ;;
        2) install_heavy ;;
        3) sudo systemctl stop $SERVICE_NAME ; echo "Stopped." ; sleep 2 ; show_menu ;;
        4) sudo systemctl restart $SERVICE_NAME ; echo "Restarted." ; sleep 2 ; show_menu ;;
        5) delete_all ;;
        6) update_code ;;
        7) exit 0 ;;
        *) show_menu ;;
    esac
}

function prepare_system() {
    echo -e "\n--- 📦 Installing System Dependencies ---"
    sudo apt update && sudo apt install -y python3 python3-pip python3-venv ffmpeg wget curl
    
    mkdir -p $BOT_DIR/downloads
    mkdir -p $BOT_DIR/creds
    cd $BOT_DIR
    python3 -m venv venv
    source venv/bin/activate
    pip install python-telegram-bot yt-dlp google-api-python-client google-auth-httplib2 google-auth-oauthlib
    
    wget -O main_bot.py $GITHUB_RAW_URL
}

function create_service() {
    cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME
[Unit]
Description=Black Telbot Service
After=network.target

[Service]
User=root
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/venv/bin/python3 $BOT_DIR/main_bot.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME
    echo "✅ INSTALLATION FINISHED! Type 'black-telbot' anywhere to open the menu."
    sleep 3
    show_menu
}

function install_standard() {
    echo -e "\n--- 🛠️ Setup (Standard Mode) ---"
    read -p "Enter Telegram Bot Token: " USER_TOKEN
    
    prepare_system
    sed -i "s/YOUR_BOT_TOKEN_HERE/$USER_TOKEN/g" main_bot.py
    
    create_service
}

function install_heavy() {
    echo -e "\n--- 🛠️ Setup (Heavy Mode - 2GB) ---"
    read -p "Enter Telegram Bot Token: " USER_TOKEN
    read -p "Enter Telegram API ID: " USER_API_ID
    read -p "Enter Telegram API Hash: " USER_API_HASH

    sudo apt install -y docker.io docker-compose
    sudo docker run -d -p 8081:8081 --name telegram-bot-api --restart=always -e TELEGRAM_API_ID=$USER_API_ID -e TELEGRAM_API_HASH=$USER_API_HASH aiogram/telegram-bot-api:latest

    prepare_system
    sed -i "s/YOUR_BOT_TOKEN_HERE/$USER_TOKEN/g" main_bot.py
    sed -i "s/USE_LOCAL_API = False/USE_LOCAL_API = True/g" main_bot.py
    
    create_service
}

function delete_all() {
    sudo systemctl stop $SERVICE_NAME
    sudo docker stop telegram-bot-api 2>/dev/null
    sudo docker rm telegram-bot-api 2>/dev/null
    sudo rm /etc/systemd/system/$SERVICE_NAME
    sudo rm -rf $BOT_DIR
    echo "Everything deleted." ; sleep 2 ; show_menu
}

function update_code() {
    cd $BOT_DIR && wget -O main_bot.py $GITHUB_RAW_URL && sudo systemctl restart $SERVICE_NAME
    echo "Updated." ; sleep 2 ; show_menu
}

show_menu
