#!/usr/bin/env bash
# ============================================================================
#  BorgOS ISO Builder – v0.4
#  Purpose  : Generate a bootable x86_64 ISO that installs BorgOS Lite
#             automatically (offline‑first AI OS) on the target PC.
#  Requires : A 64‑bit Debian/Ubuntu build host with >10 GB free space.
#  License  : MIT – experiment, hack, improve!
# ----------------------------------------------------------------------------
#  HIGH‑LEVEL STEPS
#     1.  Install live‑build + deps on HOST
#     2.  Create workspace  ~/borgos‑iso
#     3.  Configure live‑build (Debian 12 Bookworm, minimal)
#     4.  Inject BorgOS install script  (installer.sh)
#     5.  Build ISO   (lb build)  – result:  borgos‑<date>.iso
#     6.  Flash ISO to USB (e.g. balenaEtcher, dd) and boot target PC
#
#  The generated ISO boots into the Debian installer, runs preseed that
#  executes installer.sh after first boot, giving you a ready BorgOS system.
# ============================================================================
set -Eeuo pipefail

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}
WORKDIR=${WORKDIR:-$HOME/borgos-iso}
OUTDIR=${OUTDIR:-$WORKDIR/out}
LOGDIR=${LOGDIR:-$WORKDIR/logs}
BUILD_DATE=${BUILD_DATE:-$(date -u +%Y%m%d)}
ISO_NAME=${ISO_NAME:-"borgos-${BUILD_DATE}.iso"}
DIST=${DIST:-bookworm}  # Debian 12

trap 'echo "[!] Error on line $LINENO. See logs in $LOGDIR if available." >&2' ERR

# 0. CHECK ROOT PRIVILEGES ---------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "[!] Run this builder script as root (sudo su) on the HOST machine"; exit 1; fi
echo "[*] Using WORKDIR=$WORKDIR OUTDIR=$OUTDIR LOGDIR=$LOGDIR DIST=$DIST ISO_NAME=$ISO_NAME"

# 1. INSTALL DEPENDENCIES ----------------------------------------------------
mkdir -p "$OUTDIR" "$LOGDIR"
echo "[*] Installing dependencies..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y >>"$LOGDIR/host-apt.log" 2>&1
  apt-get install -y --no-install-recommends \
    live-build debootstrap squashfs-tools xorriso syslinux isolinux wget curl git ca-certificates >>"$LOGDIR/host-apt.log" 2>&1
else
  echo "[!] This script currently supports Debian/Ubuntu hosts with apt-get"; exit 1
fi
# live-build package name may be live-build or live-build/* depending on distro; the above works on Debian 12.

# 2. CREATE WORKSPACE --------------------------------------------------------
mkdir -p "$WORKDIR" && cd "$WORKDIR"
rm -rf auto config includes.chroot includes.binary || true   # clean prev build
# Ensure deterministic config
lb config -d "$DIST" \
           --archive-areas "main contrib non-free non-free-firmware" \
           --binary-images iso-hybrid \
           --debian-installer live \
           --apt-recommends true \
           --linux-flavours amd64 \
           --bootappend-live "boot=live components quiet splash noeject" \
           --memtest none \
           --win32-loader false

# 3. INCLUDE BORGOS INSTALLER -----------------------------------------------
# Add first-boot hook to run our installer in the installed system
# We leverage /etc/rc.local for simplicity: we install rc-local.service and a one-shot rc.local
mkdir -p config/includes.chroot/root config/includes.chroot/etc/systemd/system config/includes.chroot/etc
cat > config/includes.chroot/etc/systemd/system/rc-local.service <<'RCUNIT'
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
RemainAfterExit=yes
GuessMainPID=no

[Install]
WantedBy=multi-user.target
RCUNIT

cat > config/includes.chroot/etc/rc.local <<'RCLOCAL'
#!/bin/sh -e
# Run BorgOS installer once, then disable rc-local
if [ -x /root/installer.sh ] && [ ! -f /root/.borgos_installed ]; then
  /root/installer.sh >> /root/installer.log 2>&1 || true
  touch /root/.borgos_installed
  systemctl disable rc-local.service || true
fi
exit 0
RCLOCAL
chmod +x config/includes.chroot/etc/rc.local
# Enable the compatibility unit
mkdir -p config/includes.chroot/etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/rc-local.service config/includes.chroot/etc/systemd/system/multi-user.target.wants/rc-local.service

