#!/bin/bash

# ==========================================
# Black Telbot - Full Auto Global Manager
# ==========================================
BOT_DIR="/root/black_telbot"
SERVICE_NAME="blacktelbot.service"
# Replace the URL below with your raw GitHub link after uploading main_bot.py
GITHUB_RAW_URL="https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/main_bot.py"

# Register globally
if [[ "$0" != "/usr/local/bin/black-telbot" ]]; then
    sudo cp "$0" /usr/local/bin/black-telbot
    sudo chmod +x /usr/local/bin/black-telbot
fi

function show_menu() {
    clear
    echo -e "🖤 🤍 🖤 🤍 🖤 🤍 🖤 🤍 🖤 🤍 🖤"
    echo -e "       B L A C K  T E L B O T       "
    echo -e "         FULL AUTO SYSTEM           "
    echo -e "🖤 🤍 🖤 🤍 🖤 🤍 🖤 🤍 🖤 🤍 🖤"
    echo "1. 🚀 Full Automatic Install"
    echo "2. 🛑 Stop Bot"
    echo "3. 🔄 Restart Bot"
    echo "4. 🗑️ Delete Everything"
    echo "5. 📥 Update Source Code"
    echo "6. ❌ Exit"
    echo -e "------------------------------------"
    read -p "Select an option [1-6]: " choice
    handle_choice $choice
}

function install_bot() {
    echo -e "\n--- 🛠️ Setup Credentials ---"
    read -p "Enter Telegram Bot Token: " USER_TOKEN
    read -p "Enter Telegram API ID: " USER_API_ID
    read -p "Enter Telegram API Hash: " USER_API_HASH

    echo -e "\n--- 📦 Installing System Dependencies ---"
    sudo apt update && sudo apt install -y python3 python3-pip python3-venv ffmpeg docker.io docker-compose wget curl

    echo -e "\n--- 🐳 Starting Local Bot API Server (Docker) ---"
    sudo docker run -d -p 8081:8081 --name telegram-bot-api \
      --restart=always \
      -e TELEGRAM_API_ID=$USER_API_ID \
      -e TELEGRAM_API_HASH=$USER_API_HASH \
      aiogram/telegram-bot-api:latest

    echo -e "\n--- 📂 Setting up Black Telbot ---"
    mkdir -p $BOT_DIR/downloads
    mkdir -p $BOT_DIR/creds
    cd $BOT_DIR
    python3 -m venv venv
    source venv/bin/activate
    pip install python-telegram-bot yt-dlp google-api-python-client google-auth-httplib2 google-auth-oauthlib

    echo -e "\n--- 📥 Downloading & Configuring Source Code ---"
    wget -O main_bot.py $GITHUB_RAW_URL
    # Replace placeholders in Python file with actual user input
    sed -i "s/YOUR_BOT_TOKEN_HERE/$USER_TOKEN/g" main_bot.py

    echo -e "\n--- ⚙️ Creating System Service ---"
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
    
    echo "✅ INSTALLATION FINISHED! Bot is now running."
    sleep 3
    show_menu
}

function handle_choice() {
    case $1 in
        1) install_bot ;;
        2) sudo systemctl stop $SERVICE_NAME ; echo "Stopped." ; sleep 2 ; show_menu ;;
        3) sudo systemctl restart $SERVICE_NAME ; echo "Restarted." ; sleep 2 ; show_menu ;;
        4) 
            sudo systemctl stop $SERVICE_NAME
            sudo docker stop telegram-bot-api && sudo docker rm telegram-bot-api
            sudo rm /etc/systemd/system/$SERVICE_NAME
            sudo rm -rf $BOT_DIR
            echo "Everything deleted." ; sleep 2 ; show_menu ;;
        5) cd $BOT_DIR && wget -O main_bot.py $GITHUB_RAW_URL && sudo systemctl restart $SERVICE_NAME ; echo "Updated." ; sleep 2 ; show_menu ;;
        6) exit 0 ;;
        *) show_menu ;;
    esac
}

show_menu
