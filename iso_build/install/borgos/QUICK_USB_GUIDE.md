# 🚀 SZYBKI PRZEWODNIK - BorgOS na USB

## ⚡ NAJSZYBSZA METODA (5 minut)

### Krok 1: Nagraj Debian na USB
```bash
# Znajdź USB (8GB)
diskutil list | grep "8.0 GB"

# Nagraj ISO (podmień disk4 na swój)
sudo dd if=debian.iso of=/dev/rdisk4 bs=1m
```

### Krok 2: Przenieś pakiet BorgOS
- Skopiuj `borgos-complete.tar.gz` na drugi pendrive lub przez sieć

### Krok 3: Zainstaluj na PC
1. Boot z USB (F12 podczas startu)
2. Zainstaluj Debian 12 (minimal + SSH)
3. Po restarcie:
```bash
# Skopiuj pakiet
scp borgos-complete.tar.gz user@IP:/home/user/

# Zainstaluj
ssh user@IP
tar -xzf borgos-complete.tar.gz
cd borgos
sudo bash installer/install_all.sh
```

## 🎯 CO OTRZYMASZ

- **Mistral 7B** (4.1GB) - główny model AI
- **Llama 3.2** (2GB) - backup
- **WebUI**: http://IP:6969
- **CLI**: `borg "pytanie"`

## 📦 PLIKI GOTOWE

✅ `debian.iso` (631MB) - gotowy do nagrania
✅ `borgos-complete.tar.gz` - cały system BorgOS

## 💡 ALTERNATYWA: Balena Etcher

1. Pobierz: https://etcher.balena.io/
2. Wybierz `debian.iso`
3. Wybierz USB
4. Flash!

---

**Czas instalacji**: ~30 minut (z pobieraniem modeli)
**Wymagania**: 8GB RAM, 20GB dysku