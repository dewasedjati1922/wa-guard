#!/data/data/com.termux/files/usr/bin/bash
# WA Guard — Defensive WhatsApp helper for Termux (no root).
# Author : ChatGPT (OpenAI)
# License: GPL-3.0

set -euo pipefail

# ==============================
# Versi & URL update
# ==============================
SCRIPT_VERSION="1.0"
UPDATE_URL="https://raw.githubusercontent.com/dewasedjati1922/wa-guard/main/wa_guard.sh" 
# Ganti USERNAME dengan username GitHub kamu

# ==============================
# Konstanta & Variabel
# ==============================
APP_PKG="com.whatsapp"
DATA_DIR="$HOME/.wa-guard"
VAULT="$DATA_DIR/vault.enc"

SUSPECT_PACKAGES=(
  "com.android.system.update"
  "com.system.update"
  "com.spy.phone"
  "com.stealth.mobile.tracker"
  "com.mobile.tracker"
  "com.flexispy.phoenix"
  "com.mspy.phone"
  "com.spyhuman"
  "com.cerberus"
  "com.hoverwatch"
  "com.webwatcher.android"
  "com.wspy.app"
)

SENSITIVE_PERMS=(
  "android.permission.READ_SMS"
  "android.permission.RECEIVE_SMS"
  "android.permission.SEND_SMS"
  "android.permission.READ_CALL_LOG"
  "android.permission.WRITE_CALL_LOG"
  "android.permission.PROCESS_OUTGOING_CALLS"
  "android.permission.RECORD_AUDIO"
  "android.permission.READ_CONTACTS"
  "android.permission.ACCESS_FINE_LOCATION"
  "android.permission.READ_PHONE_STATE"
  "android.permission.PACKAGE_USAGE_STATS"
  "android.permission.BIND_ACCESSIBILITY_SERVICE"
)

# ==============================
# Utilitas Tampilan
# ==============================
err() { echo -e "\e[31m[!] $*\e[0m" >&2; }
ok()  { echo -e "\e[32m[✓] $*\e[0m"; }
info(){ echo -e "\e[36m[i] $*\e[0m"; }

banner() {
cat <<'BANNER'
╔══════════════════════════════════════╗
║           WA Guard (Termux)          ║
║   Audit & Hardening untuk WhatsApp   ║
╚══════════════════════════════════════╝
BANNER
}

pause() { read -rp $'\n[Enter] lanjut...'; }

# ==============================
# Fungsi Cek Dependensi
# ==============================
check_deps() {
  local need_cmds=(pm dumpsys getprop awk grep sed date head tr od xxd openssl ip)
  local missing=0
  for c in "${need_cmds[@]}"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      err "Perintah '$c' tidak ditemukan."
      missing=1
    fi
  done
  if [ "$missing" -eq 1 ]; then
    echo
    echo "Instal dependensi dasar:"
    echo "  pkg update && pkg install -y termux-tools openssl iproute2 coreutils grep sed awk"
    exit 1
  fi
}

# ==============================
# Fungsi Fitur
# ==============================
info_system() {
  echo
  ok "Info Sistem & WhatsApp"
  local android_ver sec_patch brand model
  android_ver="$(getprop ro.build.version.release || true)"
  sec_patch="$(getprop ro.build.version.security_patch || true)"
  brand="$(getprop ro.product.brand || true)"
  model="$(getprop ro.product.model || true)"
  echo "Perangkat : $brand $model"
  echo "Android   : $android_ver"
  echo "Patch Sec : ${sec_patch:-unknown}"

  echo
  if pm list packages | grep -q "^package:$APP_PKG$"; then
    ok "WhatsApp terpasang: $APP_PKG"
    local vname vcode firstInstall lastUpdate
    vname="$(dumpsys package $APP_PKG 2>/dev/null | grep versionName | sed 's/ *versionName=//')"
    vcode="$(dumpsys package $APP_PKG 2>/dev/null | grep versionCode | head -n1 | sed 's/.*versionCode=//; s/ minSdk=.*//')"
    firstInstall="$(dumpsys package $APP_PKG 2>/dev/null | grep firstInstallTime | sed 's/.*=//')"
    lastUpdate="$(dumpsys package $APP_PKG 2>/dev/null | grep lastUpdateTime | sed 's/.*=//')"
    echo "Versi     : ${vname:-unknown} (code ${vcode:-?})"
    echo "Install   : ${firstInstall:-unknown}"
    echo "Update    : ${lastUpdate:-unknown}"
  else
    err "WhatsApp ($APP_PKG) tidak terdeteksi."
  fi
}

