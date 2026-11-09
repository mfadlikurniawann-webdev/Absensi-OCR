# Absensi Face Recognition

Sistem absensi berbasis pengenalan wajah: **server Flask** (pencocokan wajah DeepFace Facenet)
dan **aplikasi mobile native Android & iOS** (Flutter, deteksi wajah + cek kedip on-device
dengan Google ML Kit).

![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-000000?style=flat-square&logo=flask&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-003B57?style=flat-square&logo=sqlite&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)

## Struktur monorepo

```
.
├── apps/
│   ├── server/              # Flask: REST API (/api) + halaman web, Dockerfile, tests
│   └── mobile/              # Flutter: aplikasi Android & iOS
├── deploy/Caddyfile         # reverse proxy + HTTPS otomatis
├── docker-compose.yml       # jalankan server (lokal / produksi)
├── .env.example             # konfigurasi server & deploy
└── .github/workflows/       # CI: server (test + image Docker), mobile (APK + iOS)
```

| Bagian | Dokumentasi |
| --- | --- |
| Server | [apps/server/README.md](apps/server/README.md) |
| Mobile | [apps/mobile/README.md](apps/mobile/README.md) |

## Mulai cepat (lokal)

**Server** (butuh Docker):

```bash
cp .env.example .env               # ganti SECRET_KEY & ADMIN_PASSWORD
docker compose up -d --build
curl http://localhost:5000/api/health
```

Halaman web: `http://localhost:5000/absen`, dashboard admin: `http://localhost:5000/login`.

**Aplikasi** (butuh Flutter 3.44+):

```bash
cd apps/mobile
flutter pub get
flutter run                         # HP Android via USB / emulator
```

Di aplikasi, ketuk ikon pengaturan lalu isi alamat server, mis. `http://192.168.1.10:5000`
(IP laptop di Wi-Fi yang sama) atau `http://10.0.2.2:5000` dari emulator.

## Deploy ke server (VPS)

Kebutuhan: VPS Linux (min. 2 GB RAM), Docker, dan domain yang DNS-nya mengarah ke IP VPS.
Port 80 dan 443 harus terbuka.

```bash
git clone https://github.com/mfadlikurniawann-webdev/Absensi-OCR.git
cd Absensi-OCR
cp .env.example .env
nano .env        # isi SECRET_KEY, ADMIN_PASSWORD, DOMAIN, dan API_BIND=127.0.0.1
docker compose --profile https up -d --build
```

Caddy otomatis mengambil sertifikat HTTPS (Let's Encrypt) untuk `DOMAIN`. Cek:
`curl https://DOMAIN/api/health`. Database tersimpan di volume Docker `absensi-data`.

Perintah lain:

```bash
docker compose logs -f api                      # lihat log
git pull && docker compose --profile https up -d --build   # update versi
```

Tanpa build di VPS: setiap push ke `main`, GitHub Actions menerbitkan image
`ghcr.io/mfadlikurniawann-webdev/absensi-ocr/server:latest`. Isi `API_IMAGE` di `.env`, lalu
`docker compose pull && docker compose --profile https up -d`. Untuk repo private, login dulu
dengan `docker login ghcr.io`.

**Memindahkan database lama** (`apps/server/data/absensi.db`) ke server:

```bash
docker compose cp ./apps/server/data/absensi.db api:/data/absensi.db
docker compose exec -u root api chown appuser:appuser /data/absensi.db
docker compose restart api
```

Platform lain (Render, Railway, Fly.io) bisa langsung memakai `apps/server/Dockerfile`,
karena server membaca port dari env `PORT`. Pasang persistent disk di `/data` agar database
tidak hilang.

## CI/CD (GitHub Actions)

| Workflow | Pemicu | Hasil |
| --- | --- | --- |
| **Server** (`server.yml`) | perubahan `apps/server/**` | pytest, lalu image Docker ke GHCR |
| **Mobile** (`mobile.yml`) | perubahan `apps/mobile/**` | analyze + test, APK rilis, `.ipa` iOS tanpa signing |

Isi repository variable `API_BASE_URL` (Settings → Secrets and variables → Actions → Variables),
misalnya `https://absensi.domainanda.com`, agar alamat server tertanam di APK/iOS hasil CI.
Artefak bisa diunduh di tab **Actions** → run terbaru → **Artifacts**.

## Rilis ke Play Store & App Store

Langkahnya ada di [apps/mobile/README.md](apps/mobile/README.md#rilis). Sebelum rilis: gunakan
server HTTPS, ganti ikon aplikasi, dan siapkan kebijakan privasi, karena aplikasi memproses
data biometrik wajah.

## Keamanan & privasi

- Database (`*.db`) dan file ekspor **tidak ikut di-commit** (lihat `.gitignore`), karena
  berisi data biometrik wajah.
- Ganti `SECRET_KEY` dan `ADMIN_PASSWORD` sebelum deploy, dan selalu gunakan HTTPS.
- Cek kedip mata di aplikasi mencegah absen dengan foto cetak, tetapi bukan anti-spoofing
  penuh.

## Kredit

Dikembangkan dari proyek [Absensi-FaceRecognition](https://github.com/HibbanRdn/Absensi-FaceRecognition)
oleh **Muhamad Hibban Ramadhan** (Teknik Informatika, Universitas Lampung).

## Lisensi

Open-source untuk keperluan pendidikan. Mohon sertakan atribusi bila digunakan di proyek lain.
Font Plus Jakarta Sans memakai SIL Open Font License (`apps/mobile/assets/fonts/OFL.txt`).
