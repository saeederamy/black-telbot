import os
from telegram import Update, ReplyKeyboardMarkup, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes, CallbackQueryHandler
import yt_dlp
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# ==========================================
# CONFIGURATION 
# ==========================================
BOT_TOKEN = "YOUR_BOT_TOKEN_HERE"
USE_LOCAL_API = False  # Changed automatically by setup.sh
LOCAL_API_URL = "http://localhost:8081" 
CREDS_DIR = "creds"
DOWNLOADS_DIR = "downloads"

os.makedirs(CREDS_DIR, exist_ok=True)
os.makedirs(DOWNLOADS_DIR, exist_ok=True)

user_states = {}
user_urls = {}

# Menu Buttons
BTN_DL = "🎬 Download Media"
BTN_UL = "☁️ Upload to Drive"
BTN_SETUP = "⚙️ Setup Credentials"
BTN_ABOUT = "ℹ️ About & Donate"

MAIN_MENU = [[BTN_DL, BTN_UL], [BTN_SETUP, BTN_ABOUT]]

def upload_to_drive(file_path, user_id):
    cred_file = os.path.join(CREDS_DIR, f"{user_id}.json")
    if not os.path.exists(cred_file):
        return None
    scopes = ['https://www.googleapis.com/auth/drive.file']
    creds = service_account.Credentials.from_service_account_file(cred_file, scopes=scopes)
    service = build('drive', 'v3', credentials=creds)
    file_metadata = {'name': os.path.basename(file_path)}
    media = MediaFileUpload(file_path, resumable=True)
    file = service.files().create(body=file_metadata, media_body=media, fields='id, webViewLink').execute()
    return file.get('webViewLink')

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_states[update.effective_user.id] = None
    markup = ReplyKeyboardMarkup(MAIN_MENU, resize_keyboard=True)
    await update.message.reply_text(
        "🖤 **Welcome to BLACK TELBOT** 🤍\n\nPlease select an option from the menu below:", 
        reply_markup=markup, 
        parse_mode="Markdown"
    )