cat <<'INSTALL' >config/includes.chroot/root/installer.sh
#!/usr/bin/env bash
# BorgOS post-install script (runs inside live system after first boot)
# – copies itself to /root and executes automatically.
# ------------------ BEGIN BORGOS LITE INSTALLER -----------------------------
#!/usr/bin/env bash
# ============================================================================
#  BorgOS LITE – install-all-in-one script (v0.2-alpha)
#  Target HW : Intel® Celeron J1900 box (QBOX-2072) – 64-bit
#  Goal      : offline-first AI OS with online fallback (OpenRouter),
#              vector memory, MCP client+server, natural-language CLI,
#              headless + WebUI, plus common dev services (nginx/FTP/n8n).
#  License   : MIT – hack away!
# ----------------------------------------------------------------------------
#  BIG STEPS
#     0.  Run on fresh Debian 12 netinst (64-bit, minimal, SSH enabled)
#     1.  Base packages + dev toolchain
#     2.  Python env + Agent-Zero fork install
#     3.  Ollama (local LLMs)  + pull tiny models
#     4.  Online LLM via OpenRouter (OpenAI-compatible)
#     5.  Vector DB (Chroma) + embedding model
#     6.  MCP Python SDK – both server & client helpers
#     7.  Natural-language CLI alias  “borg”   (offline ↔ online auto-switch)
#     8.  Services: nginx, vsftpd, n8n (Docker), watchdog systemd units
#     9.  WebUI dashboard (Flask)     port 6969
#    10.  Optional Wi-Fi dongle setup (rtl8812au example)
# ============================================================================

set -e  # stop on error

# 0. DETECT ROOT
if [[ $EUID -ne 0 ]]; then
  echo "[!] Run as root (sudo su)"; exit 1; fi

# 1. UPDATE & BASE TOOLS ------------------------------------------------------
apt update && apt upgrade -y
apt install -y build-essential git curl wget unzip htop tmux \
               python3 python3-venv python3-pip \
               gcc g++ make pkg-config \
               ca-certificates gnupg lsb-release \
               sqlite3 dnsutils net-tools ufw neofetch

# 2. PYTHON VENV + AGENT-ZERO -------------------------------------------------
mkdir -p /opt/borgos && cd /opt/borgos
python3 -m venv env
source env/bin/activate
pip install --upgrade pip wheel

echo "[+] Cloning Agent-Zero fork"
if [[ ! -d agent-zero ]]; then
  git clone https://github.com/vizi2000/agent-zero.git
fi
cd agent-zero
pip install -e .[cli]
cd ..

# 3. OLLAMA (LOCAL LLM) -------------------------------------------------------
if ! command -v ollama &>/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi
# pull lightweight model for offline use
ollama pull phi3:instruct || true

# 4. OPENROUTER CONFIG --------------------------------------------------------
# environment var OPENAI_API_BASE tells openai-python to hit OpenRouter
pip install openai==1.* openrouter-client
cat <<'EOF' >/etc/profile.d/openrouter.sh
export OPENAI_API_BASE="https://openrouter.ai/api/v1"
# You must export OPENAI_API_KEY="sk-..." with your key later
EOF
chmod +x /etc/profile.d/openrouter.sh

# 5. VECTOR MEMORY (CHROMA) ---------------------------------------------------
pip install chromadb sentence-transformers
# default DB path: /opt/borgos/chroma_db
mkdir -p /opt/borgos/chroma_db

# 6. MCP CLIENT & SERVER ------------------------------------------------------
pip install mcp anthropic python-dotenv
mkdir -p /opt/borgos/mcp_servers && cd /opt/borgos/mcp_servers
if [[ ! -f fs_server.py ]]; then
  cat <<'PY' >fs_server.py
from mcp.server import Server, Resource, Tool
import os, asyncio, json
srv = Server(name="filesystem", description="Expose basic FS ops")
@srv.tool(name="listdir", description="List files in a directory")
async def listdir(path: str = "."):
    return os.listdir(path)
asyncio.run(srv.serve("127.0.0.1", 7300))
PY
fi

# 7. NATURAL LANGUAGE CLI WRAPPER -------------------------------------------
cat <<'PY' >/usr/local/bin/borg
#!/usr/bin/env python3
"""Borg CLI – decides offline vs online LLM automatically."""
import os, sys, subprocess, json, socket, requests, pathlib
OFFLINE_MODEL = os.getenv("BORG_OFFLINE_MODEL", "phi3:instruct")
ONLINE = False
try:
    requests.get("https://1.1.1.1", timeout=2)
    ONLINE = True
