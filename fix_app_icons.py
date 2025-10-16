#!/usr/bin/env python3
"""
Script to remove alpha channel from app icons.
Apple requires app icons without transparency.
"""
import os
import sys
from PIL import Image

def remove_alpha(image_path):
    """Remove alpha channel from PNG image."""
    print(f"Processing: {image_path}")
    
    # Open image
    img = Image.open(image_path)
    
    # Check if image has alpha channel
    if img.mode in ('RGBA', 'LA'):
        print(f"  - Has alpha channel, converting...")
        
        # Create white background
        background = Image.new('RGB', img.size, (255, 255, 255))
        
        # Paste image on white background
        if img.mode == 'RGBA':
            background.paste(img, mask=img.split()[3])  # Use alpha as mask
        else:
            background.paste(img, mask=img.split()[1])
        
        # Save as RGB
        background.save(image_path, 'PNG')
        print(f"  ✓ Converted to RGB")
    else:
        print(f"  - Already RGB, no changes needed")

def main():
    # Main app icons
    app_icon_dir = "Hardcover Reading Widget/Assets.xcassets/AppIcon.appiconset"
    
    # Widget icons (if they exist)
    widget_icon_dir = "ReadingProgressWidget/Assets.xcassets/AppIcon.appiconset"
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    for icon_dir in [app_icon_dir, widget_icon_dir]:
        full_path = os.path.join(script_dir, icon_dir)
        
        if not os.path.exists(full_path):
            print(f"Directory not found: {full_path}")
            continue
        
        print(f"\n📁 Processing directory: {icon_dir}")
        
        # Process all PNG files
        for filename in os.listdir(full_path):
            if filename.endswith('.png'):
                image_path = os.path.join(full_path, filename)
                remove_alpha(image_path)
    
    print("\n✅ Done! All app icons processed.")

if __name__ == "__main__":
    try:
        from PIL import Image
    except ImportError:
        print("❌ Error: PIL (Pillow) not installed.")
        print("Installing Pillow...")
        os.system(f"{sys.executable} -m pip install Pillow")
        print("\nPlease run the script again.")
        sys.exit(1)
    
    main()
