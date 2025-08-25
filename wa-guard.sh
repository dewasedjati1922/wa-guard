#!/data/data/com.termux/files/usr/bin/bash
# WA Guard — WhatsApp Security Helper for Termux (no root)
# Author : Hanjardewa
# License: GPL-3.0
# Changelog v1.1:
# - Tambah menu Doctor (diagnostik)
# - Perbaikan PATH Android (/system/bin)
# - Fallback pm/cmd, dumpsys/cmd dump
# - Fallback pidof -> pgrep
# - ss -p fallback & izin terbatas
# - Cek dependency lebih lengkap

set -Eeuo pipefail

# ===== Versi & Update =====
SCRIPT_VERSION="1.1"
UPDATE_URL="https://raw.githubusercontent.com/dewasedjati1922/wa-guard/main/wa_guard.sh"   

# ===== Konstanta =====
export PATH="$PATH:/system/bin:/system/xbin"
APP_PKG="com.whatsapp"
DATA_DIR="$HOME/.wa-guard"
VAULT="$DATA_DIR/vault.enc"

SUSPECT_PACKAGES=(
  "com.android.system.update" "com.system.update" "com.spy.phone" "com.flexispy.phoenix"
  "com.mspy.phone" "com.hoverwatch" "com.webwatcher.android" "com.cerberus"
)
SENSITIVE_PERMS=(
  "android.permission.READ_SMS"
  "android.permission.RECORD_AUDIO"
  "android.permission.ACCESS_FINE_LOCATION"
  "android.permission.READ_CALL_LOG"
  "android.permission.PACKAGE_USAGE_STATS"
  "android.permission.BIND_ACCESSIBILITY_SERVICE"
)

# ===== Util =====
err()  { echo -e "\e[31m[!] $*\e[0m" >&2; }
ok()   { echo -e "\e[32m[✓] $*\e[0m"; }
info() { echo -e "\e[36m[i] $*\e[0m"; }
pause(){ read -rp $'\n[Enter] lanjut...'; }

banner() {
cat <<'BANNER'


██████╗ ███████╗██╗    ██╗ █████╗     ██╗  ██╗██╗██████╗ ███████╗
██╔══██╗██╔════╝██║    ██║██╔══██╗    ██║  ██║██║██╔══██╗██╔════╝
██████╔╝█████╗  ██║ █╗ ██║███████║    ███████║██║██████╔╝█████╗  
██╔═══╝ ██╔══╝  ██║███╗██║██╔══██║    ██╔══██║██║██╔═══╝ ██╔══╝  
██║     ███████╗╚███╔███╔╝██║  ██║    ██║  ██║██║██║     ███████╗
╚═╝     ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝╚═╝     ╚═════


╔══════════════════════════════════════╗
║           WA Guard (Termux)          ║
║   Audit & Hardening untuk WhatsApp   ║
╚══════════════════════════════════════╝
BANNER
}

