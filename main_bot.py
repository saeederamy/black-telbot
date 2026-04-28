import os
import sys
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
USE_LOCAL_API = False  
LOCAL_API_URL = "http://localhost:8081" 
BOT_DIR = "/root/black_telbot"
CREDS_DIR = os.path.join(BOT_DIR, "creds")
DOWNLOADS_DIR = os.path.join(BOT_DIR, "downloads")

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
    if not os.path.exists(cred_file): return None
    creds = service_account.Credentials.from_service_account_file(cred_file, scopes=['https://www.googleapis.com/auth/drive.file'])
    service = build('drive', 'v3', credentials=creds)
    media = MediaFileUpload(file_path, resumable=True)
    file = service.files().create(body={'name': os.path.basename(file_path)}, media_body=media, fields='id, webViewLink').execute()
    return file.get('webViewLink')

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_states[update.effective_user.id] = None
    markup = ReplyKeyboardMarkup(MAIN_MENU, resize_keyboard=True)
    await update.message.reply_text("🖤 **BLACK TELBOT** 🤍\nSelect an option:", reply_markup=markup, parse_mode="Markdown")

async def handle_messages(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.message.from_user.id
    text = update.message.text
    state = user_states.get(uid)

    if text in [BTN_DL, BTN_UL, BTN_SETUP, BTN_ABOUT]:
        user_states[uid] = None
        if text == BTN_ABOUT:
            about_text = ("🖤 *BLACK TELBOT* 🤍\n*Developed by:* Saeed Ermy\n"
                          "🐙 *GitHub:* [black-telbot](https://github.com/saeederamy/black-telbot/)\n"
                          "🪙 *LTC:* `ltc1qxhuvs6j0suvv50nqjsuujqlr3u4ekfmys2ydps`\n")
            await update.message.reply_text(about_text, parse_mode="Markdown", disable_web_page_preview=True)
        elif text == BTN_DL:
            user_states[uid] = 'WAIT_URL'
            await update.message.reply_text("🔗 Send the link:")
        elif text == BTN_UL:
            if not os.path.exists(os.path.join(CREDS_DIR, f"{uid}.json")):
                await update.message.reply_text("⚠️ Setup Credentials first.")
            else:
                user_states[uid] = 'WAIT_FILE'
                await update.message.reply_text("📁 Send the file (Up to 2GB):")
        elif text == BTN_SETUP:
            user_states[uid] = 'WAIT_JSON'
            await update.message.reply_text("📎 Send your `credentials.json` file:")
        return

    if state == 'WAIT_JSON' and update.message.document:
        file = await update.message.document.get_file()
        await file.download_to_drive(os.path.join(CREDS_DIR, f"{uid}.json"))
        await update.message.reply_text("✅ Credentials saved!")
        user_states[uid] = None
    elif state == 'WAIT_URL' and text:
        user_urls[uid] = text
        kb = [[InlineKeyboardButton("🎬 1080p", callback_data='q_1080')], [InlineKeyboardButton("🎞️ 720p", callback_data='q_720')], [InlineKeyboardButton("🎧 MP3", callback_data='q_mp3')]]
        await update.message.reply_text("📉 Quality:", reply_markup=InlineKeyboardMarkup(kb))
    elif state == 'WAIT_FILE':
        attachment = update.message.document or update.message.video or update.message.audio
        if attachment:
            msg = await update.message.reply_text("⏳ Processing...")
            file = await attachment.get_file()
            path = os.path.join(DOWNLOADS_DIR, attachment.file_name or "file")
            await file.download_to_drive(path)
            link = upload_to_drive(path, uid)
            await msg.edit_text(f"✅ Done!\n🔗 {link}" if link else "❌ Error.")
            if os.path.exists(path): os.remove(path)
        user_states[uid] = None

async def handle_callbacks(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    uid = query.from_user.id
    quality = query.data.split('_')[1]
    url = user_urls.get(uid)
    if not url: return

    await query.edit_message_text(f"⏳ Downloading ({quality})...")
    
    # Smart format selection for YouTube/Insta
    f_str = 'bestvideo[height<=1080]+bestaudio/best[height<=1080]/best' if quality == '1080' else \
            'bestvideo[height<=720]+bestaudio/best[height<=720]/best' if quality == '720' else 'bestaudio/best'

    ydl_opts = {
        'format': f_str, 'outtmpl': f'{DOWNLOADS_DIR}/%(title)s.%(ext)s',
        'merge_output_format': 'mp4' if quality != 'mp3' else None,
        'quiet': True, 'nocheckcertificate': True, 'noplaylist': True,
        'extractor_args': {'youtube': {'player_client': ['android', 'web']}}
    }
    
    cookie_path = os.path.join(BOT_DIR, 'cookies.txt')
    if os.path.exists(cookie_path): ydl_opts['cookiefile'] = cookie_path

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            path = ydl.prepare_filename(info)
        await query.edit_message_text("✅ Sending...")
        with open(path, 'rb') as f:
            if quality == 'mp3': await context.bot.send_audio(chat_id=uid, audio=f)
            else: await context.bot.send_video(chat_id=uid, video=f, supports_streaming=True)
        if os.path.exists(path): os.remove(path)
        await query.message.delete()
    except Exception as e:
        await query.edit_message_text(f"❌ Error:\n{str(e)[:400]}")

def main():
    builder = Application.builder().token(BOT_TOKEN)
    if USE_LOCAL_API: builder = builder.base_url(f"{LOCAL_API_URL}/bot").local_mode(True)
    app = builder.build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT | filters.ATTACHMENT, handle_messages))
    app.add_handler(CallbackQueryHandler(handle_callbacks))
    app.run_polling()

if __name__ == '__main__':
    main()
