# BorgOS Branding - Wymagania Graficzne

## 🎨 Lista Plików Graficznych do Wygenerowania

### 1. Boot Loader Graphics (ISOLINUX/GRUB)

#### splash.png
- **Rozmiar**: 640x480 px (4:3) 
- **Format**: PNG, 256 kolorów (8-bit)
- **Użycie**: Tło ekranu bootloadera ISOLINUX
- **Zawartość**: 
  - Logo BorgOS/Borg.tools
  - Gradient tła (ciemny, tech/cyber styl)
  - Tekst: "BorgOS - AI-First Operating System"

#### grub-bg.png  
- **Rozmiar**: 1920x1080 px (16:9)
- **Format**: PNG, 24-bit color
- **Użycie**: Tło GRUB dla UEFI boot
- **Zawartość**:
  - Wysokiej jakości logo Borg.tools
  - Futurystyczne tło (mesh, neural network wzór)
  - Subtelne elementy AI/tech

### 2. Plymouth Boot Splash (animacja podczas startu)

#### plymouth-logo.png
- **Rozmiar**: 256x256 px
- **Format**: PNG z przezroczystością
- **Użycie**: Logo podczas boot sequence
- **Zawartość**: Logo Borg.tools (może pulsować)

#### plymouth-background.png
- **Rozmiar**: 1920x1080 px
- **Format**: PNG
- **Użycie**: Tło podczas ładowania systemu
- **Zawartość**: Ciemne tło z subtelnymi elementami tech

#### spinner.png
- **Rozmiar**: 360x360 px (36 klatek 10x10 px każda)
- **Format**: PNG sprite sheet
- **Użycie**: Animacja ładowania
- **Zawartość**: Obracające się koło/hexagon w stylu Borg

### 3. Installer Graphics (Debian Installer)

#### installer-banner.png
- **Rozmiar**: 800x75 px
- **Format**: PNG
- **Użycie**: Banner na górze instalatora
- **Zawartość**: Logo + "BorgOS Installation"

#### installer-sidebar.png
- **Rozmiar**: 120x280 px
- **Format**: PNG
- **Użycie**: Boczny panel w instalatorze
- **Zawartość**: Pionowe logo lub wzór

### 4. Desktop Wallpapers

#### wallpaper-1920x1080.png
- **Rozmiar**: 1920x1080 px
- **Format**: PNG/JPG wysokiej jakości
- **Zawartość**: 
  - Futurystyczne tło
  - Subtelne logo Borg.tools
  - Motywy: AI, neural networks, cyber

#### wallpaper-4k.png
- **Rozmiar**: 3840x2160 px
- **Format**: PNG/JPG wysokiej jakości

### 5. Icons & Logos

#### logo.svg
- **Format**: SVG (skalowalny)
- **Użycie**: Główne logo Borg.tools
- **Warianty**: 
  - Pełne (z tekstem)
  - Ikona (sam symbol)
  - Monochromatyczne

#### favicon.ico
- **Rozmiary**: 16x16, 32x32, 48x48, 64x64
- **Format**: ICO multi-resolution
- **Użycie**: Ikona systemowa

#### borgos-icon.png
- **Rozmiary**: 16, 24, 32, 48, 64, 128, 256, 512 px
- **Format**: PNG z przezroczystością
- **Użycie**: Ikony aplikacji

### 6. Color Palette & Style Guide

#### Kolory BorgOS:
```css
/* Primary Colors */
--borg-primary: #00D4FF;     /* Cyber Blue */
--borg-secondary: #FF6B35;   /* Orange Accent */
--borg-dark: #0A0E27;        /* Deep Dark Blue */
--borg-darker: #050714;      /* Almost Black */

/* Accent Colors */
--borg-success: #00FF88;     /* Green */
--borg-warning: #FFD93D;     /* Yellow */
--borg-error: #FF3366;       /* Red */

/* Text Colors */
--text-primary: #FFFFFF;     /* White */
--text-secondary: #B8BCC8;   /* Light Gray */
--text-muted: #6C7293;       /* Muted Gray */

/* Background Gradients */
--gradient-1: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
--gradient-2: linear-gradient(135deg, #00D4FF 0%, #0A0E27 100%);
```

### 7. ASCII Art for Terminal

#### logo.ascii
```
    ____                   ____  _____
   / __ )____  _________ _/ __ \/ ___/
  / __  / __ \/ ___/ __ `/ / / /\__ \ 
 / /_/ / /_/ / /  / /_/ / /_/ /___/ / 
/_____/\____/_/   \__, /\____//____/  
                 /____/  AI-First OS   
```

### 8. Specyfikacje Techniczne

#### Formaty wspierane przez instalator:
- **PNG**: Preferowany dla większości grafik
- **XPM**: Dla niektórych elementów GRUB
- **PCX**: Legacy format dla ISOLINUX (opcjonalnie)
- **SVG**: Dla ikon skalowalnych

#### Paleta kolorów dla ISOLINUX (16 kolorów):
```
#000000 #800000 #008000 #808000
#000080 #800080 #008080 #C0C0C0
#808080 #FF0000 #00FF00 #FFFF00
#0000FF #FF00FF #00FFFF #FFFFFF
```

## 🛠️ Narzędzia do Generowania

### Rekomendowane:
1. **GIMP** - Do tworzenia PNG i edycji
2. **Inkscape** - Do logo SVG
3. **ImageMagick** - Do konwersji i batch processing
4. **Krita** - Do wallpaperów artystycznych

### Komendy do konwersji:
```bash
# Konwersja do 256 kolorów dla ISOLINUX
convert input.png -colors 256 -depth 8 splash.png

# Tworzenie różnych rozmiarów ikon
convert logo.svg -resize 16x16 icon-16.png
convert logo.svg -resize 32x32 icon-32.png
# etc...

# Tworzenie ICO z wielu rozmiarów
convert icon-16.png icon-32.png icon-48.png favicon.ico

# Optymalizacja PNG
optipng -o7 *.png
```

## 📁 Struktura Katalogów

```
branding/
├── boot/
│   ├── isolinux/
│   │   └── splash.png
│   └── grub/
│       └── grub-bg.png
├── plymouth/
│   ├── logo.png
│   ├── background.png
│   └── spinner.png
├── installer/
│   ├── banner.png
│   └── sidebar.png
├── wallpapers/
│   ├── borgos-1920x1080.png
│   └── borgos-4k.png
├── icons/
│   ├── logo.svg
│   ├── favicon.ico
│   └── sizes/
│       ├── 16x16.png
│       ├── 32x32.png
│       └── ...
└── ascii/
    └── logo.txt
```

## 🎯 Przykładowe Prompty do AI (DALL-E, Midjourney, etc.)

### Dla Wallpaper:
"Futuristic cyberpunk operating system wallpaper, dark blue and cyan colors, neural network patterns, hexagonal grid, glowing connections, subtle tech elements, professional, clean, 4K resolution, with small 'Borg.tools' logo"

### Dla Logo:
"Minimalist tech logo for 'BorgOS', hexagonal shape, circuit patterns, cyan and blue gradient, modern, clean, scalable vector design, AI-inspired, professional"

### Dla Boot Splash:
"Dark boot screen background, matrix-style grid, subtle animated particles, technological, professional OS installer look, dark navy blue base, cyan accents"