except requests.exceptions.RequestException:
    pass
prompt = " ".join(sys.argv[1:]) or input("borg> ")
if ONLINE and os.getenv("OPENAI_API_KEY"):
    import openai
    openai.api_key = os.getenv("OPENAI_API_KEY")
    openai.base_url = os.getenv("OPENAI_API_BASE", "https://openrouter.ai/api/v1")
    rsp = openai.chat.completions.create(model="openrouter/gpt-4o-mini", messages=[{"role":"user","content":prompt}])
    print(rsp.choices[0].message.content)
else:
    import ollama
    rsp = ollama.chat(model=OFFLINE_MODEL, messages=[{"role":"user","content":prompt}])
    print(rsp['message']['content'])
PY
chmod +x /usr/local/bin/borg
# Convenience: add simple motd
echo "Welcome to BorgOS Lite – use 'borg <prompt>'" > /etc/motd

# 8. SERVICES: NGINX, VSFTPD, N8N -------------------------------------------
apt install -y nginx vsftpd
systemctl enable --now nginx || true
sed -i 's/^anonymous_enable=.*/anonymous_enable=YES/' /etc/vsftpd.conf
systemctl enable --now vsftpd

if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
docker run -d --name n8n -p 5678:5678 -v n8n_data:/home/node/.n8n n8nio/n8n

# 9. BORGOS DASHBOARD (Flask) -------------------------------------------------
mkdir -p /opt/borgos/webui && cd /opt/borgos/webui
cat <<'PY' >app.py
from flask import Flask, request, jsonify, render_template_string
import subprocess
app = Flask(__name__)
INDEX = """<h1>BorgOS Dashboard</h1><form method=post><input name=q style='width:60%'><button>Send</button></form><pre>{{out}}</pre>"""
@app.route('/', methods=['GET','POST'])
def home():
    out=""
    if request.method=='POST':
        q=request.form['q']
        out=subprocess.check_output(['borg',q]).decode()
    return render_template_string(INDEX,out=out)
if __name__=='__main__':
    app.run(host='0.0.0.0', port=6969)
PY
pip install flask
cat <<'UNIT' >/etc/systemd/system/borgos-webui.service
[Unit]
Description=BorgOS WebUI
After=network.target

[Service]
User=root
ExecStart=/opt/borgos/env/bin/python /opt/borgos/webui/app.py
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable --now borgos-webui

# 10. OPTIONAL Wi-Fi DRIVER EXAMPLE -----------------------------------------
# apt install -y dkms linux-headers-$(uname -r)
# git clone https://github.com/aircrack-ng/rtl8812au.git /usr/src/8812au
# dkms add -m 8812au -v 5.9.3
# dkms build -m 8812au -v 5.9.3
# dkms install -m 8812au -v 5.9.3

# ============================================================================
 echo "[✔] BorgOS Lite installation completed. Reboot recommended."
# ------------------- END  BORGOS LITE INSTALLER -----------------------------
INSTALL

# Make the embedded installer executable (chmod target fix)
chmod +x config/includes.chroot/root/installer.sh

# 3b. Include minimal preseed to ensure noninteractive installer -------------
# Provide an empty preseed that still sets locale/timezone and root pw disabled
mkdir -p config/includes.installer
cat > config/includes.installer/preseed.cfg <<'PSEED'
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us
d-i time/zone string UTC
d-i clock-setup/utc boolean true
d-i netcfg/choose_interface select auto
d-i passwd/root-login boolean false
d-i user-setup/allow-password-weak boolean true
PSEED

# 4. BUILD ISO ---------------------------------------------------------------
echo "[*] Starting live-build..."
if ! lb build 2>&1 | tee "$LOGDIR/lb-build.log" ; then
  echo "[!] lb build failed. See $LOGDIR/lb-build.log"; exit 1
fi

# 5. RENAME OUTPUT -----------------------------------------------------------
FOUND=""
for candidate in "binary.hybrid.iso" "live-image-amd64.hybrid.iso" "live-image-amd64.hybrid.iso" "live-image-amd64.iso"; do
  if [[ -f "$candidate" ]]; then FOUND="$candidate"; break; fi
done
if [[ -n "$FOUND" ]]; then
  mkdir -p "$OUTDIR"
  mv -f "$FOUND" "$OUTDIR/$ISO_NAME"
  echo "[+] ISO ready: $OUTDIR/$ISO_NAME"
else
  echo "[!] Expected ISO not found in $WORKDIR. Check logs in $LOGDIR."
  exit 1
fi
