#!/bin/bash
# Generate all branding assets for BorgOS

set -e

BRANDING_DIR="$(pwd)/branding"
mkdir -p ${BRANDING_DIR}/{boot,plymouth,installer,wallpapers,icons/sizes,ascii}

echo "================================================"
echo " BorgOS Branding Asset Generator"
echo " Generating graphics for Borg.tools"
echo "================================================"

# Function to create a simple splash screen
create_splash() {
    echo "[1/8] Creating boot splash screens..."
    
    # Create a simple text-based splash using ImageMagick
    if command -v convert &> /dev/null; then
        # ISOLINUX splash (640x480)
        convert -size 640x480 xc:'#0A0E27' \
            -font Arial -pointsize 48 -fill '#00D4FF' \
            -gravity center -annotate +0-50 'BorgOS' \
            -font Arial -pointsize 20 -fill '#B8BCC8' \
            -gravity center -annotate +0+20 'AI-First Operating System' \
            -font Arial -pointsize 16 -fill '#6C7293' \
            -gravity center -annotate +0+60 'Powered by Borg.tools' \
            ${BRANDING_DIR}/boot/splash.png
        
        # GRUB background (1920x1080)
        convert -size 1920x1080 \
            gradient:'#0A0E27'-'#050714' \
            -font Arial -pointsize 72 -fill '#00D4FF' \
            -gravity center -annotate +0-100 'BorgOS' \
            -font Arial -pointsize 32 -fill '#B8BCC8' \
            -gravity center -annotate +0+0 'Multi-Agent AI Operating System' \
            -font Arial -pointsize 24 -fill '#6C7293' \
            -gravity center -annotate +0+80 'Borg.tools' \
            ${BRANDING_DIR}/boot/grub-bg.png
    else
        echo "⚠️  ImageMagick not found. Install with: brew install imagemagick"
    fi
}

# Function to create Plymouth boot animation assets
create_plymouth() {
    echo "[2/8] Creating Plymouth boot animation..."
    
    if command -v convert &> /dev/null; then
        # Logo for Plymouth
        convert -size 256x256 xc:transparent \
            -fill '#00D4FF' -draw 'circle 128,128 128,200' \
            -fill '#0A0E27' -draw 'circle 128,128 128,180' \
            -fill '#00D4FF' -font Arial -pointsize 72 \
            -gravity center -annotate +0+0 'B' \
            ${BRANDING_DIR}/plymouth/logo.png
        
        # Background
        convert -size 1920x1080 gradient:'#0A0E27'-'#050714' \
            ${BRANDING_DIR}/plymouth/background.png
    fi
}

# Function to create installer graphics
create_installer() {
    echo "[3/8] Creating installer graphics..."
    
    if command -v convert &> /dev/null; then
        # Banner
        convert -size 800x75 gradient:'#0A0E27'-'#00D4FF' \
            -font Arial -pointsize 32 -fill white \
            -gravity west -annotate +20+0 'BorgOS Installation' \
            ${BRANDING_DIR}/installer/banner.png
        
        # Sidebar
        convert -size 120x280 gradient:'#00D4FF'-'#0A0E27' \
            -rotate 90 \
            ${BRANDING_DIR}/installer/sidebar.png
    fi
}

# Function to create wallpapers
create_wallpapers() {
    echo "[4/8] Creating wallpapers..."
    
    if command -v convert &> /dev/null; then
        # 1920x1080 wallpaper
        convert -size 1920x1080 \
            plasma:fractal \
            -colorspace RGB \
            -modulate 100,50 \
            -fill '#0A0E27' -colorize 80% \
            -font Arial -pointsize 48 -fill '#00D4FF33' \
            -gravity southeast -annotate +50+50 'Borg.tools' \
            ${BRANDING_DIR}/wallpapers/borgos-1920x1080.png
        
        # 4K wallpaper
        convert -size 3840x2160 \
            plasma:fractal \
            -colorspace RGB \
            -modulate 100,50 \
            -fill '#0A0E27' -colorize 80% \
            -font Arial -pointsize 72 -fill '#00D4FF33' \
            -gravity southeast -annotate +100+100 'Borg.tools' \
            ${BRANDING_DIR}/wallpapers/borgos-4k.png
    fi
}

# Function to create icons
create_icons() {
    echo "[5/8] Creating icons..."
    
    # Use the SVG logo to generate different sizes
    if command -v convert &> /dev/null; then
        for size in 16 24 32 48 64 128 256 512; do
            convert ${BRANDING_DIR}/logo.svg \
                -resize ${size}x${size} \
                ${BRANDING_DIR}/icons/sizes/icon-${size}.png
        done
        
        # Create favicon.ico
        convert ${BRANDING_DIR}/icons/sizes/icon-16.png \
                ${BRANDING_DIR}/icons/sizes/icon-32.png \
                ${BRANDING_DIR}/icons/sizes/icon-48.png \
                ${BRANDING_DIR}/icons/sizes/icon-64.png \
                ${BRANDING_DIR}/icons/favicon.ico
    fi
}

