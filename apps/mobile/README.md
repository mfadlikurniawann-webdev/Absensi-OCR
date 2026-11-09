# Mobile

Aplikasi Flutter untuk Android & iOS. Deteksi wajah dan cek kedip mata berjalan di HP
(Google ML Kit), lalu foto dikirim ke [server](../server) untuk dicocokkan.

## Menjalankan

```bash
cd apps/mobile
flutter pub get
flutter run
```

Alamat server diatur dari ikon pengaturan di beranda, atau ditanam saat build:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://absensi.domainanda.com
```

Default `http://10.0.2.2:5000`, yaitu komputer host bila dijalankan dari emulator Android.

### iOS (di macOS)

Plugin ML Kit memakai Swift Package Manager dan butuh file model yang diunduh sekali:

```bash
bash ios/download_mlkit_bundles.sh
flutter build ios --release
```

iOS minimum 15.5, dan ML Kit harus diuji di iPhone fisik. Tanpa Mac, build iOS berjalan di
GitHub Actions (workflow **Mobile**).

## Rilis

**Google Play**

1. Buat keystore sekali, simpan baik-baik, dan jangan di-commit:
   ```bash
   keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Salin `android/key.properties.example` menjadi `android/key.properties`, lalu isi passwordnya.
3. Build dan upload `build/app/outputs/bundle/release/app-release.aab` ke Play Console:
   ```bash
   flutter build appbundle --release --dart-define=API_BASE_URL=https://absensi.domainanda.com
   ```

**App Store** — butuh Mac dan akun Apple Developer. Jalankan langkah iOS di atas, buka
`ios/Runner.xcworkspace`, pilih Team di *Signing & Capabilities*, lalu
**Product → Archive → Distribute App**.

**Sebelum rilis**

- Pakai server HTTPS, lalu hapus `android:usesCleartextTraffic="true"` di
  `android/app/src/main/AndroidManifest.xml`.
- Sesuaikan Application ID / Bundle ID bila perlu (`id.argabumi.absensi_wajah` /
  `id.argabumi.absensiWajah`) dan ganti ikon aplikasi.
- Siapkan kebijakan privasi, karena aplikasi memproses data wajah.

## Catatan teknis

- `android/app/proguard-rules.pro` wajib dipertahankan. Tanpa aturan ini, R8 di build rilis
  merusak ML Kit sehingga wajah tidak pernah terdeteksi.
- `android/gradle.properties` mematikan kompilasi inkremental Kotlin, karena build di Windows
  gagal bila project dan pub cache berada di drive berbeda.
- Font: Plus Jakarta Sans (SIL OFL), di `assets/fonts/`.
