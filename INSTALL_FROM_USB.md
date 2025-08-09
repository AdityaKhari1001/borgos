# 📀 INSTALACJA BorgOS Z PENDRIVE NA DYSK

## 🎯 DWA TRYBY DZIAŁANIA

### 1. **LIVE MODE** (bez instalacji)
- System działa Z pendrive
- Zmiany znikają po restarcie
- Dobre do testowania

### 2. **INSTALACJA NA DYSK** (trwała)
- System instaluje się NA dysk twardy
- Działa bez pendrive
- Pełna wydajność

---

## 🔧 JAK ZAINSTALOWAĆ NA DYSK

### KROK 1: Boot z USB
1. Włóż pendrive do PC
2. Restart → F12/F2/Del
3. Wybierz boot z USB

### KROK 2: Wybierz opcję instalacji
Po uruchomieniu zobaczysz menu:
- **Install BorgOS (Automated)** ← WYBIERZ TO
- Live (amd64)
- Install (text mode)

### KROK 3: Instalator Debian
1. **Język**: English
2. **Lokalizacja**: Other → Europe → Poland
3. **Klawiatura**: American English
4. **Sieć**: 
   - Hostname: `borgos`
   - Domain: (zostaw puste)
5. **Użytkownik**:
   - Root password: (ustaw swoje)
   - Username: `borg`
   - Password: (ustaw swoje)

### KROK 4: Partycjonowanie dysku
**WAŻNE**: To WYMAŻE wybrany dysk!

Opcje:
- **Guided - use entire disk** ← Najłatwiejsze
- Guided - use entire disk and set up LVM
- Manual (dla zaawansowanych)

Wybierz dysk do instalacji (np. sda, nvme0n1)

### KROK 5: Instalacja systemu
- Potrwa 10-15 minut
- System skopiuje pliki z USB na dysk
- BorgOS zainstaluje się automatycznie

### KROK 6: Restart
1. System poprosi o wyjęcie USB
2. Wyjmij pendrive
3. Enter → restart

---

## 🚀 PO INSTALACJI

### Pierwsze uruchomienie:
System automatycznie:
1. Uruchomi Ollama z Mistral 7B
2. Wystartuje WebUI na porcie 6969
3. Skonfiguruje wszystkie usługi

### Dostęp:
```bash
# SSH
ssh borg@IP_ADRES

# WebUI
http://IP_ADRES:6969

# CLI
borg "twoje pytanie"
```

---

## 💡 OPCJE INSTALACJI

### A. SZYBKA INSTALACJA (Automated)
- Używa preseed.cfg
- Automatyczne partycjonowanie
- BorgOS instaluje się sam

### B. RĘCZNA INSTALACJA
1. Zainstaluj czysty Debian 12
2. Po restarcie:
```bash
# Skopiuj pliki BorgOS
sudo cp -r /media/cdrom/borgos /opt/
cd /opt/borgos
sudo bash installer/install_all.sh
```

### C. DUAL BOOT (z Windows)
1. Zmniejsz partycję Windows
2. Wybierz "Manual" partycjonowanie
3. Utwórz:
   - `/` (root) - 20GB minimum
   - `swap` - 4-8GB
   - `/home` - reszta

---

## ⚠️ WYMAGANIA

### Minimalne:
- **CPU**: x86_64 (Intel/AMD)
- **RAM**: 8GB
- **Dysk**: 20GB wolnego
- **GPU**: Nie wymagane (CPU inference)

### Zalecane:
- **RAM**: 16GB
- **Dysk**: 50GB (dla dodatkowych modeli)
- **GPU**: NVIDIA (opcjonalne, przyspiesza)

---

## 🔍 TROUBLESHOOTING

### "No bootable device"
- Wyłącz Secure Boot w BIOS
- Włącz Legacy/CSM mode

### "Cannot find installation media"
- Spróbuj innego portu USB
- Użyj USB 2.0 zamiast 3.0

### "Installation failed"
- Sprawdź sumę kontrolną ISO
- Nagraj ponownie USB
- Użyj Balena Etcher

---

## 📝 RÓŻNICE: LIVE vs INSTALACJA

| Funkcja | Live Mode | Instalacja |
|---------|-----------|------------|
| Szybkość | Wolniejsze (USB) | Pełna prędkość |
| Zmiany | Tymczasowe | Trwałe |
| Modele AI | Z USB | Z dysku |
| Updates | Nie | Tak |
| Dodatkowe modele | Nie | Tak |

---

## ✅ PODSUMOWANIE

**Chcesz zainstalować na dysk?**
1. Boot z USB
2. Wybierz "**Install BorgOS (Automated)**"
3. Postępuj zgodnie z instalatorem
4. Po 15 minutach masz gotowy system!

**System zainstaluje:**
- Debian 12 base
- BorgOS wszystkie komponenty  
- Mistral 7B (4.1GB)
- Ollama runtime
- WebUI + CLI

Wszystko **100% offline**, bez internetu!