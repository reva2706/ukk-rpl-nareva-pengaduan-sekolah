# Setup Firebase untuk salinan repository

Project asli menggunakan Firebase project yang sudah terhubung dari FlutLab. Untuk keamanan pengumpulan UKK, nilai API key pada source yang diunggah ke repository ini telah diganti menjadi placeholder `YOUR_FIREBASE_WEB_API_KEY`.

## Sebelum menjalankan secara lokal
1. Pastikan project Firebase yang digunakan adalah project milik pengembang.
2. Konfigurasikan Firebase untuk aplikasi Flutter sesuai platform yang digunakan.
3. Isi konfigurasi lokal yang diperlukan tanpa melakukan commit credential/secret.
4. Pastikan Authentication, Cloud Firestore, Storage (untuk respons admin), dan Cloud Messaging sesuai konfigurasi project.

## Penting
Petunjuk teknis UKK melarang upload API key, password, secret key, token, dan credential rahasia. Karena itu jangan mengganti placeholder dengan credential rahasia lalu melakukan commit ke repository.
