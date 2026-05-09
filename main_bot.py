"""
╔══════════════════════════════════════════════════════════════╗
║              BLACK TELBOT — main_bot.py                     ║
║         develop by Saeed Eramy                              ║
║         https://github.com/saeederamy                       ║
╚══════════════════════════════════════════════════════════════╝
"""

import os
import asyncio
import logging
import mimetypes

from telegram import Update, ReplyKeyboardMarkup, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, MessageHandler,
    filters, ContextTypes, CallbackQueryHandler,
)
import yt_dlp
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError

# ──────────────────────────────────────────────────────────────
# LOGGING
# ──────────────────────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s | %(levelname)s | %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────
BOT_TOKEN     = "YOUR_BOT_TOKEN_HERE"
USE_LOCAL_API = False
LOCAL_API_URL = "http://localhost:8081"

BOT_DIR       = "/root/black_telbot"
CREDS_DIR     = os.path.join(BOT_DIR, "creds")
DOWNLOADS_DIR = os.path.join(BOT_DIR, "downloads")

# Paste the ID from your shared Drive folder URL:
# https://drive.google.com/drive/folders/<THIS_PART>
DEFAULT_DRIVE_FOLDER_ID = "YOUR_SHARED_FOLDER_ID_HERE"

os.makedirs(CREDS_DIR,     exist_ok=True)
os.makedirs(DOWNLOADS_DIR, exist_ok=True)

# ──────────────────────────────────────────────────────────────
# STATE STORES
# ──────────────────────────────────────────────────────────────
user_states: dict[int, str | None] = {}
user_urls:   dict[int, str]        = {}

# ──────────────────────────────────────────────────────────────
# MENU
# ──────────────────────────────────────────────────────────────
BTN_DL    = "🎬 Download Media"
BTN_UL    = "☁️ Upload to Drive"
BTN_SETUP = "⚙️ Setup Credentials"
BTN_ABOUT = "ℹ️ About"
MAIN_MENU = [[BTN_DL, BTN_UL], [BTN_SETUP, BTN_ABOUT]]


# ══════════════════════════════════════════════════════════════
# YT-DLP — COOKIELESS DOWNLOAD  (3-tier fallback)
# ══════════════════════════════════════════════════════════════
#
#  Tier 1 — mweb player client
#    YouTube's mobile-web endpoint skips the "confirm you're not a bot"
#    gate entirely.  Works for the vast majority of public videos.
#
#  Tier 2 — tv_embedded player client
#    YouTube's TV/embed endpoint authenticates via an API key that
#    yt-dlp already has baked in — no user session required.
#    Catches age-restricted or geo-blocked content that mweb can't serve.
#
#  Tier 3 — ios player client + Instagram GraphQL
#    iOS client uses a different signing key and is the last reliable
#    option before giving up.  For Instagram, the public GraphQL API
#    is used (works for public posts without login).
#
#  No cookies are read or written anywhere in this chain.
# ──────────────────────────────────────────────────────────────

_CHROME_UA = (
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/125.0.0.0 Mobile Safari/537.36"
)
_INSTA_UA = (
    "Instagram 319.0.0.45.109 Android (33/13; 420dpi; 1080x2400; "
    "Google/google; Pixel 7; oriole; oriole; en_US; 561394846)"
)


def _make_opts(quality: str, extractor_args: dict, ua: str = _CHROME_UA) -> dict:
    if quality == "mp3":
        fmt = "bestaudio/best"
    elif quality == "1080":
        fmt = (
            "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]"
            "/bestvideo[height<=1080]+bestaudio"
            "/best[height<=1080]/best"
        )
    else:
        fmt = (
            "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]"
            "/bestvideo[height<=720]+bestaudio"
            "/best[height<=720]/best"
        )

    opts: dict = {
        "format":                      fmt,
        "outtmpl":                     os.path.join(DOWNLOADS_DIR, "%(title).80s.%(ext)s"),
        "merge_output_format":         "mp4" if quality != "mp3" else None,
        "quiet":                       True,
        "no_warnings":                 True,
        "noplaylist":                  True,
        "nocheckcertificate":          True,
        "concurrent_fragment_downloads": 4,
        "extractor_args":              extractor_args,
        "http_headers": {
            "User-Agent":      ua,
            "Accept-Language": "en-US,en;q=0.9",
            "Accept":          "text/html,application/xhtml+xml,*/*;q=0.8",
        },
    }

    if quality == "mp3":
        opts["postprocessors"] = [
            {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "192"},
            {"key": "EmbedThumbnail"},
            {"key": "FFmpegMetadata"},
        ]
        opts["writethumbnail"] = True

    return opts