require() {
  local miss=()
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || miss+=("$c"); done
  if (( ${#miss[@]} )); then
    err "Dependency hilang: ${miss[*]}"
    echo "Instal: pkg install -y ${miss[*]}"
    return 1
  fi
}

doctor() {
  echo
  ok "Doctor — Diagnostik Lingkungan"
  echo "PATH      : $PATH"
  echo "Shell     : $SHELL"
  echo "Termux?   : $(echo "$PREFIX" | sed 's|/data/data/com.termux/files||' >/dev/null 2>&1 && echo ya || echo ?) "
  echo "Android   : $(getprop ro.build.version.release 2>/dev/null || echo '?')"
  echo "Sec Patch : $(getprop ro.build.version.security_patch 2>/dev/null || echo '?')"
  echo
  echo "Cek dependency..."
  local need=(bash coreutils awk grep sed openssl curl ip ss netstat pidof pgrep pm dumpsys cmd)
  # alias/cmd mapping
  command -v ip >/dev/null 2>&1 || need+=(ip)
  command -v ss >/dev/null 2>&1 || true
  command -v netstat >/dev/null 2>&1 || true
  command -v pidof >/dev/null 2>&1 || true
  command -v pgrep >/dev/null 2>&1 || true
  command -v pm >/dev/null 2>&1 || true
  command -v dumpsys >/dev/null 2>&1 || true
  command -v cmd >/dev/null 2>&1 || true
  for c in bash coreutils awk grep sed openssl curl ip; do command -v "$c" >/dev/null 2>&1 && ok "$c" || err "$c MISSING"; done
  command -v ss >/dev/null 2>&1 && ok "ss" || info "ss tidak ada (ok, fallback netstat)"
  command -v netstat >/dev/null 2>&1 && ok "netstat" || info "netstat tidak ada (boleh)"
  command -v pidof >/dev/null 2>&1 && ok "pidof" || info "pidof tidak ada (pakai pgrep)"
  command -v pgrep >/dev/null 2>&1 && ok "pgrep" || err "pgrep hilang (procps)"
  command -v pm >/dev/null 2>&1 && ok "pm" || info "pm tak terjangkau, coba 'cmd package'"
  command -v dumpsys >/dev/null 2>&1 && ok "dumpsys" || info "dumpsys tak terjangkau, coba 'cmd package dump'"
  command -v cmd >/dev/null 2>&1 && ok "cmd" || err "cmd hilang (komponen Android)"
  echo
  ok "Jika ada MISSING, jalankan:"
  echo "pkg install -y procps iproute2 net-tools openssl curl coreutils grep sed awk"
}

# ===== Helper Android =====
has_pkg() {
  # true jika paket terinstal
  if command -v pm >/dev/null 2>&1; then
    pm list packages | grep -q "^package:$1$" && return 0
  fi
  if command -v cmd >/dev/null 2>&1; then
    cmd package list packages | grep -q "^package:$1$" && return 0
  fi
  return 1
}

pkg_dump() {
  # cetak info package dengan dumpsys/cmd
  if command -v dumpsys >/dev/null 2>&1; then
    dumpsys package "$1" 2>/dev/null && return 0
  fi
  if command -v cmd >/dev/null 2>&1; then
    cmd package dump "$1" 2>/dev/null && return 0
  fi
  return 1
}

find_pid() {
  # cari PID proses dengan nama paket
  if command -v pidof >/dev/null 2>&1; then
    pidof "$1" 2>/dev/null || true
  elif command -v pgrep >/dev/null 2>&1; then
    pgrep -f "$1" 2>/dev/null || true
  else
    echo ""
  fi
}

# ===== Fitur =====
info_system() {
  echo
  ok "Info Sistem & WhatsApp"
  echo "Perangkat : $(getprop ro.product.brand 2>/dev/null) $(getprop ro.product.model 2>/dev/null)"
  echo "Android   : $(getprop ro.build.version.release 2>/dev/null)"
  echo "Patch Sec : $(getprop ro.build.version.security_patch 2>/dev/null)"
  echo
  if has_pkg "$APP_PKG"; then
    ok "WhatsApp terpasang: $APP_PKG"
    local vname vcode firstInstall lastUpdate
    if out="$(pkg_dump "$APP_PKG")"; then
      vname="$(echo "$out" | grep -m1 'versionName=' | sed 's/.*versionName=//')"
      vcode="$(echo "$out" | grep -m1 'versionCode=' | sed 's/.*versionCode=//; s/ .*//')"
      firstInstall="$(echo "$out" | grep -m1 'firstInstallTime=' | sed 's/.*=//')"
      lastUpdate="$(echo "$out" | grep -m1 'lastUpdateTime=' | sed 's/.*=//')"
      echo "Versi     : ${vname:-unknown} (code ${vcode:-?})"
      echo "Install   : ${firstInstall:-unknown}"
      echo "Update    : ${lastUpdate:-unknown}"
    else
      info "Tidak bisa baca detail (izin dibatasi)."
    fi
  else
    err "WhatsApp tidak terdeteksi."
  fi
}

scan_suspects() {
  echo
  ok "Pindai aplikasi berisiko"
  local found=0
  for p in "${SUSPECT_PACKAGES[@]}"; do
    if has_pkg "$p"; then
      echo -e "\e[33m[!] Ditemukan: $p — tinjau & pertimbangkan uninstall.\e[0m"
      found=1
    fi
  done
  ((found==0)) && ok "Tidak ada paket dari daftar tersangka."
}

audit_permissions() {
  echo
  ok "Audit izin sensitif aplikasi non-sistem"
  local user_pkgs=""
  if command -v pm >/dev/null 2>&1; then
    user_pkgs="$(pm list packages -3 | sed 's/^package://')"
  elif command -v cmd >/dev/null 2>&1; then
    user_pkgs="$(cmd package list packages -3 | sed 's/^package://')"
  fi
  [ -z "$user_pkgs" ] && { info "Tidak ada/izin terbatas."; return; }
  while read -r pkg; do
    [ -z "$pkg" ] && continue
    if out="$(pkg_dump "$pkg")"; then
      local matched=""
      for perm in "${SENSITIVE_PERMS[@]}"; do
        echo "$out" | grep -q "$perm" && echo "$out" | grep -q "granted=true" && matched+="$perm, "
      done
      [ -n "$matched" ] && echo -e "\e[33m[!] $pkg izin: ${matched%, }\e[0m"
    fi
  done <<< "$user_pkgs"
}

net_check() {
  echo
  ok "Cek koneksi jaringan WhatsApp"
  local pid="$(find_pid "$APP_PKG" | head -n1 || true)"
  if [ -z "${pid:-}" ]; then
    err "WhatsApp belum berjalan (buka WA dulu)."
    return
  fi
  echo "PID WhatsApp: $pid"
  if command -v ss >/dev/null 2>&1; then
    # ss -p kadang dibatasi; coba tanpa -p jika gagal
    if ! ss -tnp 2>/dev/null | grep -F "$pid" ; then
      info "Tidak bisa baca proses (-p). Menampilkan koneksi TCP tanpa proses:"
      ss -tn 2>/dev/null || true
    fi
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tun 2>/dev/null | grep -E 'tcp|udp' || info "Tidak ada koneksi aktif."
  else
    err "ss/netstat tidak tersedia."
  fi
  echo
  info "Koneksi ke server WhatsApp/Meta adalah normal. Waspadai host asing yang tidak dikenal."
}

gen_passwords() {
  echo
  ok "Generator PIN/Password kuat"
  require openssl >/dev/null 2>&1 || return 0
  echo "PIN 6 digit     : $(tr -dc 0-9 </dev/urandom | head -c6)"
  echo "Password 16 b64 : $(openssl rand -base64 16)"
  echo "Password 32 b64 : $(openssl rand -base64 32)"
  echo "Passphrase HEX  : $(openssl rand -hex 24)"
}

vault_menu() {
  mkdir -p "$DATA_DIR"
  echo
  ok "Brankas terenkripsi (AES-256 + PBKDF2)"
  if [ -f "$VAULT" ]; then
    echo "1) Tambah catatan"
    echo "2) Lihat brankas"
    echo "0) Kembali"
    read -rp "Pilih: " v
    case "$v" in
      1)
        local tmp="$DATA_DIR/.vault.plain"
        if ! openssl enc -d -aes-256-cbc -pbkdf2 -in "$VAULT" -out "$tmp"; then
          err "Kata sandi salah."; rm -f "$tmp"; return
        fi
        read -rp "Judul catatan: " title
        echo "Isi (Ctrl+D selesai):"
        {
          echo -e "\n---\nTitle: $title"
          echo "Date: $(date -Iseconds)"
          cat
        } >> "$tmp"
        openssl enc -aes-256-cbc -pbkdf2 -salt -in "$tmp" -out "$VAULT"
        shred -u "$tmp" 2>/dev/null || rm -f "$tmp"
        ok "Catatan ditambahkan."
        ;;
      2)
        local tmp="$DATA_DIR/.vault.view"
        if ! openssl enc -d -aes-256-cbc -pbkdf2 -in "$VAULT" -out "$tmp"; then
          err "Kata sandi salah."; rm -f "$tmp"; return
        fi
        echo; cat "$tmp"; echo
        shred -u "$tmp" 2>/dev/null || rm -f "$tmp"
        ;;
      0) return ;;
      *) err "Pilihan tak valid." ;;
    esac
  else
    read -rp "Judul catatan pertama: " title
    echo "Isi (Ctrl+D selesai):"
    local tmp="$DATA_DIR/.vault.tmp"
    : > "$tmp"; cat >> "$tmp"
    {
      echo -e "\n---\nTitle: $title"
      echo "Date: $(date -Iseconds)"
    } >> "$tmp"
    openssl enc -aes-256-cbc -pbkdf2 -salt -in "$tmp" -out "$VAULT"
    shred -u "$tmp" 2>/dev/null || rm -f "$tmp"
    ok "Brankas dibuat: $VAULT"
  fi
}

