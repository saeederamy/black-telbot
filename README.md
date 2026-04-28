<div align="center">

# 🖤 Black Telbot 🤍
### Advanced Multi-User Telegram to Google Drive Assistant

![Python](https://img.shields.io/badge/Python-3.9+-black.svg?style=for-the-badge&logo=python&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Local_API-white.svg?style=for-the-badge&logo=docker&logoColor=black)
![Telegram](https://img.shields.io/badge/Telegram-2GB_Upload-black.svg?style=for-the-badge&logo=telegram&logoColor=white)

</div>

**Black Telbot** is an advanced, high-performance Telegram Bot built with Python. It acts as a dual-purpose personal assistant:
* 🎬 **Media Downloader:** Downloads high-quality videos and audio from X (Twitter), Instagram, YouTube, Spotify, and various other websites.
* ☁️ **Drive Uploader:** Bypasses Telegram's standard 50MB limit to receive files up to **2GB** and uploads them directly to the user's personal Google Drive.

This bot supports multiple users simultaneously, isolating each user's Google Drive credentials for ultimate privacy.

---

## 🌟 Key Features

* **2GB File Support:** Utilizes a Local Telegram Bot API Server via Docker to handle massive files.
* **Multi-User Architecture:** Each user provides their own `credentials.json`, meaning files go to their Drive, not a central server Drive.
* **Format Selection:** Users can choose between 1080p, 720p, or Audio-only (MP3) before downloading media.
* **Global Command Manager:** Comes with a fully automated Bash script (`black-telbot`) for easy installation, updating, and service management on Ubuntu.
* **Black & White Aesthetic:** Sleek and minimalistic UI using Telegram Inline Keyboards.

---

## 🛠️ Part 1: Deployment Guide (For the Server Owner)

If you are hosting this bot on your Ubuntu Server, follow these steps.

### Step 1: Get Your Telegram API Credentials
To run a Local API Server (which allows the 2GB limit), you need developer API keys.
1. Go to [my.telegram.org](https://my.telegram.org) and log in.
2. Click on **API development tools**.
3. Create a new application (fill in any App Title and Short Name, set Platform to Other).
4. Copy your **App api_id** and **App api_hash**.

### Step 2: Get Your Bot Token
1. Go to Telegram and message `@BotFather`.
2. Send `/newbot`, choose a name, and get your **HTTP API Token**.

### Step 3: Run the Auto-Installer
Connect to your Ubuntu server (SSH) and run the following commands to install everything automatically:

```bash
wget [https://raw.githubusercontent.com/saeederamy/black-telbot/main/setup.sh]
chmod +x setup.sh
./setup.sh
```
> **Note:** Choose option 1 from the menu and paste your Token, API ID, and API Hash when prompted.

---

## 📖 Part 2: User Guide (How to use the Drive Uploader)

For end-users to upload files to their personal Google Drive, they must provide the bot with a Google Service Account key.

### Step 1: Get `credentials.json` from Google Cloud
1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and create a New Project.
2. Search for **Google Drive API** in the top bar and click **Enable**.
3. Go to the **Credentials** tab on the left menu.
4. Click **+ CREATE CREDENTIALS** and select **Service Account**.
5. Give it a name (e.g., `black-telbot-upload`) and click **Done**.
6. Click on the newly created Service Account email in the list.
7. Go to the **Keys** tab > **Add Key** > **Create new key** > Select **JSON**.
8. The `credentials.json` file will download to your device.

### Step 2: Configure Your Personal Google Drive
> ⚠️ **CRITICAL STEP:** The downloaded JSON file acts as a "virtual robot worker." You must give this robot permission to access a specific folder in your Drive.

1. Open the `credentials.json` file with a text editor (like Notepad).
2. Find the line that says `"client_email"` and copy the email address next to it.
3. Open your personal Google Drive.
4. Create a new folder (e.g., `Bot_Uploads`).
5. Right-click the folder > **Share**.
6. Paste the copied email address into the "Add people" box.
7. Set the permission to **Editor** and click **Send**.

### Step 3: Connect to the Bot
Send the `credentials.json` file to Black Telbot in Telegram. You can now send files up to 2GB to the bot, and they will appear directly in your shared Google Drive folder!

---