def _run_ydl(opts: dict, url: str) -> str:
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=True)
        path = ydl.prepare_filename(info)
        if opts.get("postprocessors"):
            path = path.rsplit(".", 1)[0] + ".mp3"
        return path


def _download_sync(url: str, quality: str) -> str:
    """3-tier cookieless fallback chain. Raises on total failure."""
    is_instagram = "instagram.com" in url.lower()

    # Tier 1 — mweb
    try:
        return _run_ydl(
            _make_opts(quality, {"youtube": {"player_client": ["mweb"]}}),
            url,
        )
    except Exception as e1:
        logger.warning("Tier 1 (mweb) failed: %s", e1)

    # Tier 2 — tv_embedded
    try:
        return _run_ydl(
            _make_opts(quality, {"youtube": {"player_client": ["tv_embedded"]}}),
            url,
        )
    except Exception as e2:
        logger.warning("Tier 2 (tv_embedded) failed: %s", e2)

    # Tier 3 — ios / Instagram GraphQL
    ua   = _INSTA_UA if is_instagram else _CHROME_UA
    args = {"youtube": {"player_client": ["ios"]}, "instagram": {"api": ["graphql"]}}
    try:
        return _run_ydl(_make_opts(quality, args, ua=ua), url)
    except Exception as e3:
        logger.warning("Tier 3 (ios/graphql) failed: %s", e3)
        raise  # Surface the final error to the handler


async def download_media(url: str, quality: str) -> str:
    return await asyncio.to_thread(_download_sync, url, quality)


# ══════════════════════════════════════════════════════════════
# GOOGLE DRIVE UPLOAD
# ══════════════════════════════════════════════════════════════

def _upload_sync(file_path: str, user_id: int) -> str | None:
    cred_file = os.path.join(CREDS_DIR, f"{user_id}.json")
    if not os.path.exists(cred_file):
        return None

    creds   = service_account.Credentials.from_service_account_file(
        cred_file, scopes=["https://www.googleapis.com/auth/drive.file"]
    )
    service = build("drive", "v3", credentials=creds)

    mime, _ = mimetypes.guess_type(file_path)
    mime    = mime or "application/octet-stream"
    req     = service.files().create(
        body={"name": os.path.basename(file_path), "parents": [DEFAULT_DRIVE_FOLDER_ID]},
        media_body=MediaFileUpload(file_path, mimetype=mime, resumable=True,
                                   chunksize=8 * 1024 * 1024),
        fields="id,webViewLink",
    )

    try:
        resp = None
        while resp is None:
            status, resp = req.next_chunk()
            if status:
                logger.info("Drive: %.0f%%", status.progress() * 100)
        return resp.get("webViewLink")
    except HttpError as e:
        if "storageQuotaExceeded" in str(e):
            raise RuntimeError(
                "❌ Drive quota exceeded.\n"
                "Ensure DEFAULT_DRIVE_FOLDER_ID is correct and the folder is "
                "shared with the Service Account (Editor permission)."
            )
        raise


async def upload_to_drive(file_path: str, user_id: int) -> str | None:
    return await asyncio.to_thread(_upload_sync, file_path, user_id)


# ══════════════════════════════════════════════════════════════
# HANDLERS
# ══════════════════════════════════════════════════════════════

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    uid = update.effective_user.id
    user_states[uid] = None
    await update.message.reply_text(
        "🖤 *BLACK TELBOT* 🤍\n_develop by Saeed Eramy_\n\nSelect an option:",
        reply_markup=ReplyKeyboardMarkup(MAIN_MENU, resize_keyboard=True),
        parse_mode="Markdown",
    )


