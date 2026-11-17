#!/usr/bin/env python3
"""
Generate YOLO NCNN Detector Brand Assets:
- branding/icon.svg (editable vector master)
- branding/icon_foreground.svg & icon_foreground.png (1024x1024, transparent, safe zone <= 66%)
- branding/icon_background.png (1024x1024, solid #0B0F14)
- branding/icon_monochrome.svg & icon_monochrome.png (1024x1024, white-on-transparent)
- branding/icon.png (1024x1024 standalone master icon)
"""

import os
import subprocess
from pathlib import Path
from PIL import Image

BRANDING_DIR = Path("C:/dev/object-detector/branding")
BRANDING_DIR.mkdir(parents=True, exist_ok=True)

# Master SVG with solid background
ICON_SVG_CONTENT = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <!-- Background Gradient -->
    <radialGradient id="bgGrad" cx="50%" cy="50%" r="50%" fx="50%" fy="50%">
      <stop offset="0%" stop-color="#111827"/>
      <stop offset="100%" stop-color="#0B0F14"/>
    </radialGradient>

    <!-- Cyan Glow & Gradients -->
    <linearGradient id="cyanGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#67E8F9"/>
      <stop offset="100%" stop-color="#06B6D4"/>
    </linearGradient>

    <!-- Amber Iris Accent -->
    <linearGradient id="amberGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FBBF24"/>
      <stop offset="100%" stop-color="#F59E0B"/>
    </linearGradient>

    <!-- Blade Shading -->
    <linearGradient id="bladeGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#1E293B"/>
      <stop offset="100%" stop-color="#0F172A"/>
    </linearGradient>

    <!-- Subtle Drop Shadow -->
    <filter id="bracketShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="8" stdDeviation="16" flood-color="#06B6D4" flood-opacity="0.35"/>
    </filter>
  </defs>

  <!-- 1. Solid App Canvas Background -->
  <rect width="1024" height="1024" rx="228" fill="url(#bgGrad)"/>

  <!-- 2. Central Bounding-Box Corner Brackets (Object Detection Frame) -->
  <!-- Safe Zone: 66% diameter is ~676px (radius 338px). Box is 520x520 centered at (512, 512) -> [252, 772] -->
  <g filter="url(#bracketShadow)">
    <!-- Top-Left Bracket -->
    <path d="M 252 380 L 252 284 A 32 32 0 0 1 284 252 L 380 252"
          fill="none" stroke="url(#cyanGrad)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>
    
    <!-- Top-Right Bracket -->
    <path d="M 644 252 L 740 252 A 32 32 0 0 1 772 284 L 772 380"
          fill="none" stroke="url(#cyanGrad)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>

    <!-- Bottom-Right Bracket -->
    <path d="M 772 644 L 772 740 A 32 32 0 0 1 740 772 L 644 772"
          fill="none" stroke="url(#cyanGrad)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>

    <!-- Bottom-Left Bracket -->
    <path d="M 380 772 L 284 772 A 32 32 0 0 1 252 740 L 252 644"
          fill="none" stroke="url(#cyanGrad)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>

    <!-- Amber Detection Tag Anchor on Top-Left Corner -->
    <circle cx="284" cy="252" r="14" fill="#F59E0B"/>
    <circle cx="740" cy="772" r="14" fill="#F59E0B"/>
  </g>

  <!-- 3. Camera Lens Aperture Ring -->
  <circle cx="512" cy="512" r="192" fill="#0B0F14" stroke="#1E293B" stroke-width="14"/>
  <circle cx="512" cy="512" r="182" fill="none" stroke="url(#cyanGrad)" stroke-width="4" stroke-dasharray="14 10" opacity="0.7"/>

  <!-- 4. Six Interleaved Aperture Blades -->
  <g id="aperture-blades">
    <!-- Blade 1 -->
    <path d="M 512 332 L 620 400 L 570 480 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
    <!-- Blade 2 -->
    <path d="M 668 422 L 668 546 L 575 510 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
    <!-- Blade 3 -->
    <path d="M 620 624 L 512 692 L 512 590 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
    <!-- Blade 4 -->
    <path d="M 404 624 L 356 502 L 450 510 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
    <!-- Blade 5 -->
    <path d="M 356 422 L 404 332 L 450 434 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
    <!-- Blade 6 -->
    <path d="M 512 332 L 404 332 L 512 434 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
  </g>

  <!-- 5. Optical Center Aperture Iris & Amber Sensor Core -->
  <polygon points="512,442 572,477 572,547 512,582 452,547 452,477"
           fill="#0B0F14" stroke="url(#amberGrad)" stroke-width="8"/>
  
  <circle cx="512" cy="512" r="32" fill="url(#amberGrad)"/>
  <circle cx="512" cy="512" r="14" fill="#FFFFFF" opacity="0.9"/>
  
  <!-- Precision Target Crosshair Ticks -->
  <line x1="512" y1="400" x2="512" y2="422" stroke="#22D3EE" stroke-width="5" stroke-linecap="round"/>
  <line x1="512" y1="602" x2="512" y2="624" stroke="#22D3EE" stroke-width="5" stroke-linecap="round"/>
  <line x1="400" y1="512" x2="422" y2="512" stroke="#22D3EE" stroke-width="5" stroke-linecap="round"/>
  <line x1="602" y1="512" x2="624" y2="512" stroke="#22D3EE" stroke-width="5" stroke-linecap="round"/>
