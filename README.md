# WA Guard (WhatsApp Security Helper)

WA Guard adalah script bash untuk **Termux (Android)** yang membantu pengguna meningkatkan keamanan WhatsApp.  
Script ini **bukan untuk hack/spy**, hanya untuk audit & hardening keamanan WhatsApp di perangkat sendiri.  

---

## ✨ Fitur
- 🔍 Cek info sistem & WhatsApp
- 🕵️ Deteksi aplikasi berisiko (indikasi stalkerware)
- 📜 Audit izin sensitif aplikasi non-sistem
- 🌐 Cek koneksi jaringan WhatsApp
- 🔑 Generator PIN & Password kuat
- 📦 Brankas terenkripsi (AES-256) untuk simpan PIN/backup code
- 📚 Tips hardening WhatsApp
- 🆕 Cek update otomatis dari GitHub

---

## 📥 Install & Jalankan

Buka **Termux** lalu jalankan:

```bash
# clone repo
pkg install git -y
git clone https://github.com/dewasedjati1922/wa-guard.git
cd wa-guard

# ubah izin & jalankan
chmod +x wa_guard.sh
./wa_guard.sh
