#!/usr/bin/env bash
# ============================================================================
#  BorgOS ISO Builder – v1.0
#  Purpose  : Generate a bootable x86_64 ISO that installs BorgOS
#             automatically (offline‑first AI OS) on the target PC.
#  Requires : A 64‑bit Debian/Ubuntu build host with >10 GB free space.
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR=${WORKDIR:-$HOME/borgos-iso}
OUTDIR=${OUTDIR:-$SCRIPT_DIR/../out/ISO}
LOGDIR=${LOGDIR:-$SCRIPT_DIR/../logs}
BUILD_DATE=${BUILD_DATE:-$(date -u +%Y%m%d)}
ISO_NAME=${ISO_NAME:-"borgos-${BUILD_DATE}.iso"}
ISO_TAG=${ISO_TAG:-"borgos-${BUILD_DATE}"}
DIST=${DIST:-bookworm}  # Debian 12
BORG_BRANCH=${BORG_BRANCH:-main}
BORG_OFFLINE_MODEL=${BORG_OFFLINE_MODEL:-phi3:instruct}

trap 'echo "[!] Error on line $LINENO. See logs in $LOGDIR if available." >&2' ERR

# 0. CHECK ROOT PRIVILEGES ---------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "[!] Run this builder script as root (sudo su) on the HOST machine"
  exit 1
fi

echo "[*] BorgOS ISO Builder v1.0"
echo "[*] Configuration:"
echo "    WORKDIR=$WORKDIR"
echo "    OUTDIR=$OUTDIR"
echo "    LOGDIR=$LOGDIR"
echo "    DIST=$DIST"
echo "    ISO_NAME=$ISO_NAME"
echo "    ISO_TAG=$ISO_TAG"
echo "    BORG_BRANCH=$BORG_BRANCH"
echo "    BORG_OFFLINE_MODEL=$BORG_OFFLINE_MODEL"

# 1. INSTALL DEPENDENCIES ----------------------------------------------------
mkdir -p "$OUTDIR" "$LOGDIR"
echo "[*] Installing dependencies..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y >>"$LOGDIR/host-apt.log" 2>&1
  apt-get install -y --no-install-recommends \
    live-build debootstrap squashfs-tools xorriso \
    syslinux isolinux wget curl git ca-certificates >>"$LOGDIR/host-apt.log" 2>&1
else
  echo "[!] This script currently supports Debian/Ubuntu hosts with apt-get"
  exit 1
fi

# 2. CREATE WORKSPACE --------------------------------------------------------
echo "[*] Creating workspace at $WORKDIR"
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
echo "[*] Injecting BorgOS installer..."
# Copy the installer script from our repo
mkdir -p config/includes.chroot/root
cp "$SCRIPT_DIR/../installer/install_all.sh" config/includes.chroot/root/installer.sh
chmod +x config/includes.chroot/root/installer.sh

# Add first-boot hook to run our installer in the installed system
mkdir -p config/includes.chroot/etc/systemd/system
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
  echo "[*] Running BorgOS installer..." >> /root/installer.log
  /root/installer.sh >> /root/installer.log 2>&1 || true
  touch /root/.borgos_installed
  systemctl disable rc-local.service || true
fi
exit 0
RCLOCAL
chmod +x config/includes.chroot/etc/rc.local

# Enable the compatibility unit
mkdir -p config/includes.chroot/etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/rc-local.service \
  config/includes.chroot/etc/systemd/system/multi-user.target.wants/rc-local.service

# 3b. Include minimal preseed to ensure noninteractive installer -------------
mkdir -p config/includes.installer
cat > config/includes.installer/preseed.cfg <<'PSEED'
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us
d-i time/zone string UTC
d-i clock-setup/utc boolean true
d-i netcfg/choose_interface select auto
d-i passwd/root-login boolean false
d-i user-setup/allow-password-weak boolean true
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
PSEED

# 4. BUILD ISO ---------------------------------------------------------------
echo "[*] Starting live-build (this may take 20-60 minutes)..."
if ! lb build 2>&1 | tee "$LOGDIR/lb-build.log" ; then
  echo "[!] lb build failed. See $LOGDIR/lb-build.log"
  exit 1
fi

# 5. RENAME OUTPUT -----------------------------------------------------------
FOUND=""
for candidate in "binary.hybrid.iso" "live-image-amd64.hybrid.iso" "live-image-amd64.iso"; do
  if [[ -f "$candidate" ]]; then
    FOUND="$candidate"
    break
  fi
done

if [[ -n "$FOUND" ]]; then
  mkdir -p "$OUTDIR"
  mv -f "$FOUND" "$OUTDIR/$ISO_NAME"
  
  # Generate checksums
  echo "[*] Generating checksums..."
  cd "$OUTDIR"
  sha256sum "$ISO_NAME" > "${ISO_NAME}.sha256"
  
  echo "[+] ========================================="
  echo "[+] ISO build complete!"
  echo "[+] Location: $OUTDIR/$ISO_NAME"
  echo "[+] Size: $(du -h "$ISO_NAME" | cut -f1)"
  echo "[+] SHA256: $(cat "${ISO_NAME}.sha256")"
  echo "[+] ========================================="
else
  echo "[!] Expected ISO not found in $WORKDIR. Check logs in $LOGDIR."
  exit 1
fi