</svg>
"""

# Foreground SVG (Transparent background, artwork strictly within central 66% safe zone)
ICON_FOREGROUND_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="cyanGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#67E8F9"/>
      <stop offset="100%" stop-color="#06B6D4"/>
    </linearGradient>
    <linearGradient id="amberGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FBBF24"/>
      <stop offset="100%" stop-color="#F59E0B"/>
    </linearGradient>
    <linearGradient id="bladeGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#1E293B"/>
      <stop offset="100%" stop-color="#0F172A"/>
    </linearGradient>
    <filter id="bracketShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="6" stdDeviation="12" flood-color="#06B6D4" flood-opacity="0.4"/>
    </filter>
  </defs>

  <!-- Central Detection Bounding-Box Brackets (Within 66% Safe Zone) -->
  <g filter="url(#bracketShadow)">
    <path d="M 252 380 L 252 284 A 32 32 0 0 1 284 252 L 380 252"
          fill="none" stroke="url(#cyanGrad)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M 644 252 L 740 252 A 32 32 0 0 1 772 284 L 772 380"
          fill="none" stroke="url(#cyanGrad)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M 772 644 L 772 740 A 32 32 0 0 1 740 772 L 644 772"
          fill="none" stroke="url(#cyanGrad)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M 380 772 L 284 772 A 32 32 0 0 1 252 740 L 252 644"
          fill="none" stroke="url(#cyanGrad)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="284" cy="252" r="14" fill="#F59E0B"/>
    <circle cx="740" cy="772" r="14" fill="#F59E0B"/>
  </g>

  <!-- Lens Aperture -->
  <circle cx="512" cy="512" r="192" fill="#0B0F14" stroke="#1E293B" stroke-width="14"/>
  <circle cx="512" cy="512" r="182" fill="none" stroke="url(#cyanGrad)" stroke-width="4" stroke-dasharray="14 10" opacity="0.7"/>

  <!-- Six Interleaved Blades -->
  <path d="M 512 332 L 620 400 L 570 480 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
  <path d="M 668 422 L 668 546 L 575 510 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
  <path d="M 620 624 L 512 692 L 512 590 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
  <path d="M 404 624 L 356 502 L 450 510 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
  <path d="M 356 422 L 404 332 L 450 434 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>
  <path d="M 512 332 L 404 332 L 512 434 Z" fill="url(#bladeGrad)" stroke="#22D3EE" stroke-width="3"/>

  <!-- Optical Center Aperture Iris & Amber Sensor Core -->
  <polygon points="512,442 572,477 572,547 512,582 452,547 452,477"
           fill="#0B0F14" stroke="url(#amberGrad)" stroke-width="8"/>
  <circle cx="512" cy="512" r="32" fill="url(#amberGrad)"/>
  <circle cx="512" cy="512" r="14" fill="#FFFFFF" opacity="0.9"/>
  <line x1="512" y1="400" x2="512" y2="422" stroke="#22D3EE" stroke-width="5" stroke-linecap="round"/>
  <line x1="512" y1="602" x2="512" y2="624" stroke="#22D3EE" stroke-width="5" stroke-linecap="round"/>
  <line x1="400" y1="512" x2="422" y2="512" stroke="#22D3EE" stroke-width="5" stroke-linecap="round"/>
  <line x1="602" y1="512" x2="624" y2="512" stroke="#22D3EE" stroke-width="5" stroke-linecap="round"/>
</svg>
"""

