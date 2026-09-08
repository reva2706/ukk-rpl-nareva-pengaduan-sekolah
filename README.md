# UKK RPL — Aplikasi Pengaduan Sekolah

## Identitas Project
- **Nama Peserta:** Nareva Ranov
- **Kelas:** XII RPL 2
- **Judul Project:** Aplikasi Pengaduan Sekolah
- **Studi Kasus:** Sistem pengaduan/aspirasi siswa di lingkungan sekolah

## Gambaran Umum
Project terdiri dari dua aplikasi yang terhubung ke backend Firebase yang sama:

1. **Aplikasi Siswa/Petugas** — project Flutter pada folder `aplikasi-siswa`.
2. **Portal Admin Web** — project Flutter Web pada folder `aplikasi-admin`.

Keduanya menggunakan Cloud Firestore sebagai database dan Firebase Authentication untuk autentikasi. Source siswa juga menggunakan Firebase Cloud Messaging dan fitur multimedia. Portal admin menggunakan Firebase Storage untuk penyimpanan bukti respons admin dan mempunyai Cloud Function untuk notifikasi aspirasi baru.

## Teknologi
- Frontend: Flutter / Dart
- Backend/Platform: Firebase
- Database: Cloud Firestore
- Authentication: Firebase Authentication
- Storage: Firebase Storage (digunakan portal admin)
- Notifikasi: Firebase Cloud Messaging / Cloud Functions

## Fitur yang teridentifikasi pada source
### Aplikasi Siswa/Petugas
- Login berdasarkan peran siswa/petugas/admin pada source saat ini
- Registrasi data siswa
- Pengiriman aspirasi/pengaduan
- Kategori, lokasi, dan keterangan pengaduan
- Lampiran foto serta dukungan video/audio
- Riwayat aspirasi
- Perubahan/monitoring status pengaduan
- Penanganan tugas oleh petugas
- Rating dan komentar aplikasi

### Portal Admin Web
- Login admin
- Dashboard dan statistik aspirasi
- Pencarian/filter data aspirasi
- Melihat detail aspirasi
- Mengubah status dan memberi tanggapan
- Menugaskan petugas
- Manajemen data petugas
- Pencatatan `admin_logs`
- Notifikasi aspirasi baru melalui Cloud Function/FCM
- Fitur bukti respons admin

## Struktur Repository
```text
ukk-rpl-nareva-pengaduan-sekolah/
├── README.md
├── aplikasi-siswa/
├── aplikasi-admin/
├── database/
├── docs/
└── tests/
```

## Database
Project menggunakan Cloud Firestore. Dokumentasi collection dan field yang teridentifikasi dari source tersedia di `database/firestore-structure.md`.

## Cara Menjalankan
### Aplikasi siswa/petugas
1. Buka folder `aplikasi-siswa`.
2. Jalankan `flutter pub get`.
3. Pastikan konfigurasi Firebase lokal sudah disiapkan.
4. Jalankan `flutter run` pada perangkat/platform yang didukung.

### Portal admin
1. Buka folder `aplikasi-admin`.
2. Jalankan `flutter pub get`.
3. Pastikan konfigurasi Firebase lokal sudah disiapkan.
4. Jalankan `flutter run -d chrome` atau build web sesuai kebutuhan.

### Cloud Functions
1. Buka `aplikasi-admin/functions`.
2. Instal dependency Node.js sesuai `package.json`.
3. Deploy melalui Firebase CLI pada project Firebase yang benar jika deployment diperlukan.

> **Catatan:** Konfigurasi API key pada salinan repository UKK ini sengaja direduksi menjadi placeholder. Lihat `database/firebase-setup.md`.

## Akun Pengujian
Isi dengan akun DEMO yang benar-benar aktif sebelum repository diserahkan kepada asesor. Jangan menuliskan password rahasia/pribadi.

| Peran | Username/Email | Password |
|---|---|---|
| Siswa | `ISI_AKUN_DEMO` | `ISI_PASSWORD_DEMO` |
| Petugas | `ISI_AKUN_DEMO` | `ISI_PASSWORD_DEMO` |
| Admin | `ISI_AKUN_DEMO` | `ISI_PASSWORD_DEMO` |

## Dokumentasi
- `docs/01-analisis-kebutuhan.pdf`
- `docs/02-perancangan.pdf`
- `docs/03-dokumentasi-program.pdf`
- `docs/04-pengujian.pdf`
- `docs/05-debugging.pdf`
- `docs/06-evaluasi.pdf`
- `docs/screenshots/` untuk screenshot evidence.

Dokumen PDF dalam paket ini merupakan **draft berbasis source code dan ketentuan teknis pengumpulan**. Tambahkan screenshot, hasil uji nyata, dan data yang belum tersedia sebelum submit final.

## Known Issues / Hal yang Harus Diverifikasi
- Pastikan konfigurasi Firebase lokal/FlutLab benar setelah API key disanitasi untuk repository.
- Verifikasi aturan Firestore terbaru sebelum submit.
- Uji ulang alur media video/audio dari aplikasi siswa sampai tampilan admin.
- Uji ulang fitur cetak laporan pada portal admin jika fitur tersebut termasuk deliverable UKK.
- Ganti akun pengujian placeholder dengan akun demo yang memang tersedia.

## Keamanan Repository
Jangan commit `.env`, password, secret key, token, service account, private key, atau credential rahasia. Gunakan `.gitignore` dan konfigurasi lokal.
