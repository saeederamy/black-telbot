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
import subprocess

from telegram import (
    Update, ReplyKeyboardMarkup,
    InlineKeyboardButton, InlineKeyboardMarkup,
)
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

# Drive folder ID — "DRIVE_FOLDER_DISABLED" = Drive feature hidden from menu
DEFAULT_DRIVE_FOLDER_ID = "DRIVE_FOLDER_DISABLED"

# bgutil PO Token server (systemd: bgutil-pot.service)
BGUTIL_SERVER      = "http://127.0.0.1:4416"
BGUTIL_SERVER_HOME = os.path.join(BOT_DIR, "bgutil-pot", "server")

# Optional outbound proxy for yt-dlp (e.g. "http://127.0.0.1:1088").
# Leave empty to connect directly. Only set this if a proxy is actually
# running — pointing at a dead proxy makes every download fail.
YTDLP_PROXY = ""

os.makedirs(CREDS_DIR,     exist_ok=True)
os.makedirs(DOWNLOADS_DIR, exist_ok=True)

DRIVE_ENABLED = DEFAULT_DRIVE_FOLDER_ID not in ("", "DRIVE_FOLDER_DISABLED")

# ──────────────────────────────────────────────────────────────
# STATE STORES
# ──────────────────────────────────────────────────────────────
user_states: dict[int, str | None] = {}
user_urls:   dict[int, str]        = {}

# ──────────────────────────────────────────────────────────────
# MENU
# ──────────────────────────────────────────────────────────────
BTN_DL    = "🎬  Download"
BTN_UL    = "☁️  Upload to Drive"
BTN_SETUP = "🔑  Drive Setup"
BTN_ABOUT = "🖤  About"


def build_menu() -> ReplyKeyboardMarkup:
    rows = [[BTN_DL]]
    if DRIVE_ENABLED:
        rows.append([BTN_UL, BTN_SETUP])
    rows.append([BTN_ABOUT])
    return ReplyKeyboardMarkup(rows, resize_keyboard=True)


# ══════════════════════════════════════════════════════════════
# DOWNLOAD ENGINE
# ══════════════════════════════════════════════════════════════

_INSTA_UA = (
    "Instagram 319.0.0.45.109 Android (33/13; 420dpi; 1080x2400; "
    "Google/google; Pixel 7; oriole; oriole; en_US; 561394846)"
)

QUALITY_MAP = {
    "1080": (
        "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]"
        "/bestvideo[height<=1080]+bestaudio/best[height<=1080]/best"
    ),
    "720": (
        "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]"
        "/bestvideo[height<=720]+bestaudio/best[height<=720]/best"
    ),
    "480": (
        "bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]"
        "/bestvideo[height<=480]+bestaudio/best[height<=480]/best"
    ),
    "360": (
        "bestvideo[height<=360][ext=mp4]+bestaudio[ext=m4a]"
        "/bestvideo[height<=360]+bestaudio/best[height<=360]/best"
    ),
    "mp3": "bestaudio/best",
}


def _is_spotify(url: str) -> bool:
    return "spotify.com" in url.lower()


YTDLP_BIN  = os.path.join(BOT_DIR, "venv", "bin", "yt-dlp")
SPOTDL_BIN = os.path.join(BOT_DIR, "venv", "bin", "spotdl")

# Cookies file (optional but recommended for authenticated sessions)
COOKIES_FILE = os.path.join(BOT_DIR, "cookies.txt")


def _yt_engine_args() -> list[str]:
    """
    Shared yt-dlp args that make YouTube work from a datacenter/server IP.

    Used both for direct yt-dlp downloads and, joined into a string, for
    spotdl's --yt-dlp-args (spotdl pulls the audio from YouTube under the
    hood, so it hits the exact same bot-check and needs the same fix).
    """
    args = [
        "--no-check-certificate",
        "--js-runtimes", "node",
        "--remote-components", "ejs:github",
        "--extractor-args", "youtube:player_client=mweb,tv_simply,web",
        "--extractor-args", f"youtubepot-bgutilhttp:base_url={BGUTIL_SERVER}",
        "--extractor-args", f"youtubepot-bgutilscript:server_home={BGUTIL_SERVER_HOME}",
    ]
    if YTDLP_PROXY:
        args += ["--proxy", YTDLP_PROXY, "--geo-verification-proxy", YTDLP_PROXY]
    return args


