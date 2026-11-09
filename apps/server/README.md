# Server

Flask yang melayani REST API untuk aplikasi mobile (`/api/...`) sekaligus halaman web
(`/absen`, `/register`, `/login`, `/dashboard`). Wajah dicocokkan dengan DeepFace **Facenet**
(ONNX Runtime, tanpa TensorFlow) memakai jarak cosine. Data disimpan di SQLite.

## Menjalankan tanpa Docker

```bash
cd apps/server
python -m venv .venv
.venv\Scripts\activate             # macOS/Linux: source .venv/bin/activate
pip install -r requirements-dev.txt
python app.py                      # http://0.0.0.0:5000
```

Database default ada di `data/absensi.db`. Bobot model (~90 MB) diunduh ke
`~/.deepface/weights` saat pertama kali dijalankan.

## Test

```bash
python tests/download_fixtures.py  # foto contoh untuk test pengenalan wajah
pytest -q
```

## Konfigurasi (environment variable)

| Variabel | Default | Keterangan |
| --- | --- | --- |
| `SECRET_KEY` | *(wajib ganti)* | Kunci session web & token admin |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | `admin` / `admin123` | Login admin (wajib ganti) |
| `DB_PATH` | `data/absensi.db` | Lokasi database (Docker: `/data/absensi.db`) |
| `APP_TIMEZONE` | `Asia/Jakarta` | Zona waktu pencatatan |
| `MATCH_THRESHOLD` | `0.40` | Batas jarak cosine; makin kecil makin ketat |
| `ATTENDANCE_COOLDOWN_MINUTES` | `5` | Absen ulang dalam rentang ini tidak dicatat dobel |
| `ALLOW_PUBLIC_REGISTER` | `true` | `false` = hanya admin yang bisa mendaftarkan wajah |
| `TOKEN_MAX_AGE_HOURS` | `12` | Masa berlaku login admin di aplikasi |
| `FACE_DETECTOR` | `opencv` | `retinaface` lebih akurat tapi lebih berat |
| `MAX_IMAGE_MB` | `8` | Ukuran maksimal foto |
| `PORT` | `5000` | Port server |

## REST API

| Method | Endpoint | Auth | Keterangan |
| --- | --- | --- | --- |
| GET | `/api/health` | – | Status server |
| POST | `/api/attendance` | – | Absen. Multipart `image` (atau JSON `{"image": base64}`) |
| POST | `/api/register` | –/admin | Daftar wajah. Multipart `name`, `npm`, `image` |
| POST | `/api/admin/login` | – | JSON `{"username","password"}` → `token` |
| GET | `/api/admin/summary` | Bearer | Statistik hari ini |
| GET | `/api/admin/attendance?date=YYYY-MM-DD&q=` | Bearer | Riwayat absensi |
| GET | `/api/admin/users` | Bearer | Pengguna terdaftar |
| DELETE | `/api/admin/users/<id>` | Bearer | Hapus pengguna & riwayatnya |
| GET | `/api/admin/export.csv?date=&q=` | Bearer | Export CSV |

Wajah tidak dikenali → `200` dengan `recognized: false`; foto tanpa wajah → `422`.

## Skrip

- `scripts/webcam_client.py` — absen/daftar dari webcam laptop lewat API.
- `scripts/legacy/` — skrip versi pertama (arsip, tidak kompatibel lagi).