scan_suspects() {
  echo
  ok "Pindai paket/aplikasi berisiko"
  local found=0
  for p in "${SUSPECT_PACKAGES[@]}"; do
    if pm list packages | grep -q "package:$p$"; then
      echo -e "\e[33m[!] Ditemukan paket mencurigakan: $p\e[0m"
      found=1
    fi
  done
  if [ "$found" -eq 0 ]; then
    ok "Tidak ada paket mencurigakan terdeteksi."
  fi
}

audit_permissions() {
  echo
  ok "Audit izin sensitif aplikasi non-sistem"
  local user_pkgs
  user_pkgs=$(pm list packages -3 | sed 's/^package://')
  for pkg in $user_pkgs; do
    local report=""
    for perm in "${SENSITIVE_PERMS[@]}"; do
      if dumpsys package "$pkg" 2>/dev/null | grep -q "granted=true.*$perm"; then
        report+="$perm, "
      fi
    done
    if [ -n "$report" ]; then
      echo -e "\e[33m[!] $pkg izin: ${report%, }\e[0m"
    fi
  done
}

net_check() {
  echo
  ok "Cek koneksi jaringan WhatsApp"
  if ! pidof "$APP_PKG" >/dev/null 2>&1; then
    err "WhatsApp belum berjalan."
    return
  fi
  local pid
  pid="$(pidof "$APP_PKG" | awk '{print $1}')"
  echo "PID WhatsApp: $pid"
  if command -v ss >/dev/null 2>&1; then
    ss -tpn | grep "$pid" || info "Tidak ada koneksi aktif."
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tunp 2>/dev/null | grep "$pid" || info "Tidak ada koneksi aktif."
  else
    err "ss/netstat tidak tersedia."
  fi
}

gen_passwords() {
  echo
  ok "Generator PIN/Password kuat"
  echo "PIN 6 digit     : $(od -An -N4 -tu4 /dev/urandom | tr -dc 0-9 | head -c 6)"
  echo "Password 16 char: $(openssl rand -base64 16)"
  echo "Password 32 char: $(openssl rand -base64 32)"
  echo "Passphrase HEX  : $(openssl rand -hex 24)"
}

# ------------------------------
# Brankas Enkripsi
# ------------------------------
create_vault() {
  read -rp "Judul catatan: " title
  echo "Isi catatan (Ctrl+D untuk selesai):"
  local tmp="$DATA_DIR/.vault.tmp"
  : > "$tmp"
  cat >> "$tmp"
  echo -e "\n---\nTitle: $title\nDate: $(date -Iseconds)" >> "$tmp"
  openssl enc -aes-256-cbc -pbkdf2 -salt -in "$tmp" -out "$VAULT"
  rm -f "$tmp"
  ok "Brankas dibuat: $VAULT"
}

add_to_vault() {
  local tmp="$DATA_DIR/.vault.plain"
  if ! openssl enc -d -aes-256-cbc -pbkdf2 -in "$VAULT" -out "$tmp"; then
    err "Kata sandi salah."
    return
  fi
  read -rp "Judul catatan: " title
  echo "Isi catatan (Ctrl+D untuk selesai):"
  echo -e "\n---\nTitle: $title\nDate: $(date -Iseconds)" >> "$tmp"
  cat >> "$tmp"
  openssl enc -aes-256-cbc -pbkdf2 -salt -in "$tmp" -out "$VAULT"
  rm -f "$tmp"
  ok "Catatan ditambahkan."
}

view_vault() {
  local tmp="$DATA_DIR/.vault.view"
  if ! openssl enc -d -aes-256-cbc -pbkdf2 -in "$VAULT" -out "$tmp"; then
    err "Kata sandi salah."
    return
  fi
  cat "$tmp"
  rm -f "$tmp"
}