async def handle_messages(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    uid   = update.message.from_user.id
    text  = update.message.text or ""
    state = user_states.get(uid)

    if text in (BTN_DL, BTN_UL, BTN_SETUP, BTN_ABOUT):
        user_states[uid] = None

        if text == BTN_ABOUT:
            await update.message.reply_text(
                "🖤 *BLACK TELBOT* 🤍\n"
                "*develop by Saeed Eramy*\n"
                "🐙 [github.com/saeederamy](https://github.com/saeederamy)\n"
                "🔗 [black-telbot repo](https://github.com/saeederamy/black-telbot)\n\n"
                "🪙 *LTC:* `ltc1qxhuvs6j0suvv50nqjsuujqlr3u4ekfmys2ydps`",
                parse_mode="Markdown",
                disable_web_page_preview=True,
            )
        elif text == BTN_DL:
            user_states[uid] = "WAIT_URL"
            await update.message.reply_text("🔗 Send the URL:")
        elif text == BTN_UL:
            if not os.path.exists(os.path.join(CREDS_DIR, f"{uid}.json")):
                await update.message.reply_text(
                    "⚠️ No credentials found.\nUse ⚙️ *Setup Credentials* first.",
                    parse_mode="Markdown",
                )
            else:
                user_states[uid] = "WAIT_FILE"
                await update.message.reply_text("📁 Send the file (up to 2 GB):")
        elif text == BTN_SETUP:
            user_states[uid] = "WAIT_JSON"
            await update.message.reply_text(
                "📎 Send your `credentials.json` from Google Cloud Console.",
                parse_mode="Markdown",
            )
        return

    if state == "WAIT_JSON" and update.message.document:
        f = await update.message.document.get_file()
        await f.download_to_drive(os.path.join(CREDS_DIR, f"{uid}.json"))
        user_states[uid] = None
        await update.message.reply_text("✅ Credentials saved!")
        return

    if state == "WAIT_URL" and text:
        user_urls[uid] = text
        kb = [
            [InlineKeyboardButton("🎬 1080p", callback_data="q_1080")],
            [InlineKeyboardButton("🎞️  720p", callback_data="q_720")],
            [InlineKeyboardButton("🎧 MP3",   callback_data="q_mp3")],
        ]
        await update.message.reply_text("📉 Choose quality:", reply_markup=InlineKeyboardMarkup(kb))
        return

    if state == "WAIT_FILE":
        attachment = update.message.document or update.message.video or update.message.audio
        if not attachment:
            await update.message.reply_text("⚠️ Please send a file.")
            return

        msg  = await update.message.reply_text("⏳ Receiving file…")
        name = getattr(attachment, "file_name", None) or "uploaded_file"
        path = os.path.join(DOWNLOADS_DIR, name)
        try:
            tg_file = await attachment.get_file()
            await tg_file.download_to_drive(path)
            await msg.edit_text("☁️ Uploading to Drive…")
            link = await upload_to_drive(path, uid)
            await msg.edit_text(
                f"✅ Upload complete!\n🔗 {link}" if link
                else "❌ Upload failed. Check credentials and FOLDER_ID."
            )
        except RuntimeError as e:
            await msg.edit_text(str(e))
        except Exception as e:
            logger.exception("Upload error")
            await msg.edit_text(f"❌ Error:\n{str(e)[:400]}")
        finally:
            if os.path.exists(path):
                os.remove(path)
            user_states[uid] = None


async def handle_callbacks(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query   = update.callback_query
    await query.answer()
    uid     = query.from_user.id
    quality = query.data.split("_")[1]
    url     = user_urls.get(uid)

    if not url:
        await query.edit_message_text("⚠️ Session expired. Send the URL again.")
        return

    await query.edit_message_text(f"⏳ Downloading ({quality.upper()})…")
    path = None
    try:
        path = await download_media(url, quality)
        await query.edit_message_text("📤 Sending…")
        with open(path, "rb") as f:
            if quality == "mp3":
                await context.bot.send_audio(chat_id=uid, audio=f)
            else:
                await context.bot.send_video(chat_id=uid, video=f, supports_streaming=True)
        try:
            await query.message.delete()
        except Exception:
            pass

    except Exception as e:
        err = str(e)
        logger.error("Download error: %s", err)
        if "Sign in" in err or "bot" in err.lower():
            hint = "❌ Platform rejected the download.\nThis video may be restricted or private."
        elif "private" in err.lower() or "login" in err.lower():
            hint = "❌ Content is private or requires login."
        elif "unavailable" in err.lower() or "not available" in err.lower():
            hint = "❌ Video is unavailable or has been removed."
        else:
            hint = f"❌ Download failed:\n`{err[:350]}`"
        await query.edit_message_text(hint, parse_mode="Markdown")

    finally:
        if path and os.path.exists(path):
            os.remove(path)
        user_urls.pop(uid, None)
        user_states[uid] = None


# ══════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════

def main() -> None:
    builder = Application.builder().token(BOT_TOKEN)
    if USE_LOCAL_API:
        builder = builder.base_url(f"{LOCAL_API_URL}/bot").local_mode(True)
    app = builder.build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT | filters.ATTACHMENT, handle_messages))
    app.add_handler(CallbackQueryHandler(handle_callbacks))
    logger.info("BLACK TELBOT starting — develop by Saeed Eramy")
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