def _spotify_download_sync(url: str) -> str:
    spotdl_cmd = SPOTDL_BIN if os.path.isfile(SPOTDL_BIN) else "spotdl"
    cmd = [
        spotdl_cmd, "download", url,
        "--output", DOWNLOADS_DIR,
        "--format", "mp3",
        "--bitrate", "192k",
        "--no-cache",
        "--yt-dlp-args", " ".join(_yt_engine_args()),
    ]
    if os.path.isfile(COOKIES_FILE):
        cmd += ["--cookie-file", COOKIES_FILE]
    result = subprocess.run(
        cmd, capture_output=True, text=True, timeout=600,
    )
    if result.returncode != 0:
        raise RuntimeError(f"spotdl error:\n{(result.stderr or result.stdout)[:400]}")
    mp3s = sorted(
        [os.path.join(DOWNLOADS_DIR, f) for f in os.listdir(DOWNLOADS_DIR) if f.endswith(".mp3")],
        key=os.path.getmtime, reverse=True,
    )
    if not mp3s:
        raise RuntimeError("spotdl finished but no MP3 found.")
    return mp3s[0]



def _ydl_download_sync(url: str, quality: str) -> str:
    """
    Call yt-dlp binary directly via subprocess.

    What makes YouTube work from a datacenter/server IP (no VPN):
    - --js-runtimes node          : Node.js runtime for the challenge solver
    - --remote-components ejs:github : fetches the EJS signature / n-sig solver
    - player_client=mweb,tv_simply,web : clients that expose plain-https
                                    adaptive formats and accept a PO Token
                                    (plain web only yields the 403-prone
                                     legacy format 18; tv is DRM-only)
    - youtubepot-bgutilhttp       : local bgutil server provides the PO Token
                                    (needs bgutil-pot.service + the
                                     bgutil-ytdlp-pot-provider yt-dlp plugin)
    - cookies.txt                 : logged-in fallback. REQUIRED for videos /
                                    server IPs that YouTube has flagged: once
                                    flagged, the PO Token alone is not enough
                                    and the CDN returns HTTP 403.

    NOTE: no proxy is used by default. Routing through a proxy that is not
    actually running makes every request fail with "connection refused".
    Set YTDLP_PROXY only if you really have a proxy listening.
    """
    fmt = QUALITY_MAP[quality]
    is_instagram = "instagram.com" in url.lower()

    cmd = [
        YTDLP_BIN if os.path.isfile(YTDLP_BIN) else "yt-dlp",
        "--format", fmt,
        "--output", os.path.join(DOWNLOADS_DIR, "%(title).80s.%(ext)s"),
        "--no-playlist",
        "--concurrent-fragments", "4",
    ] + _yt_engine_args()

    # Add cookies if available
    if os.path.isfile(COOKIES_FILE):
        cmd += ["--cookies", COOKIES_FILE]

    if is_instagram:
        cmd += ["--user-agent", _INSTA_UA,
                "--extractor-args", "instagram:api=graphql"]

    if quality != "mp3":
        cmd += ["--merge-output-format", "mp4"]
    else:
        cmd += [
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", "192K",
            "--embed-thumbnail",
            "--add-metadata",
        ]

    cmd.append(url)

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)

    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())

    # Find the newest file in downloads dir
    files = sorted(
        [os.path.join(DOWNLOADS_DIR, f) for f in os.listdir(DOWNLOADS_DIR)],
        key=os.path.getmtime, reverse=True,
    )
    if not files:
        raise RuntimeError("Download finished but no file found.")
    return files[0]


def _download_sync(url: str, quality: str) -> str:
    if _is_spotify(url):
        return _spotify_download_sync(url)
    return _ydl_download_sync(url, quality)


async def download_media(url: str, quality: str) -> str:
    return await asyncio.to_thread(_download_sync, url, quality)


# ══════════════════════════════════════════════════════════════
# GOOGLE DRIVE UPLOAD
# ══════════════════════════════════════════════════════════════