hardening_tips() {
cat <<'TIPS'

[Checklist Hardening WhatsApp]
1) Aktifkan Two-Step Verification (PIN + email).
2) Aktifkan App Lock/biometrik.
3) Cek "Linked Devices" & logout yang asing.
4) Hindari APK luar Play Store.
5) Update Android & WhatsApp rutin.
6) Audit izin aplikasi lain; hapus yang tak perlu.
7) Simpan PIN/backup codes di brankas terenkripsi.
8) Jangan pernah bagikan OTP ke siapa pun.

TIPS
}

about_menu() {
cat <<ABOUT

╔════════════════════════════════════╗
║          Tentang WA Guard           ║
╚════════════════════════════════════╝
Versi     : $SCRIPT_VERSION
Author    : Hanjardewa
Lisensi   : GPL-3.0

Deskripsi:
Audit & hardening WhatsApp di perangkat sendiri.
Tidak membaca chat & bukan alat penyadapan.

ABOUT
}

check_update() {
  echo
  ok "Cek update WA Guard"
  if ! command -v curl >/dev/null 2>&1; then
    err "curl tidak tersedia. Install: pkg install curl"
    return
  fi
  local remote
  remote="$(curl -s "$UPDATE_URL" | grep -m1 '^SCRIPT_VERSION=' | cut -d'"' -f2 || true)"
  echo "Versi lokal   : $SCRIPT_VERSION"
  echo "Versi terbaru : ${remote:-gagal cek}"
  if [ -n "${remote:-}" ] && [ "$remote" != "$SCRIPT_VERSION" ]; then
    echo -e "\e[33m[!] Ada update baru.\e[0m"
    echo "Update:"
    echo "  curl -o wa_guard.sh $UPDATE_URL && chmod +x wa_guard.sh"
  else
    ok "Script sudah terbaru atau URL belum diatur."
  fi
}

# ===== Menu =====
menu() {
  echo
  echo "1) Info sistem & WhatsApp"
  echo "2) Pindai aplikasi berisiko"
  echo "3) Audit izin aplikasi"
  echo "4) Cek koneksi WhatsApp"
  echo "5) Generator PIN/Password"
  echo "6) Brankas terenkripsi"
  echo "7) Tips hardening"
  echo "8) Tentang Script"
  echo "9) Cek Update"
  echo "D) Doctor (diagnostik)"
  echo "0) Keluar"
  read -rp "Pilih: " ch
  case "${ch^^}" in
    1) info_system; pause ;;
    2) scan_suspects; pause ;;
    3) audit_permissions; pause ;;
    4) net_check; pause ;;
    5) gen_passwords; pause ;;
    6) vault_menu; pause ;;
    7) hardening_tips; pause ;;
    8) about_menu; pause ;;
    9) check_update; pause ;;
    D) doctor; pause ;;
    0) exit 0 ;;
    *) err "Pilihan tidak valid." ;;
  esac
}

main() {
  mkdir -p "$DATA_DIR"
  banner
  # Cek dependency dasar (tanpa memaksa)
  require bash coreutils awk grep sed openssl curl ip || true
  while true; do menu; done
}
main "$@"
