import os
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes, CallbackQueryHandler
import yt_dlp
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# ==========================================
# CONFIGURATION 
# ==========================================
BOT_TOKEN = "YOUR_BOT_TOKEN_HERE"
LOCAL_API_URL = "http://localhost:8081" 
CREDS_DIR = "creds"
DOWNLOADS_DIR = "downloads"

os.makedirs(CREDS_DIR, exist_ok=True)
os.makedirs(DOWNLOADS_DIR, exist_ok=True)

user_states = {}
user_urls = {}

# ==========================================
# GOOGLE DRIVE LOGIC
# ==========================================
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

# ==========================================
# BOT HANDLERS
# ==========================================
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_states[update.effective_user.id] = None
    keyboard = [
        [InlineKeyboardButton("🎬 Download Media", callback_data='menu_dl')],
        [InlineKeyboardButton("☁️ Upload to Drive", callback_data='menu_ul')],
        [InlineKeyboardButton("⚙️ Setup Credentials", callback_data='menu_setup')],
        [InlineKeyboardButton("ℹ️ About & Donate", callback_data='menu_about')]
    ]
    text = "🖤 **BLACK TELBOT** 🤍\n\nSelect an option below:"
    if update.message:
        await update.message.reply_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="Markdown")
    else:
        await update.callback_query.edit_message_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="Markdown")

async def handle_callbacks(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    uid = query.from_user.id
    cred_file_path = os.path.join(CREDS_DIR, f"{uid}.json")

    # --- ABOUT & DONATE SECTION ---
    if query.data == 'menu_about':
        about_text = (
            "🖤 *BLACK TELBOT* 🤍\n"
            "This bot is completely FREE to use! 🆓\n\n"
            "👨‍💻 *Developed by:* Saeed Ermy\n"
            "🐙 *GitHub Repo:* [black-telbot](https://github.com/saeederamy/black-telbot/)\n\n"
            "☕ *Support the Developer (Donate):*\n"
            "If you find this bot useful, consider supporting the project!\n"
            "🪙 *Litecoin (LTC) Address:*\n"
            "`ltc1qxhuvs6j0suvv50nqjsuujqlr3u4ekfmys2ydps`\n"
        )
        await query.edit_message_text(
            about_text, 
            parse_mode="Markdown", 
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Back", callback_data='back')]], disable_web_page_preview=True)
        )

    elif query.data == 'menu_dl':
        user_states[uid] = 'WAIT_URL'
        await query.edit_message_text("🔗 Send the link (YouTube, X, Insta, Spotify...): 🖤", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Back", callback_data='back')]]))
    
    elif query.data == 'menu_ul':
        if not os.path.exists(cred_file_path):
            user_states[uid] = 'WAIT_JSON'
            guide_text = (
                "⚠️ *You need to connect your Google Drive first!* 🤍\n\n"
                "📖 *How to get credentials.json:*\n"
                "1. Go to Google Cloud Console and create a Project.\n"
                "2. Enable *Google Drive API*.\n"
                "3. Go to Credentials > Create Credentials > *Service Account*.\n"
                "4. Open the created Service Account > Keys tab > Add Key > *Create JSON*.\n\n"
                "⚙️ *CRITICAL DRIVE SETUP:*\n"
                "Open the downloaded JSON file, find the `client_email` and copy it. "
                "Go to your personal Google Drive, create a folder, click 'Share', paste that email, and give it *Editor* access.\n\n"
                "📎 *Now, send me your `credentials.json` file here:* 🖤"
            )
            await query.edit_message_text(guide_text, parse_mode="Markdown", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Back", callback_data='back')]]))
        else:
            user_states[uid] = 'WAIT_FILE'
            await query.edit_message_text("📁 Great! Send me the file (Up to 2GB) to upload to your Drive: 🖤", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Back", callback_data='back')]]))
    
    elif query.data == 'menu_setup':
        user_states[uid] = 'WAIT_JSON'
        await query.edit_message_text("📑 Send your `credentials.json` file now: 🖤", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Back", callback_data='back')]]))
        
    elif query.data == 'back':
        await start(update, context)

    elif query.data.startswith('q_'):
        quality = query.data.split('_')[1]
        await start_download(update, query.message, user_urls.get(uid), quality)

async def handle_messages(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.message.from_user.id
    state = user_states.get(uid)

    if state == 'WAIT_JSON' and update.message.document:
        if update.message.document.file_name.endswith('.json'):
            file = await update.message.document.get_file()
            await file.download_to_drive(os.path.join(CREDS_DIR, f"{uid}.json"))
            await update.message.reply_text("✅ Credentials saved! You can now use the Upload feature. 🤍")
            user_states[uid] = None
        else:
            await update.message.reply_text("❌ Please send a valid .json file.")
    
    elif state == 'WAIT_URL':
        url = update.message.text
        if not url or not url.startswith("http"):
            await update.message.reply_text("❌ Send a valid URL.")
            return
        user_urls[uid] = url
        kb = [
            [InlineKeyboardButton("🎬 1080p / High", callback_data='q_1080')], 
            [InlineKeyboardButton("🎞️ 720p / Med", callback_data='q_720')],
            [InlineKeyboardButton("🎧 Audio (MP3)", callback_data='q_mp3')]
        ]
        await update.message.reply_text("📉 Select Download Quality: 🖤", reply_markup=InlineKeyboardMarkup(kb))

    elif state == 'WAIT_FILE':
        attachment = update.message.document or update.message.video or update.message.audio
        if not attachment:
            await update.message.reply_text("❌ No valid file found.")
            return
        
        msg = await update.message.reply_text("⏳ Downloading large file to server... 🤍")
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
            await msg.edit_text(f"❌ Upload Failed. Check if the folder is shared correctly.")
            
        if os.path.exists(path): os.remove(path)
        user_states[uid] = None
        await start(update, context)

async def start_download(update, message, url, q):
    if not url:
        await message.edit_text("❌ Link expired. Please send again.")
        return
        
    await message.edit_text(f"⏳ Downloading media ({q})... Please wait. ⬛️🤍")
    
    format_sel = 'bestvideo+bestaudio/best'
    if q == '1080': format_sel = 'bestvideo[height<=1080]+bestaudio/best'
    elif q == '720': format_sel = 'bestvideo[height<=720]+bestaudio/best'
    elif q == 'mp3': format_sel = 'bestaudio/best'

    ydl_opts = {
        'format': format_sel,
        'outtmpl': f'{DOWNLOADS_DIR}/%(title)s.%(ext)s',
        'merge_output_format': 'mp4' if q != 'mp3' else None,
        'quiet': True,
        'nocheckcertificate': True
    }
    
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            path = ydl.prepare_filename(info)
            
        await message.edit_text("✅ Sending to Telegram... 🖤")
        with open(path, 'rb') as f:
            if q == 'mp3': 
                await update.callback_query.message.reply_audio(f)
            else: 
                await update.callback_query.message.reply_video(f, supports_streaming=True)
                
        os.remove(path)
        await message.delete()
    except Exception as e:
        await message.edit_text("❌ Error downloading file. Link might be private.")

def main():
    # CONNECTING TO LOCAL API SERVER (Port 8081)
    app = Application.builder().token(BOT_TOKEN).base_url(f"{LOCAL_API_URL}/bot").local_mode(True).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(handle_callbacks))
    app.add_handler(MessageHandler(filters.ALL & ~filters.COMMAND, handle_messages))
    
    print("Black Telbot is running! 🖤")
    app.run_polling()

if __name__ == '__main__':
    main()