async def handle_messages(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.message.from_user.id
    text = update.message.text
    state = user_states.get(uid)

    # --- HANDLE MAIN MENU BUTTONS ---
    if text in [BTN_DL, BTN_UL, BTN_SETUP, BTN_ABOUT]:
        user_states[uid] = None  # Reset state on menu click
        
        if text == BTN_ABOUT:
            about_text = (
                "🖤 *BLACK TELBOT* 🤍\n"
                "This bot is completely FREE to use! 🆓\n\n"
                "👨‍💻 *Developed by:* Saeed Ermy\n"
                "🐙 *GitHub Repo:* [black-telbot](https://github.com/saeederamy/black-telbot/)\n\n"
                "☕ *Support the Developer (Donate):*\n"
                "🪙 *Litecoin (LTC):*\n"
                "`ltc1qxhuvs6j0suvv50nqjsuujqlr3u4ekfmys2ydps`\n"
            )
            await update.message.reply_text(about_text, parse_mode="Markdown", disable_web_page_preview=True)
        
        elif text == BTN_DL:
            user_states[uid] = 'WAIT_URL'
            await update.message.reply_text("🔗 Please send the link (YouTube, X, Insta, Spotify...):")
        
        elif text == BTN_UL:
            if not os.path.exists(os.path.join(CREDS_DIR, f"{uid}.json")):
                await update.message.reply_text("⚠️ Please use 'Setup Credentials' first to connect your Google Drive.")
            else:
                user_states[uid] = 'WAIT_FILE'
                await update.message.reply_text("📁 Great! Send me the file to upload to your Drive:")
        
        elif text == BTN_SETUP:
            user_states[uid] = 'WAIT_JSON'
            guide_text = (
                "⚠️ *Connect your Google Drive!* 🤍\n\n"
                "1. Go to Google Cloud Console, create a Project, and enable *Google Drive API*.\n"
                "2. Create a *Service Account* and download its *JSON Key*.\n"
                "3. In your personal Google Drive, create a folder, click 'Share', paste the `client_email` from the JSON, and give *Editor* access.\n\n"
                "📎 *Now, send me your `credentials.json` file as a document:* 🖤"
            )
            await update.message.reply_text(guide_text, parse_mode="Markdown")
        return

    # --- HANDLE STATES ---
    if state == 'WAIT_JSON' and update.message.document:
        if update.message.document.file_name.endswith('.json'):
            file = await update.message.document.get_file()
            await file.download_to_drive(os.path.join(CREDS_DIR, f"{uid}.json"))
            await update.message.reply_text("✅ Credentials saved! You can now use the Upload feature.")
            user_states[uid] = None
        else:
            await update.message.reply_text("❌ Please send a valid .json file.")
    
    elif state == 'WAIT_URL' and text:
        if not text.startswith("http"):
            await update.message.reply_text("❌ Send a valid URL.")
            return
        user_urls[uid] = text
        kb = [
            [InlineKeyboardButton("🎬 1080p / High", callback_data='q_1080')], 
            [InlineKeyboardButton("🎞️ 720p / Med", callback_data='q_720')],
            [InlineKeyboardButton("🎧 Audio (MP3)", callback_data='q_mp3')]
        ]
        await update.message.reply_text("📉 Select Download Quality:", reply_markup=InlineKeyboardMarkup(kb))

    elif state == 'WAIT_FILE':
        attachment = update.message.document or update.message.video or update.message.audio
        if not attachment:
            await update.message.reply_text("❌ No valid file found. Please send a document, video, or audio.")
            return
        
        msg = await update.message.reply_text("⏳ Downloading file to server... 🤍")
        file = await attachment.get_file()
        file_name = attachment.file_name if hasattr(attachment, 'file_name') else f"ul_{uid}.dat"
        path = os.path.join(DOWNLOADS_DIR, file_name)
        
        await file.download_to_drive(path)
        await msg.edit_text("☁️ Uploading to your Google Drive... 🖤")
        
        try:
            link = upload_to_drive(path, uid)
            if link:
                await msg.edit_text(f"✅ Upload Complete!\n🔗 Link: {link}")
            else:
                await msg.edit_text("❌ Credentials error. Please setup credentials again.")
        except Exception as e:
            await msg.edit_text(f"❌ Upload Failed. Check if the folder is shared correctly with the bot email.")
            
        if os.path.exists(path): os.remove(path)
        user_states[uid] = None

async def handle_callbacks(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    uid = query.from_user.id

    if query.data.startswith('q_'):
        quality = query.data.split('_')[1]
        url = user_urls.get(uid)
        if not url:
            await query.edit_message_text("❌ Link expired. Please send again.")
            return
            
        await query.edit_message_text(f"⏳ Downloading media ({quality})... Please wait. ⬛️🤍")
        
        format_sel = 'bestvideo+bestaudio/best'
        if quality == '1080': format_sel = 'bestvideo[height<=1080]+bestaudio/best'
        elif quality == '720': format_sel = 'bestvideo[height<=720]+bestaudio/best'
        elif quality == 'mp3': format_sel = 'bestaudio/best'

        ydl_opts = {
            'format': format_sel,
            'outtmpl': f'{DOWNLOADS_DIR}/%(title)s.%(ext)s',
            'merge_output_format': 'mp4' if quality != 'mp3' else None,
            'quiet': True,
            'nocheckcertificate': True
        }
        
        # 🍪 AUTOMATIC COOKIE DETECTION 🍪
        if os.path.exists('cookies.txt'):
            ydl_opts['cookiefile'] = 'cookies.txt'
        
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                path = ydl.prepare_filename(info)
                
            await query.edit_message_text("✅ Sending to Telegram... 🖤")
            with open(path, 'rb') as f:
                if quality == 'mp3': 
                    await query.message.reply_audio(f)
                else: 
                    await query.message.reply_video(f, supports_streaming=True)
                    
            os.remove(path)
            await query.message.delete()
        except Exception as e:
            await query.edit_message_text(f"❌ Error downloading file: It might be private or require updated cookies.")

def main():
    builder = Application.builder().token(BOT_TOKEN)
    if USE_LOCAL_API:
        builder = builder.base_url(f"{LOCAL_API_URL}/bot").local_mode(True)
        
    app = builder.build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT | filters.Document.ALL | filters.VIDEO | filters.AUDIO, handle_messages))
    app.add_handler(CallbackQueryHandler(handle_callbacks))
    
    print("Black Telbot is running! 🖤")
    app.run_polling()

if __name__ == '__main__':
    main()
