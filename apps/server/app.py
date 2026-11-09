"""
Backend Absensi Face Recognition.

Satu server melayani dua jenis klien:
  - Web (template Flask): /absen, /register, /login, /dashboard, /export/csv
  - Aplikasi mobile Android & iOS (REST API JSON): /api/...

Pengenalan wajah memakai DeepFace dengan model Facenet (embedding 128 dimensi)
dan jarak cosine, sama seperti versi sebelumnya, sehingga wajah yang sudah
terdaftar di absensi.db tetap dikenali.

Semua konfigurasi dibaca dari environment variable (lihat .env.example).
"""
import base64
import binascii
import csv
import hmac
import io
import json
import logging
import os
import re
import sqlite3
import sys
import threading
import traceback
from contextlib import contextmanager
from datetime import datetime, timedelta
from functools import wraps
from zoneinfo import ZoneInfo

import cv2
import numpy as np
from flask import (
    Flask,
    Response,
    jsonify,
    redirect,
    render_template,
    request,
    session,
    url_for,
)
from itsdangerous import BadSignature, URLSafeTimedSerializer

# ============================================================
# KONFIGURASI
# ============================================================
BASE_DIR = os.path.abspath(os.path.dirname(__file__))


def env_bool(name, default):
    value = os.environ.get(name)
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


DEFAULT_SECRET_KEY = "absensi_secret_key"
DEFAULT_ADMIN_PASSWORD = "admin123"

SECRET_KEY = os.environ.get("SECRET_KEY", DEFAULT_SECRET_KEY)
ADMIN_USERNAME = os.environ.get("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", DEFAULT_ADMIN_PASSWORD)
DB_PATH = os.environ.get("DB_PATH", os.path.join(BASE_DIR, "data", "absensi.db"))

# Model TIDAK dibuat configurable: embedding yang tersimpan di database dibuat
# dengan Facenet, model lain menghasilkan vektor yang tidak bisa dibandingkan.
FACE_MODEL = "Facenet"
FACE_DETECTOR = os.environ.get("FACE_DETECTOR", "opencv")
MATCH_THRESHOLD = float(os.environ.get("MATCH_THRESHOLD", "0.40"))
ATTENDANCE_COOLDOWN_MINUTES = int(os.environ.get("ATTENDANCE_COOLDOWN_MINUTES", "5"))
ALLOW_PUBLIC_REGISTER = env_bool("ALLOW_PUBLIC_REGISTER", True)
TOKEN_MAX_AGE_SECONDS = int(os.environ.get("TOKEN_MAX_AGE_HOURS", "12")) * 3600
APP_TIMEZONE = ZoneInfo(os.environ.get("APP_TIMEZONE", "Asia/Jakarta"))
MAX_IMAGE_MB = int(os.environ.get("MAX_IMAGE_MB", "8"))
PRELOAD_MODEL = env_bool("PRELOAD_MODEL", True)

API_VERSION = "1.0.0"
TIME_FMT = "%Y-%m-%d %H:%M:%S"
MAX_IMAGE_SIDE = 1280

app = Flask(
    __name__,
    template_folder=os.path.join(BASE_DIR, "templates"),
    static_folder=os.path.join(BASE_DIR, "static"),
)
app.secret_key = SECRET_KEY
app.config["MAX_CONTENT_LENGTH"] = MAX_IMAGE_MB * 1024 * 1024

# Logger DeepFace mencetak emoji; di konsol Windows (cp1252) hal itu bisa crash.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except (AttributeError, ValueError):
        pass

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("absensi")

if SECRET_KEY == DEFAULT_SECRET_KEY:
    log.warning("SECRET_KEY masih default. Ganti lewat environment variable sebelum deploy!")
if ADMIN_PASSWORD == DEFAULT_ADMIN_PASSWORD:
    log.warning("ADMIN_PASSWORD masih default (admin123). Ganti sebelum deploy!")


class ApiError(Exception):
    """Kesalahan yang pesannya aman ditampilkan ke pengguna."""

    def __init__(self, message, status=422):
        super().__init__(message)
        self.message = message
        self.status = status