def _upload_sync(file_path: str, user_id: int) -> str | None:
    cred_file = os.path.join(CREDS_DIR, f"{user_id}.json")
    if not os.path.exists(cred_file):
        return None
    creds = service_account.Credentials.from_service_account_file(
        cred_file, scopes=["https://www.googleapis.com/auth/drive.file"]
    )
    service = build("drive", "v3", credentials=creds)
    mime, _ = mimetypes.guess_type(file_path)
    mime = mime or "application/octet-stream"
    req = service.files().create(
        body={"name": os.path.basename(file_path), "parents": [DEFAULT_DRIVE_FOLDER_ID]},
        media_body=MediaFileUpload(file_path, mimetype=mime, resumable=True, chunksize=8 * 1024 * 1024),
        fields="id,webViewLink",
    )
    try:
        resp = None
        while resp is None:
            status, resp = req.next_chunk()
            if status:
                logger.info("Drive upload: %.0f%%", status.progress() * 100)
        return resp.get("webViewLink")
    except HttpError as e:
        if "storageQuotaExceeded" in str(e):
            raise RuntimeError("Drive quota exceeded. Make sure the folder is shared with the Service Account.")
        raise


async def upload_to_drive(file_path: str, user_id: int) -> str | None:
    return await asyncio.to_thread(_upload_sync, file_path, user_id)


# ══════════════════════════════════════════════════════════════
# UI TEXTS
# ══════════════════════════════════════════════════════════════

WELCOME = (
    "🖤 *BLACK TELBOT* 🤍\n"
    "━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    "*Media Downloader & Drive Uploader*\n\n"
    "🎬 *Download from:*\n"
    "  ▸ YouTube  \\|  Instagram\n"
    "  ▸ Twitter  \\|  Spotify\n"
    "  ▸ \\+1000 other sites\n\n"
    "📥 Quality: *360p to 1080p* and *MP3*\n\n"
    "━━━━━━━━━━━━━━━━━━━━━━━━\n"
    "👨‍💻 *develop by* [Saeed Eramy](https://github.com/saeederamy)\n"
    "━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    "Choose an option 👇"
)

ABOUT_TEXT = (
    "🖤 *BLACK TELBOT* 🤍\n"
    "━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    "Advanced media downloader & Google Drive uploader bot\\.\n\n"
    "✦ YouTube, Instagram, Twitter\n"
    "✦ Spotify \\(DRM\\-free via spotdl\\)\n"
    "✦ Quality: 360p → 1080p and MP3\n"
    "✦ Upload up to 2GB to personal Google Drive\n"
    "✦ YouTube via bgutil PO Token \\(no IP blocks\\)\n\n"
    "━━━━━━━━━━━━━━━━━━━━━━━━\n"
    "👨‍💻 *develop by* [Saeed Eramy](https://github.com/saeederamy)\n"
    "📦 [black\\-telbot](https://github.com/saeederamy/black-telbot)\n\n"
    "🪙 *LTC:*\n"
    "`ltc1qxhuvs6j0suvv50nqjsuujqlr3u4ekfmys2ydps`"
)


def quality_keyboard(is_spotify: bool = False) -> InlineKeyboardMarkup:
    if is_spotify:
        return InlineKeyboardMarkup([
            [InlineKeyboardButton("🎵  Download MP3", callback_data="q_mp3")]
        ])
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("🎬 1080p", callback_data="q_1080"),
            InlineKeyboardButton("🎞 720p",  callback_data="q_720"),
        ],
        [
            InlineKeyboardButton("📹 480p",  callback_data="q_480"),
            InlineKeyboardButton("📱 360p",  callback_data="q_360"),
        ],
        [InlineKeyboardButton("🎧 MP3 — 192kbps", callback_data="q_mp3")],
    ])


# ══════════════════════════════════════════════════════════════
# HANDLERS
# ══════════════════════════════════════════════════════════════

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    uid = update.effective_user.id
    user_states[uid] = None
    await update.message.reply_text(
        WELCOME,
        reply_markup=build_menu(),
        parse_mode="MarkdownV2",
        disable_web_page_preview=True,
    )


