# 🚀 JAK ZROBIĆ BOOTOWALNY USB - WSZYSTKIE METODY

## ✅ NAJŁATWIEJSZA METODA (Windows/Mac/Linux)

### 🎯 **Balena Etcher** (GUI - Graficzny)
1. **Pobierz**: https://etcher.balena.io/
2. **Zainstaluj** i uruchom
3. **Wybierz ISO**: `iso_output/BorgOS-Live-amd64.iso` (gdy będzie gotowy)
4. **Wybierz USB**: Twój pendrive 8GB+
5. **Kliknij "Flash!"**
6. **Gotowe!** - 100% sukcesu

**Zalety**: 
- ✅ Zawsze działa
- ✅ Automatycznie weryfikuje
- ✅ Nie trzeba znać komend

---

## 💻 NA WINDOWS (3 metody)

### Metoda 1: **Rufus** (Najlepsza)
1. **Pobierz**: https://rufus.ie/
2. Uruchom Rufus (nie wymaga instalacji)
3. Wybierz USB drive
4. Wybierz ISO: `BorgOS-Live-amd64.iso`
5. **WAŻNE**: Wybierz "DD Image" mode
6. Kliknij START

### Metoda 2: **Win32DiskImager**
1. **Pobierz**: https://sourceforge.net/projects/win32diskimager/
2. Zainstaluj i uruchom jako Administrator
3. Wybierz ISO i USB
4. Kliknij "Write"

### Metoda 3: **PowerShell** (dla zaawansowanych)
```powershell
# Uruchom PowerShell jako Administrator
diskpart
list disk
# Znajdź numer USB (np. Disk 2)
select disk 2
clean
create partition primary
format fs=fat32 quick
assign
exit

# Następnie użyj Rufus lub Etcher
```

---

## 🍎 NA MACOS (3 metody)

### Metoda 1: **Terminal dd** (szybka)
```bash
# Znajdź USB
diskutil list | grep "external"

# Odmontuj (NIE eject!)
diskutil unmountDisk /dev/disk4

# Nagraj ISO
sudo dd if=iso_output/BorgOS-Live-amd64.iso of=/dev/rdisk4 bs=1m

# Czekaj 10-15 minut (dla 7GB ISO)
```

### Metoda 2: **macOS Disk Utility** + Etcher
1. Otwórz Disk Utility
2. Wybierz USB → Erase → Format: "MS-DOS (FAT)"
3. Użyj Balena Etcher do nagrania ISO

### Metoda 3: **Homebrew + ddrescue** (niezawodna)
```bash
brew install ddrescue
sudo ddrescue iso_output/BorgOS-Live-amd64.iso /dev/rdisk4 --force
```

---

## 🐧 NA LINUX (najprostsze)

### Metoda 1: **dd**
```bash
# Znajdź USB
lsblk

# Nagraj
sudo dd if=BorgOS-Live-amd64.iso of=/dev/sdb bs=4M status=progress
sync
```

### Metoda 2: **Gnome Disks** (GUI)
1. Otwórz "Disks" 
2. Wybierz USB
3. Menu → "Restore Disk Image"
4. Wybierz ISO

---

## ⚠️ WAŻNE INFORMACJE

### Dlaczego USB wygląda na pusty w macOS?
- **To normalne!** macOS nie czyta filesystemów Linux
- USB jest bootowalny mimo że wygląda pusty
- Sprawdź na PC - będzie działał

### Jak sprawdzić czy działa?
1. Włóż USB do PC (nie Mac!)
2. Restart komputera
3. Wciśnij **F12** (lub F2, Del, Esc) podczas startu
4. Wybierz boot z USB
5. Powinien pojawić się BorgOS/Debian installer

### Co jeśli nie bootuje?
1. **Wyłącz Secure Boot** w BIOS
2. **Włącz Legacy Boot** jeśli masz stary PC
3. **Sprawdź czy USB jest USB 2.0** (niektóre stare PC nie czytają USB 3.0)

---

## 🏆 RANKING METOD

### Najłatwiejsze:
1. **Balena Etcher** - działa wszędzie
2. **Rufus** (Windows) - super opcje
3. **dd** (Linux/Mac) - szybkie

### Najszybsze:
1. **dd** z `bs=4M` lub `bs=1m`
2. **ddrescue** 
3. **Win32DiskImager**

### Najbezpieczniejsze:
1. **Balena Etcher** - weryfikuje automatycznie
2. **Rufus** - sprawdza błędy
3. **Gnome Disks** - GUI, trudno pomylić dysk

---

## 📝 GOTOWE KOMENDY DO SKOPIOWANIA

### macOS:
```bash
diskutil unmountDisk /dev/disk4 && sudo dd if=iso_output/BorgOS-Live-amd64.iso of=/dev/rdisk4 bs=1m
```

### Linux:
```bash
sudo dd if=BorgOS-Live-amd64.iso of=/dev/sdb bs=4M status=progress && sync
```

### Windows (użyj Rufus lub Etcher)

---

## 💡 PROTIP
**Jeśli masz problemy**, po prostu użyj **Balena Etcher** - zawsze działa!