# ============================================================
# DATABASE
# ============================================================
@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def init_db():
    """Buat tabel bila belum ada, dan lengkapi skema database lama."""
    db_dir = os.path.dirname(DB_PATH)
    if db_dir:
        os.makedirs(db_dir, exist_ok=True)
    with db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              embedding TEXT NOT NULL,
              npm TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS absensi (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              waktu TEXT NOT NULL,
              FOREIGN KEY (user_id) REFERENCES users(id)
            )
            """
        )
        # Database buatan train_faces.py tidak punya kolom npm.
        cols = [row["name"] for row in conn.execute("PRAGMA table_info(users)")]
        if "npm" not in cols:
            conn.execute("ALTER TABLE users ADD COLUMN npm TEXT")
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_absensi_user_waktu ON absensi(user_id, waktu)"
        )
        conn.commit()


init_db()


def now_local():
    return datetime.now(APP_TIMEZONE).replace(tzinfo=None)


def query_attendance(date=None, keyword=None, limit=None):
    sql = """
        SELECT a.id, a.user_id, u.name, u.npm, a.waktu
        FROM absensi a
        JOIN users u ON a.user_id = u.id
    """
    where, params = [], []
    if date:
        where.append("a.waktu LIKE ?")
        params.append(f"{date}%")
    if keyword:
        where.append("(u.name LIKE ? OR u.npm LIKE ?)")
        params += [f"%{keyword}%", f"%{keyword}%"]
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY a.waktu DESC, a.id DESC"
    if limit:
        sql += " LIMIT ?"
        params.append(limit)
    with db() as conn:
        return [dict(row) for row in conn.execute(sql, params)]


def build_csv(rows):
    buf = io.StringIO()
    buf.write("﻿")  # BOM agar Excel membaca UTF-8 dengan benar
    writer = csv.writer(buf)
    writer.writerow(["ID", "Name", "NPM", "Waktu"])
    for row in rows:
        writer.writerow([row["id"], row["name"], row["npm"] or "", row["waktu"]])
    return buf.getvalue()


def csv_response(rows):
    return Response(
        build_csv(rows),
        mimetype="text/csv",
        headers={"Content-Disposition": "attachment; filename=absensi.csv"},
    )


# ============================================================
# PENGENALAN WAJAH
# ============================================================
_face_lock = threading.Lock()


def _deepface():
    # Import ditunda karena memuat model cukup berat; server tetap cepat start.
    from deepface import DeepFace

    return DeepFace


def warmup_model():
    try:
        with _face_lock:
            _deepface().build_model(FACE_MODEL)
        log.info("Model %s siap digunakan.", FACE_MODEL)
    except Exception:
        log.exception("Gagal memuat model %s saat warmup", FACE_MODEL)


def decode_image(data):
    if not data:
        raise ApiError("Foto wajah kosong.", 400)
    img = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise ApiError("File gambar tidak valid.", 400)
    h, w = img.shape[:2]
    if max(h, w) > MAX_IMAGE_SIDE:
        scale = MAX_IMAGE_SIDE / max(h, w)
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    return img


def extract_embedding(img):
    """Kembalikan embedding wajah terbesar di gambar."""
    try:
        with _face_lock:
            reps = _deepface().represent(
                img_path=img,
                model_name=FACE_MODEL,
                detector_backend=FACE_DETECTOR,
                enforce_detection=True,
            )
    except ValueError as exc:
        # DeepFace melempar FaceNotDetected (turunan ValueError) bila wajah tidak
        # terdeteksi. ValueError lain (mis. gagal unduh model) tetap jadi error 500.
        if "could not be detected" not in str(exc):
            raise
        raise ApiError(
            "Wajah tidak terdeteksi. Pastikan pencahayaan cukup."
        ) from exc
    if not reps:
        raise ApiError("Wajah tidak terdeteksi.")

    def area(rep):
        fa = rep.get("facial_area") or {}
        return fa.get("w", 0) * fa.get("h", 0)

    return np.asarray(max(reps, key=area)["embedding"], dtype=np.float64)


def cosine_distance(a, b):
    denom = np.linalg.norm(a) * np.linalg.norm(b)
    if denom == 0:
        return 1.0
    return float(1.0 - np.dot(a, b) / denom)


def find_best_match(conn, embedding):
    """Cari user dengan jarak cosine terkecil. Kembalikan (row|None, jarak|None)."""
    best, best_dist = None, None
    for row in conn.execute("SELECT id, name, npm, embedding FROM users"):
        try:
            stored = np.asarray(json.loads(row["embedding"]), dtype=np.float64)
        except (TypeError, ValueError):
            continue  # embedding rusak, lewati
        if stored.shape != embedding.shape:
            continue
        dist = cosine_distance(embedding, stored)
        if best_dist is None or dist < best_dist:
            best, best_dist = row, dist
    if best is not None and best_dist < MATCH_THRESHOLD:
        return best, best_dist
    return None, best_dist


def record_attendance(conn, user_id):
    """Simpan absensi. Kembalikan (waktu, baru_dicatat)."""
    now = now_local()
    if ATTENDANCE_COOLDOWN_MINUTES > 0:
        last = conn.execute(
            "SELECT waktu FROM absensi WHERE user_id = ? ORDER BY waktu DESC LIMIT 1",
            (user_id,),
        ).fetchone()
        if last:
            try:
                elapsed = now - datetime.strptime(last["waktu"], TIME_FMT)
                if timedelta(0) <= elapsed < timedelta(minutes=ATTENDANCE_COOLDOWN_MINUTES):
                    return last["waktu"], False
            except ValueError:
                pass
    waktu = now.strftime(TIME_FMT)
    conn.execute("INSERT INTO absensi (user_id, waktu) VALUES (?, ?)", (user_id, waktu))
    conn.commit()
    return waktu, True


def attendance_by_face(img_bytes):
    embedding = extract_embedding(decode_image(img_bytes))
    with db() as conn:
        user, dist = find_best_match(conn, embedding)
        if user is None:
            return {
                "success": False,
                "recognized": False,
                "message": "Wajah tidak dikenali.",
            }, 200
        waktu, created = record_attendance(conn, user["id"])
    if created:
        message = "Absensi tercatat."
    else:
        message = "Sudah absen sebelumnya."
    return {
        "success": True,
        "recognized": True,
        "already_recorded": not created,
        "user_id": user["id"],
        "name": user["name"],
        "npm": user["npm"],
        "waktu": waktu,
        "distance": round(dist, 4),
        "message": message,
    }, 200


def register_face(name, npm, img_bytes):
    name = (name or "").strip()
    npm = (npm or "").strip()
    if not name or not npm:
        raise ApiError("Nama dan NPM wajib diisi.", 400)
    if len(name) > 100 or len(npm) > 50:
        raise ApiError("Nama atau NPM terlalu panjang.", 400)

    with db() as conn:
        same_npm = conn.execute("SELECT name FROM users WHERE npm = ?", (npm,)).fetchone()
    if same_npm:
        raise ApiError(f"NPM {npm} sudah terdaftar.", 409)

    embedding = extract_embedding(decode_image(img_bytes))
    with db() as conn:
        user, _ = find_best_match(conn, embedding)
        if user is not None:
            raise ApiError(
                f"Wajah ini sudah terdaftar atas nama {user['name']}.", 409
            )
        cur = conn.execute(
            "INSERT INTO users (name, npm, embedding) VALUES (?, ?, ?)",
            (name, npm, json.dumps(embedding.tolist())),
        )
        conn.commit()
        user_id = cur.lastrowid
    return {
        "success": True,
        "message": "Registrasi berhasil.",
        "user": {"id": user_id, "name": name, "npm": npm},
    }, 201


def image_from_request():
    """Ambil foto dari multipart (field 'image') atau JSON base64 {"image": "..."}."""
    file = request.files.get("image")
    if file:
        return file.read()
    data = request.get_json(silent=True) or {}
    encoded = data.get("image")
    if isinstance(encoded, str) and encoded:
        encoded = re.sub(r"^data:image/[^;]+;base64,", "", encoded)
        try:
            return base64.b64decode(encoded)
        except (binascii.Error, ValueError):
            raise ApiError("Format gambar base64 tidak valid.", 400)
    raise ApiError("Foto wajah wajib dikirim (field 'image').", 400)


def run_face_task(task):
    """Jalankan task wajah dan ubah semua hasil/kesalahan menjadi respons JSON."""
    try:
        payload, status = task()
        return jsonify(payload), status
    except ApiError as exc:
        return jsonify({"success": False, "recognized": False, "message": exc.message}), exc.status
    except Exception:
        log.exception("Kesalahan saat memproses wajah")
        body = {
            "success": False,
            "recognized": False,
            "message": "Terjadi kesalahan di server.",
        }
        if app.debug:
            body["trace"] = traceback.format_exc()
        return jsonify(body), 500


# ============================================================
# AUTENTIKASI ADMIN (session untuk web, Bearer token untuk mobile)
# ============================================================
_token_serializer = URLSafeTimedSerializer(SECRET_KEY, salt="absensi-admin-token")


def check_admin_credentials(username, password):
    user_ok = hmac.compare_digest((username or "").encode(), ADMIN_USERNAME.encode())
    pass_ok = hmac.compare_digest((password or "").encode(), ADMIN_PASSWORD.encode())
    return user_ok and pass_ok


def is_admin_request():
    if session.get("admin"):
        return True
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return False
    try:
        data = _token_serializer.loads(auth[7:].strip(), max_age=TOKEN_MAX_AGE_SECONDS)
    except BadSignature:  # termasuk token kedaluwarsa
        return False
    return isinstance(data, dict) and data.get("role") == "admin"


def admin_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not is_admin_request():
            return jsonify(
                {"success": False, "message": "Sesi admin habis. Silakan masuk lagi."}
            ), 401
        return view(*args, **kwargs)

    return wrapper


def registration_forbidden():
    if ALLOW_PUBLIC_REGISTER or is_admin_request():
        return None
    return jsonify(
        {"success": False, "message": "Pendaftaran hanya oleh admin."}
    ), 403


# ============================================================
# REST API UNTUK APLIKASI MOBILE
# ============================================================
@app.get("/api/health")
def api_health():
    return jsonify(
        {
            "status": "ok",
            "app": "absensi-face-recognition",
            "version": API_VERSION,
            "public_register": ALLOW_PUBLIC_REGISTER,
            "server_time": now_local().strftime(TIME_FMT),
        }
    )


@app.post("/api/attendance")
def api_attendance():
    return run_face_task(lambda: attendance_by_face(image_from_request()))


@app.post("/api/register")
def api_register():
    forbidden = registration_forbidden()
    if forbidden:
        return forbidden
    return run_face_task(
        lambda: register_face(request.form.get("name"), request.form.get("npm"), image_from_request())
    )


@app.post("/api/admin/login")
def api_admin_login():
    data = request.get_json(silent=True) or request.form
    if not check_admin_credentials(data.get("username"), data.get("password")):
        return jsonify({"success": False, "message": "Username atau password salah."}), 401
    token = _token_serializer.dumps({"role": "admin", "u": ADMIN_USERNAME})
    return jsonify({"success": True, "token": token, "expires_in": TOKEN_MAX_AGE_SECONDS})


@app.get("/api/admin/summary")
@admin_required
def api_admin_summary():
    today = now_local().strftime("%Y-%m-%d")
    with db() as conn:
        total_users = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        total_attendance = conn.execute("SELECT COUNT(*) FROM absensi").fetchone()[0]
        today_row = conn.execute(
            "SELECT COUNT(*), COUNT(DISTINCT user_id) FROM absensi WHERE waktu LIKE ?",
            (f"{today}%",),
        ).fetchone()
    return jsonify(
        {
            "success": True,
            "date": today,
            "total_users": total_users,
            "total_attendance": total_attendance,
            "attendance_today": today_row[0],
            "present_today": today_row[1],
        }
    )


@app.get("/api/admin/attendance")
@admin_required
def api_admin_attendance():
    date = (request.args.get("date") or "").strip() or None
    if date and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
        return jsonify({"success": False, "message": "Format tanggal harus YYYY-MM-DD."}), 400
    keyword = (request.args.get("q") or "").strip() or None
    try:
        limit = max(1, min(int(request.args.get("limit", 500)), 5000))
    except ValueError:
        limit = 500
    rows = query_attendance(date, keyword, limit)
    return jsonify({"success": True, "count": len(rows), "data": rows})


@app.get("/api/admin/users")
@admin_required
def api_admin_users():
    with db() as conn:
        rows = conn.execute(
            """
            SELECT u.id, u.name, u.npm,
                   COUNT(a.id) AS total_attendance,
                   MAX(a.waktu) AS last_attendance
            FROM users u
            LEFT JOIN absensi a ON a.user_id = u.id
            GROUP BY u.id
            ORDER BY u.name COLLATE NOCASE
            """
        ).fetchall()
    return jsonify({"success": True, "data": [dict(r) for r in rows]})


@app.delete("/api/admin/users/<int:user_id>")
@admin_required
def api_admin_delete_user(user_id):
    with db() as conn:
        user = conn.execute("SELECT name FROM users WHERE id = ?", (user_id,)).fetchone()
        if user is None:
            return jsonify({"success": False, "message": "Pengguna tidak ditemukan."}), 404
        conn.execute("DELETE FROM absensi WHERE user_id = ?", (user_id,))
        conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
        conn.commit()
    return jsonify({"success": True, "message": f"Data {user['name']} berhasil dihapus."})


@app.get("/api/admin/export.csv")
@admin_required
def api_admin_export():
    date = (request.args.get("date") or "").strip() or None
    if date and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
        return jsonify({"success": False, "message": "Format tanggal harus YYYY-MM-DD."}), 400
    return csv_response(query_attendance(date, (request.args.get("q") or "").strip() or None))


# ============================================================
# HALAMAN WEB (tetap kompatibel dengan template lama)
# ============================================================
@app.route("/")
def index():
    return redirect(url_for("absen"))


@app.route("/absen")
def absen():
    return render_template("absen.html")


@app.route("/absensi", methods=["GET", "POST"])
def absensi():
    if request.method == "GET":
        # Data absensi hanya untuk admin (dipakai dashboard web).
        if not is_admin_request():
            return jsonify({"success": False, "message": "Login admin diperlukan."}), 401
        return jsonify(query_attendance())

    data = request.get_json(silent=True) or {}

    # Absen langsung via user_id (tanpa wajah) hanya boleh oleh admin,
    # supaya tidak bisa dipakai untuk titip absen.
    if "user_id" in data:
        if not is_admin_request():
            return jsonify({"recognized": False, "message": "Login admin diperlukan."}), 401
        try:
            user_id = int(data["user_id"])
        except (TypeError, ValueError):
            return jsonify({"recognized": False, "message": "user_id tidak valid"}), 400
        with db() as conn:
            user = conn.execute("SELECT name, npm FROM users WHERE id = ?", (user_id,)).fetchone()
            if user is None:
                return jsonify({"recognized": False, "message": "User tidak ditemukan"}), 404
            waktu, _ = record_attendance(conn, user_id)
        return jsonify({"recognized": True, "name": user["name"], "npm": user["npm"], "waktu": waktu})

    if "image" in data or request.files.get("image"):
        return run_face_task(lambda: attendance_by_face(image_from_request()))

    return jsonify({"recognized": False, "message": "Format data tidak dikenali"}), 400


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "GET":
        return render_template("register.html")
    forbidden = registration_forbidden()
    if forbidden:
        return forbidden
    return run_face_task(
        lambda: register_face(request.form.get("name"), request.form.get("npm"), image_from_request())
    )


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        if check_admin_credentials(request.form.get("username"), request.form.get("password")):
            session["admin"] = True
            return redirect(url_for("dashboard"))
        return render_template("login.html", error="Username atau password salah")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.pop("admin", None)
    return redirect(url_for("login"))


@app.route("/dashboard")
def dashboard():
    if not session.get("admin"):
        return redirect(url_for("login"))
    return render_template("dashboard.html")


@app.route("/export/csv")
def export_absensi():
    if not session.get("admin"):
        return redirect(url_for("login"))
    return csv_response(query_attendance())


# ============================================================
# ERROR HANDLER (JSON untuk /api)
# ============================================================
@app.errorhandler(413)
def too_large(_):
    return jsonify({"success": False, "message": f"Ukuran foto maksimal {MAX_IMAGE_MB} MB."}), 413


@app.errorhandler(404)
def not_found(err):
    if request.path.startswith("/api/"):
        return jsonify({"success": False, "message": "Endpoint tidak ditemukan."}), 404
    return err


@app.errorhandler(405)
def method_not_allowed(err):
    if request.path.startswith("/api/"):
        return jsonify({"success": False, "message": "Metode HTTP tidak diizinkan."}), 405
    return err


if PRELOAD_MODEL:
    threading.Thread(target=warmup_model, daemon=True).start()


# ============================================================
# MAIN (mode development). Produksi memakai gunicorn, lihat Dockerfile.
# ============================================================
if __name__ == "__main__":
    app.run(
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "5000")),
        debug=env_bool("FLASK_DEBUG", False),
    )
