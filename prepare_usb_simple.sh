#!/bin/bash
# ============================================================================
#  BorgOS - Simple USB Preparation (Works on macOS)
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[*]${NC} $1"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          BorgOS - Przygotowanie USB (Prosta Metoda)          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Ensure Debian ISO exists
if [ ! -f "debian.iso" ] || [ $(stat -f%z debian.iso) -lt 600000000 ]; then
    log "Pobieram Debian 12 ISO (631MB)..."
    rm -f debian.iso
    wget --progress=bar:force -O debian.iso \
        "https://cdimage.debian.org/cdimage/archive/12.8.0/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso"
fi

log "Debian ISO gotowy: $(ls -lh debian.iso | awk '{print $5}')"

# Step 2: Create complete BorgOS package
log "Tworzę kompletny pakiet BorgOS..."

# Remove old package
rm -f borgos-complete.tar.gz

# Create package with everything
tar -czf borgos-complete.tar.gz \
    installer/ \
    webui/ \
    mcp_servers/ \
    plugins/ \
    *.py \
    requirements.txt \
    *.md \
    *.sh 2>/dev/null || warn "Some files skipped"

log "Pakiet BorgOS gotowy: $(ls -lh borgos-complete.tar.gz | awk '{print $5}')"

# Step 3: Create installation instructions
cat > INSTALL_INSTRUCTIONS.txt <<'EOF'
================================
INSTRUKCJE INSTALACJI BORGOS
================================

KROK 1: NAGRANIE USB NA MACOS
------------------------------
1. Znajdź swój pendrive (8GB):
   diskutil list | grep "8.0 GB"
   (zapamiętaj numer, np. disk4)

2. Wymaż pendrive CAŁKOWICIE:
   sudo diskutil eraseDisk FREE BORGOS /dev/disk4

3. Odmontuj:
   sudo diskutil unmountDisk force /dev/disk4

4. Nagraj ISO:
   sudo dd if=debian.iso of=/dev/rdisk4 bs=1m

5. Poczekaj 5-10 minut aż się zakończy

6. Wyjmij pendrive fizycznie (nie "eject")


KROK 2: INSTALACJA NA PC x86
-----------------------------
1. Włóż pendrive do PC
2. Włącz PC i wciśnij F12/F2/Del podczas startu
3. Wybierz boot z USB
4. Zainstaluj Debian 12:
   - Wybierz: "Install" (nie graphical)
   - Język: English
   - Location: Other->Europe->Poland
   - Keyboard: American English
   - Hostname: borgos
   - Domain: (zostaw puste)
   - Root password: (ustaw swoje)
   - User: borg
   - Password: (ustaw swoje)
   - Partycjonowanie: "Guided - use entire disk"
   - Software: Zaznacz TYLKO:
     [*] SSH server
     [*] standard system utilities


KROK 3: INSTALACJA BORGOS
--------------------------
Po instalacji Debian i restarcie:

1. Zaloguj się jako root lub user
2. Sprawdź IP: ip addr show
3. Z macOS wyślij pakiet:
   scp borgos-complete.tar.gz user@IP_ADRES:~/

4. Na systemie docelowym:
   tar -xzf borgos-complete.tar.gz
   cd borgos
   sudo bash installer/install_all.sh

5. Instalacja potrwa 20-30 minut (pobierze modele AI)


KROK 4: DOSTĘP DO SYSTEMU
--------------------------
Po instalacji:
• SSH: ssh user@IP_ADRES
• WebUI: http://IP_ADRES:6969
• CLI: borg "twoje pytanie"

Modele AI:
• Mistral 7B (4.1GB) - główny
• Llama 3.2 (2GB) - backup


ALTERNATYWA: BALENA ETCHER
---------------------------
Jeśli dd nie działa:
1. Pobierz: https://etcher.balena.io/
2. Wybierz debian.iso
3. Wybierz pendrive
4. Kliknij Flash!
EOF

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ WSZYSTKO GOTOWE!                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📦 Przygotowane pliki:"
echo "   • debian.iso (631MB) - obraz do nagrania"
echo "   • borgos-complete.tar.gz - pakiet BorgOS"
echo "   • INSTALL_INSTRUCTIONS.txt - instrukcje"
echo ""
echo "🔥 SZYBKIE NAGRANIE USB:"
echo ""
echo "   1. Znajdź pendrive:"
echo "      ${YELLOW}diskutil list | grep '8.0 GB'${NC}"
echo ""
echo "   2. Nagraj (zmień disk4 na swój numer):"
echo "      ${YELLOW}sudo dd if=debian.iso of=/dev/rdisk4 bs=1m${NC}"
echo ""
echo "📖 Pełne instrukcje w pliku: INSTALL_INSTRUCTIONS.txt"
echo ""
echo "💡 Wskazówka: Użyj Balena Etcher jeśli dd nie działa"
echo "   https://etcher.balena.io/"