vault_menu() {
  mkdir -p "$DATA_DIR"
  echo
  ok "Brankas terenkripsi"
  if [ -f "$VAULT" ]; then
    echo "1) Tambah catatan"
    echo "2) Lihat brankas"
    echo "0) Kembali"
    read -rp "Pilih: " v
    case "$v" in
      1) add_to_vault ;;
      2) view_vault ;;
      0) return ;;
    esac
  else
    create_vault
  fi
}

# ------------------------------
# Tips Hardening
# ------------------------------
hardening_tips() {
cat <<'TIPS'

[Checklist Hardening WhatsApp]
1) Aktifkan 2-Step Verification (PIN 6 digit + email).
2) Aktifkan App Lock/biometrik di WhatsApp.
3) Periksa "Linked Devices" & logout perangkat asing.
4) Nonaktifkan backup chat ke cloud jika tidak aman.
5) Jangan install APK luar Play Store.
6) Update Android & WhatsApp rutin.
7) Periksa izin aplikasi lain (hapus yang mencurigakan).
8) Simpan PIN di brankas terenkripsi.
9) Jangan pernah bagikan kode OTP ke siapa pun.

TIPS
}

# ------------------------------
# Tentang Script
# ------------------------------
about_menu() {
cat <<ABOUT

╔════════════════════════════════════╗
║          Tentang WA Guard           ║
╚════════════════════════════════════╝

Versi     : $SCRIPT_VERSION
Author    : Dewasedjati1922
Lisensi   : GPL-3.0

Deskripsi :
Script ini membantu meningkatkan keamanan WhatsApp
melalui audit sistem, deteksi aplikasi berisiko, 
cek izin, brankas terenkripsi, & tips hardening.

Catatan :
• Hanya untuk keamanan & edukasi.
• Tidak ada fitur penyadapan.
• Gunakan di perangkat sendiri.

ABOUT
}

# ------------------------------
# Cek Update
# ------------------------------
check_update() {
  echo
  ok "Cek update WA Guard"
  if ! command -v curl >/dev/null 2>&1; then
    err "curl tidak tersedia. Install dengan: pkg install curl"
    return
  fi

  remote_version=$(curl -s "$UPDATE_URL" | grep -m1 '^SCRIPT_VERSION=' | cut -d'"' -f2)

  echo "Versi lokal   : $SCRIPT_VERSION"
  echo "Versi terbaru : ${remote_version:-gagal cek}"

  if [ -n "$remote_version" ] && [ "$remote_version" != "$SCRIPT_VERSION" ]; then
    echo -e "\e[33m[!] Ada update baru!\e[0m"
    echo "Update dengan:"
    echo "  curl -o wa_guard.sh $UPDATE_URL && chmod +x wa_guard.sh"
  else
    ok "Script sudah terbaru."
  fi
}

# ==============================
# Menu Utama
# ==============================
menu() {
  echo
  echo "1) Cek info sistem & WhatsApp"
  echo "2) Pindai aplikasi berisiko"
  echo "3) Audit izin aplikasi"
  echo "4) Cek koneksi WhatsApp"
  echo "5) Generator PIN/Password"
  echo "6) Brankas terenkripsi"
  echo "7) Tips hardening WhatsApp"
  echo "8) Tentang Script"
  echo "9) Cek Update Script"
  echo "0) Keluar"
  echo
  read -rp "Pilih: " choice
  case "$choice" in
    1) info_system; pause ;;
    2) scan_suspects; pause ;;
    3) audit_permissions; pause ;;
    4) net_check; pause ;;
    5) gen_passwords; pause ;;
    6) vault_menu; pause ;;
    7) hardening_tips; pause ;;
    8) about_menu; pause ;;
    9) check_update; pause ;;
    0) exit 0 ;;
    *) err "Pilihan tidak valid";;
  esac
}

# ==============================
# Main Program
# ==============================
main() {
  mkdir -p "$DATA_DIR"
  check_deps
  banner
  while true; do menu; done
}

main "$@"
