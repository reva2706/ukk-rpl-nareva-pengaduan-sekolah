# Struktur Database Cloud Firestore

Dokumen ini dibuat berdasarkan collection yang direferensikan oleh source code kedua aplikasi. Nilai/data pribadi tidak disalin ke repository.

## Collection utama

### `siswa`
Field yang ditulis oleh aplikasi siswa antara lain:
- `nis` — identitas siswa
- `nama` — nama siswa
- `kelas` — kelas siswa
- `password` — digunakan oleh mekanisme login pada source saat ini
- `createdAt` — waktu pembuatan data
- `fcmToken` — token notifikasi jika tersedia

### `petugas`
Field yang digunakan antara lain:
- `idPetugas`
- `nama`
- `email`
- `username`
- `bidang`
- `role`
- `status`
- `uid`
- `createdAt`
- `updatedAt`

### `aspirasi`
Field yang digunakan untuk pengaduan antara lain:
- `nis`, `nama`, `kelas`
- `kategori`, `lokasi`, `keterangan`
- `hasImage`, `hasImages`, `fotoUrl`, `fotoUrls`
- `mediaUrl`, `mediaType`, `mediaStorage`, `mediaName`
- `mediaContentType`, `mediaChunkCount`, `mediaChunkCollection`, `mediaSizeBytes`
- `hasVideo`, `hasAudio`
- `status`
- `feedbackAdmin`, `fotoUrlAdmin`
- `petugasId`, `petugasNama`
- `catatanPetugas`
- `buktiPenanganan`, `buktiPenangananUrl`, `buktiPenangananType`
- `updatedAt`, `createdAt`

Lampiran video/audio pada aplikasi siswa menggunakan subcollection `media_chunks` di bawah dokumen aspirasi.

### `rating_aplikasi`
Field yang ditulis antara lain:
- `nis`, `nama`, `kelas`
- `rating`, `komentar`
- `createdAt`

### `admin_logs`
Digunakan untuk mencatat pembaruan aspirasi dari portal admin. Field yang ditulis pada source admin antara lain:
- `action`
- `aspirasiId`
- `status`
- `petugasId`
- `petugasNama`
- `adminUid`
- `createdAt`

### `settings`
Source admin menggunakan dokumen `admin_token` untuk penyimpanan token notifikasi admin.

## Catatan pengumpulan

Database project menggunakan Cloud Firestore, bukan database SQL. Karena itu repository ini mendokumentasikan struktur collection dan field yang digunakan, bukan membuat file `database.sql` palsu. Sebelum pengumpulan final, tambahkan/export aturan Firestore yang benar-benar sedang dipakai ke `firestore-rules.txt` setelah diverifikasi di Firebase Console.