async def handle_messages(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    uid   = update.message.from_user.id
    text  = update.message.text or ""
    state = user_states.get(uid)

    if text in (BTN_DL, BTN_UL, BTN_SETUP, BTN_ABOUT):
        user_states[uid] = None

        if text == BTN_ABOUT:
            await update.message.reply_text(ABOUT_TEXT, parse_mode="MarkdownV2", disable_web_page_preview=True)

        elif text == BTN_DL:
            user_states[uid] = "WAIT_URL"
            await update.message.reply_text(
                "🔗 *Send the link:*\n\nYouTube \\| Instagram \\| Twitter \\| Spotify \\| \\.\\.\\.",
                parse_mode="MarkdownV2",
            )

        elif text == BTN_UL:
            if not DRIVE_ENABLED:
                await update.message.reply_text("Drive is not configured on this bot.")
                return
            if not os.path.exists(os.path.join(CREDS_DIR, f"{uid}.json")):
                await update.message.reply_text(
                    "No credentials found\\. Use 🔑 *Drive Setup* first\\.",
                    parse_mode="MarkdownV2",
                )
            else:
                user_states[uid] = "WAIT_FILE"
                await update.message.reply_text("Send your file \\(up to 2 GB\\):", parse_mode="MarkdownV2")

        elif text == BTN_SETUP:
            if not DRIVE_ENABLED:
                await update.message.reply_text("Drive is not configured on this bot.")
                return
            user_states[uid] = "WAIT_JSON"
            await update.message.reply_text(
                "Send your `credentials\\.json` from Google Cloud Console\\.",
                parse_mode="MarkdownV2",
            )
        return

    if state == "WAIT_JSON" and update.message.document:
        f = await update.message.document.get_file()
        await f.download_to_drive(os.path.join(CREDS_DIR, f"{uid}.json"))
        user_states[uid] = None
        await update.message.reply_text("Credentials saved\\!", parse_mode="MarkdownV2")
        return

    if state == "WAIT_URL" and text:
        user_urls[uid] = text
        is_spotify = _is_spotify(text)
        header = "🎵 *Spotify detected:*" if is_spotify else "📉 *Choose quality:*"
        await update.message.reply_text(header, reply_markup=quality_keyboard(is_spotify), parse_mode="MarkdownV2")
        return

    if state == "WAIT_FILE":
        attachment = update.message.document or update.message.video or update.message.audio
        if not attachment:
            await update.message.reply_text("Please send a file\\.", parse_mode="MarkdownV2")
            return

        msg  = await update.message.reply_text("Receiving file...")
        name = getattr(attachment, "file_name", None) or "uploaded_file"
        path = os.path.join(DOWNLOADS_DIR, name)
        try:
            tg_file = await attachment.get_file()
            await tg_file.download_to_drive(path)
            await msg.edit_text("Uploading to Drive...")
            link = await upload_to_drive(path, uid)
            await msg.edit_text(f"Upload complete\\!\n{link}" if link else "Upload failed\\.")
        except RuntimeError as e:
            await msg.edit_text(str(e))
        except Exception as e:
            logger.exception("Upload error")
            await msg.edit_text(f"Error:\n{str(e)[:400]}")
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
        await query.edit_message_text("Session expired. Please send the link again.")
        return

    label = "Spotify MP3" if _is_spotify(url) else quality.upper()
    await query.edit_message_text(f"Downloading ({label})...")

    path = None
    try:
        path = await download_media(url, quality)
        await query.edit_message_text("Sending to Telegram...")
        with open(path, "rb") as f:
            if quality == "mp3" or path.endswith(".mp3"):
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
        low = err.lower()
        blocked = any(s in low for s in (
            "sign in to confirm", "not a bot", "please sign in",
            "http error 403", "403: forbidden", "use --cookies",
        ))
        if blocked and "youtu" in url.lower():
            hint = (
                "YouTube blocked this video.\n\n"
                "The PO Token is active, but YouTube has flagged this "
                "server's IP for this video — for flagged IPs a logged-in "
                "account is required.\n\n"
                "Fix: on the server run  black-telbot , choose option [6] "
                "(YouTube — Cookies), paste a fresh cookies.txt, then retry. "
                "Most other videos still work without cookies."
            )
            await query.edit_message_text(hint)
        else:
            await query.edit_message_text(
                f"Download failed:\n`{err[:400]}`", parse_mode="Markdown"
            )

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