# Monochrome SVG (White on transparent for Android 13+ Themed Icons)
ICON_MONOCHROME_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- Corner Brackets in solid white -->
  <path d="M 252 380 L 252 284 A 32 32 0 0 1 284 252 L 380 252"
        fill="none" stroke="#FFFFFF" stroke-width="48" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M 644 252 L 740 252 A 32 32 0 0 1 772 284 L 772 380"
        fill="none" stroke="#FFFFFF" stroke-width="48" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M 772 644 L 772 740 A 32 32 0 0 1 740 772 L 644 772"
        fill="none" stroke="#FFFFFF" stroke-width="48" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M 380 772 L 284 772 A 32 32 0 0 1 252 740 L 252 644"
        fill="none" stroke="#FFFFFF" stroke-width="48" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="284" cy="252" r="16" fill="#FFFFFF"/>
  <circle cx="740" cy="772" r="16" fill="#FFFFFF"/>

  <!-- Lens Aperture Outline -->
  <circle cx="512" cy="512" r="192" fill="none" stroke="#FFFFFF" stroke-width="16"/>

  <!-- Aperture Blades -->
  <path d="M 512 332 L 620 400 L 570 480 Z" fill="none" stroke="#FFFFFF" stroke-width="6"/>
  <path d="M 668 422 L 668 546 L 575 510 Z" fill="none" stroke="#FFFFFF" stroke-width="6"/>
  <path d="M 620 624 L 512 692 L 512 590 Z" fill="none" stroke="#FFFFFF" stroke-width="6"/>
  <path d="M 404 624 L 356 502 L 450 510 Z" fill="none" stroke="#FFFFFF" stroke-width="6"/>
  <path d="M 356 422 L 404 332 L 450 434 Z" fill="none" stroke="#FFFFFF" stroke-width="6"/>
  <path d="M 512 332 L 404 332 L 512 434 Z" fill="none" stroke="#FFFFFF" stroke-width="6"/>

  <!-- Center Iris & Core -->
  <polygon points="512,442 572,477 572,547 512,582 452,547 452,477"
           fill="none" stroke="#FFFFFF" stroke-width="12"/>
  <circle cx="512" cy="512" r="32" fill="#FFFFFF"/>
  <line x1="512" y1="400" x2="512" y2="422" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round"/>
  <line x1="512" y1="602" x2="512" y2="624" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round"/>
  <line x1="400" y1="512" x2="422" y2="512" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round"/>
  <line x1="602" y1="512" x2="624" y2="512" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round"/>
</svg>
"""

def write_svg_files():
    (BRANDING_DIR / "icon.svg").write_text(ICON_SVG_CONTENT, encoding="utf-8")
    (BRANDING_DIR / "icon_foreground.svg").write_text(ICON_FOREGROUND_SVG, encoding="utf-8")
    (BRANDING_DIR / "icon_monochrome.svg").write_text(ICON_MONOCHROME_SVG, encoding="utf-8")
    print("Wrote SVG sources to branding/")

def render_svg_to_png(svg_path: Path, png_path: Path, width=1024, height=1024, bg_transparent=True):
    # Create HTML wrapper to render via Edge headless
    bg_style = "background: transparent;" if bg_transparent else "background: #0B0F14;"
    html_content = f"""<!DOCTYPE html>
<html>
<head>
<style>
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  html, body {{ width: {width}px; height: {height}px; {bg_style} overflow: hidden; }}
  svg {{ width: {width}px; height: {height}px; display: block; }}
</style>
</head>
<body>
{svg_path.read_text(encoding='utf-8')}
</body>
</html>
"""
    tmp_html = svg_path.with_suffix(".html")
    tmp_html.write_text(html_content, encoding="utf-8")

    edge_exe = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    cmd = [
        edge_exe,
        "--headless",
        "--disable-gpu",
        "--force-device-scale-factor=1",
        f"--window-size={width},{height}",
        f"--screenshot={str(png_path.resolve())}",
        str(tmp_html.resolve())
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    tmp_html.unlink()
    print(f"Rendered {png_path} ({width}x{height})")

def generate_background_png():
    # 1024x1024 solid #0B0F14
    bg_img = Image.new("RGBA", (1024, 1024), (11, 15, 20, 255))
    bg_path = BRANDING_DIR / "icon_background.png"
    bg_img.save(bg_path, "PNG")
    print(f"Generated {bg_path} (1024x1024 solid #0B0F14)")

def main():
    write_svg_files()
    render_svg_to_png(BRANDING_DIR / "icon.svg", BRANDING_DIR / "icon.png", 1024, 1024, bg_transparent=False)
    render_svg_to_png(BRANDING_DIR / "icon_foreground.svg", BRANDING_DIR / "icon_foreground.png", 1024, 1024, bg_transparent=True)
    render_svg_to_png(BRANDING_DIR / "icon_monochrome.svg", BRANDING_DIR / "icon_monochrome.png", 1024, 1024, bg_transparent=True)
    generate_background_png()
    print("\nAll brand assets successfully generated in branding/!")

if __name__ == "__main__":
    main()
