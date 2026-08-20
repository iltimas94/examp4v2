# ExBrowser 4 — Aturan Proyek

> **Bahasa:** Kamu selalu berkomunikasi dalam Bahasa Indonesia untuk semua percakapan, komentar, dan dokumentasi proyek ini, kecuali diminta sebaliknya.

## Aturan Kerja

1. Jangan merubah, mengedit, menghapus kode, desain, pokoknya apapun di proyek ini tanpa persetujuan saya.
2. Lakukan saja apa yang saya perintahkan. Jika kamu punya ide atau tambahan fitur, tanyakan dulu.

## 1. Deskripsi Umum

ExBrowser 4 adalah aplikasi browser khusus ujian (Secure Browser) berbasis Android yang dirancang untuk mencegah kecurangan siswa selama pelaksanaan ujian berbasis web (seperti Google Forms atau LMS). Aplikasi ini menggabungkan antarmuka Flutter yang dinamis dengan kontrol keamanan tingkat tinggi melalui integrasi native Android (Kotlin).

## 2. Fitur Keamanan Utama (Anti-Cheat)

Aplikasi ini memiliki sistem keamanan berlapis yang sangat ketat:

- **Anti-Screenshot dan Perekaman Layar:** Menggunakan FLAG_SECURE untuk memblokir pengambilan gambar dan perekaman layar.
- **Deteksi Kehilangan Fokus:** Mengawasi aktivitas jendela. Jika siswa mencoba membuka aplikasi lain, menekan tombol Home, atau melihat Recent Apps, aplikasi akan otomatis terkunci.
- **Anti Layar Terpisah:** Mendeteksi dan memblokir mode layar terpisah (split screen).
- **Mode Imersif:** Menyembunyikan navigasi sistem (tombol Back, Home, Recent) dan bilah status agar siswa tetap berada di lingkungan ujian.
- **Manajemen Notifikasi (DND):** Mengaktifkan mode "Jangan Ganggu" agar pesan masuk (WhatsApp, dll) tidak muncul dan tidak mengganggu konsentrasi atau menjadi sarana untuk menyontek.
- **Sistem Kunci Admin:** Jika terjadi pelanggaran, layar akan terkunci secara permanen (bahkan jika HP dimatikan atau dinyalakan kembali) dan hanya bisa dibuka oleh pengawas menggunakan Kode Admin.

## 3. Sistem Backend Dinamis (Google Sheets CMS)

Aplikasi ini menggunakan Google Sheets sebagai panel kontrol (CMS), yang memungkinkan admin sekolah mengubah pengaturan secara langsung tanpa harus memperbarui aplikasi:

- **Manajemen Token:** Verifikasi token ujian sebelum masuk.
- **Daftar Ujian Dinamis:** Mengatur tautan ujian, gambar, dan mata pelajaran.
- **Pesan Pengumuman:** Menampilkan catatan atau instruksi ujian.
- **Reset Sesi Otomatis:** Jika admin mengubah ID Sesi di spreadsheet, semua HP siswa yang terkunci akan terbuka otomatis (fitur mass-unlock).
- **Pembaruan Versi:** Memaksa siswa melakukan pembaruan jika versi aplikasi sudah usang.

## 4. Optimalisasi Login Google

- **Smart Security Toggle:** Aplikasi secara cerdas mematikan fitur anti-screenshot sementara saat berada di halaman login Google, agar fitur pengisian otomatis (pilih akun) sistem Android bisa muncul. Keamanan akan aktif kembali otomatis saat masuk ke soal ujian.
- **Custom User-Agent:** Menyamar sebagai browser Chrome standar agar Google mengizinkan fitur login lengkap dan pemilihan akun.

## 5. Alur Pengguna (User Flow)

1. **Layar Pembuka (Splash):** Pengecekan versi aplikasi dan status kunci sebelumnya.
2. **Halaman Token:** Siswa memasukkan token yang diberikan pengawas.
3. **Halaman Daftar Ujian:** Siswa memilih mata pelajaran yang diujikan (tampilan grid).
4. **Halaman Ujian (WebView):** Siswa mengerjakan soal. Di halaman ini, monitoring keamanan aktif sepenuhnya, kecerahan layar diatur, dan navigasi dibatasi.

## 6. Teknologi yang Digunakan

- **Framework:** Flutter (UI dan logika).
- **Native Bridge:** Platform Channels (MethodChannel) untuk komunikasi Flutter ke Kotlin.
- **Library Utama:**
  - flutter_inappwebview (mesin browser).
  - http (komunikasi ke Google Sheets).
  - shared_preferences (penyimpanan status kunci dan sesi).
  - package_info_plus (informasi versi).
- **Target SDK:** Android 16 (API 36).

## 7. Kesimpulan

ExBrowser 4 adalah solusi ujian sekolah yang stabil, fleksibel, dan sangat aman. Keunggulan utamanya terletak pada kemudahan pengelolaan bagi admin melalui Google Sheets dan sistem pemulihan kunci (anti-force close) yang memastikan siswa tidak bisa lari dari pengawasan aplikasi selama ujian berlangsung.