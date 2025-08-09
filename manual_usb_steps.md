# 🔧 MANUAL USB CREATION STEPS FOR BORGOS

## ✅ Kroki do wykonania w terminalu:

### 1. Sprawdź czy ISO jest pobrany (631MB)
```bash
ls -lh debian.iso
```
Jeśli nie ma lub jest za mały, pobierz:
```bash
wget -O debian.iso https://cdimage.debian.org/cdimage/archive/12.8.0/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso
```

### 2. Znajdź pendrive (8GB)
```bash
diskutil list | grep "8.0 GB" -B3
```
Zapamiętaj numer (np. disk4)

### 3. CAŁKOWICIE wymaż pendrive (WAŻNE!)
```bash
sudo diskutil eraseDisk FREE UNTITLED /dev/disk4
```

### 4. Odmontuj pendrive
```bash
sudo diskutil unmountDisk force /dev/disk4
```

### 5. Nagraj ISO na pendrive
```bash
sudo dd if=debian.iso of=/dev/rdisk4 bs=1m
```
⏱️ To potrwa 5-10 minut. Poczekaj aż się zakończy!

### 6. Synchronizuj dane
```bash
sync
```

### 7. Odmontuj ponownie
```bash
sudo diskutil unmountDisk force /dev/disk4
```

### 8. Wyjmij pendrive
Fizycznie wyjmij pendrive z portu USB

## ⚠️ WAŻNE INFORMACJE:

1. **Pendrive będzie wyglądał na PUSTY w macOS** - to normalne!
2. macOS nie potrafi czytać filesystemów Linux
3. Pendrive JEST bootowalny mimo że wygląda na pusty

## 🖥️ Jak sprawdzić czy działa:

1. Włóż pendrive do komputera x86 (PC)
2. Podczas startu wciśnij F12 (lub F2, Del, Esc)
3. Wybierz boot z USB
4. Powinien pojawić się Debian installer

## 📦 Po instalacji Debian:

1. Skopiuj plik `borgos-installer.tar.gz` na system docelowy
2. Rozpakuj: `tar -xzf borgos-installer.tar.gz`
3. Zainstaluj: `cd borgos && sudo bash installer/install_all.sh`

## 🔍 Jeśli pendrive NIE bootuje:

Spróbuj alternatywnej metody z Balena Etcher:
1. Pobierz Balena Etcher: https://etcher.balena.io/
2. Uruchom Etcher
3. Wybierz debian.iso
4. Wybierz pendrive 8GB
5. Kliknij "Flash!"

---
⚡ BorgOS zainstaluje:
- Mistral 7B (4.1GB) - główny model AI
- Llama 3.2 (2GB) - backup
- WebUI na porcie 6969
- Wszystkie usługi BorgOS