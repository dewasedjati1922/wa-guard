#!/data/data/com.termux/files/usr/bin/bash
# Installer WA Guard
# Author : ChatGPT (OpenAI)

set -e

REPO_URL="https://raw.githubusercontent.com/dewasedjati1922/wa-guard/main/wa_guard.sh"
INSTALL_DIR="$HOME/wa-guard"
SCRIPT_PATH="$INSTALL_DIR/wa_guard.sh"

echo "[+] Update & install dependensi..."
pkg update -y && pkg upgrade -y
pkg install git curl openssl coreutils grep sed awk iproute2 -y

echo "[+] Buat folder instalasi..."
mkdir -p "$INSTALL_DIR"

echo "[+] Download script WA Guard..."
curl -o "$SCRIPT_PATH" "$REPO_URL"

echo "[+] Set permission..."
chmod +x "$SCRIPT_PATH"

# Tambahkan alias agar gampang dipanggil
SHELL_RC="$HOME/.bashrc"
if ! grep -q "wa-guard" "$SHELL_RC"; then
  echo "alias wa-guard='$SCRIPT_PATH'" >> "$SHELL_RC"
fi

echo
echo "[✓] Instalasi selesai!"
echo "Jalankan dengan: "
echo "   wa-guard"
echo