# Function to create ASCII art
create_ascii() {
    echo "[6/8] Creating ASCII art..."
    
    cat > ${BRANDING_DIR}/ascii/logo.txt << 'ASCII'
    ____                   ____  _____
   / __ )____  _________ _/ __ \/ ___/
  / __  / __ \/ ___/ __ `/ / / /\__ \ 
 / /_/ / /_/ / /  / /_/ / /_/ /___/ / 
/_____/\____/_/   \__, /\____//____/  
                 /____/                
        AI-First Operating System      
           Powered by Borg.tools       
ASCII

    cat > ${BRANDING_DIR}/ascii/small.txt << 'ASCII'
╔══════════════════════╗
║   B O R G O S   v3   ║
║   borg.tools         ║
╚══════════════════════╝
ASCII
}

# Function to create CSS theme
create_theme() {
    echo "[7/8] Creating CSS theme..."
    
    cat > ${BRANDING_DIR}/theme.css << 'CSS'
/* BorgOS Theme - Borg.tools */

:root {
    /* Primary Colors */
    --borg-primary: #00D4FF;
    --borg-secondary: #FF6B35;
    --borg-dark: #0A0E27;
    --borg-darker: #050714;
    
    /* Accent Colors */
    --borg-success: #00FF88;
    --borg-warning: #FFD93D;
    --borg-error: #FF3366;
    
    /* Text Colors */
    --text-primary: #FFFFFF;
    --text-secondary: #B8BCC8;
    --text-muted: #6C7293;
    
    /* Background Gradients */
    --gradient-main: linear-gradient(135deg, #00D4FF 0%, #0A0E27 100%);
    --gradient-dark: linear-gradient(135deg, #0A0E27 0%, #050714 100%);
    
    /* Effects */
    --glow: 0 0 20px rgba(0, 212, 255, 0.5);
    --shadow: 0 10px 40px rgba(0, 0, 0, 0.3);
}

body {
    background: var(--gradient-dark);
    color: var(--text-primary);
    font-family: 'Segoe UI', system-ui, sans-serif;
}

.borg-logo {
    color: var(--borg-primary);
    text-shadow: var(--glow);
}

.borg-button {
    background: var(--gradient-main);
    border: none;
    padding: 12px 24px;
    border-radius: 6px;
    color: white;
    font-weight: bold;
    cursor: pointer;
    transition: transform 0.2s;
}

.borg-button:hover {
    transform: scale(1.05);
    box-shadow: var(--shadow);
}
CSS
}

# Function to create GRUB theme config
create_grub_theme() {
    echo "[8/8] Creating GRUB theme..."
    
    mkdir -p ${BRANDING_DIR}/boot/grub-theme
    
    cat > ${BRANDING_DIR}/boot/grub-theme/theme.txt << 'GRUB'
# BorgOS GRUB Theme
# Borg.tools

# General settings
title-text: "BorgOS Boot Menu"
desktop-image: "grub-bg.png"
desktop-color: "#0A0E27"
terminal-font: "Unifont Regular 16"
terminal-box: "terminal_box_*.png"

# Boot menu
+ boot_menu {
  left = 15%
  top = 30%
  width = 70%
  height = 40%
  item_font = "Unifont Regular 16"
  item_color = "#B8BCC8"
  selected_item_color = "#00D4FF"
  item_height = 24
  item_spacing = 12
}

# Progress bar
+ progress_bar {
  id = "__timeout__"
  left = 15%
  top = 75%
  width = 70%
  height = 20
  show_text = true
  text = "@TIMEOUT_NOTIFICATION_SHORT@"
  font = "Unifont Regular 12"
  text_color = "#6C7293"
  bar_style = "progress_bar_*.png"
  highlight_style = "progress_highlight_*.png"
}

# Labels
+ label {
  left = 15%
  top = 90%
  width = 70%
  text = "Powered by Borg.tools"
  font = "Unifont Regular 12"
  color = "#6C7293"
  align = "center"
}
GRUB
}

# Main execution
main() {
    # Check for dependencies
    if ! command -v convert &> /dev/null; then
        echo "⚠️  Installing ImageMagick..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install imagemagick
        else
            apt-get update && apt-get install -y imagemagick
        fi
    fi
    
    # Generate all assets
    create_splash
    create_plymouth
    create_installer
    create_wallpapers
    create_icons
    create_ascii
    create_theme
    create_grub_theme
    
    echo ""
    echo "================================================"
    echo " ✅ Branding Assets Generated!"
    echo "================================================"
    echo " Location: ${BRANDING_DIR}"
    echo ""
    echo " Generated files:"
    find ${BRANDING_DIR} -type f -name "*.png" -o -name "*.svg" -o -name "*.txt" -o -name "*.css" | sort
    echo ""
    echo " Next steps:"
    echo " 1. Review and customize the generated assets"
    echo " 2. Use professional tools for final versions:"
    echo "    - GIMP/Photoshop for splash screens"
    echo "    - Inkscape/Illustrator for logos"
    echo "    - Figma/Sketch for UI elements"
    echo " 3. Include in ISO build process"
    echo "================================================"
}

main "$@"