import os
from PIL import Image

def main():
    src_path = 'assets/brand/app_icon_1024.png'
    dest_dir = 'Chess/Images.xcassets/AppIcon.appiconset'
    
    if not os.path.exists(src_path):
        print(f"Source image {src_path} not found.")
        return
        
    img = Image.open(src_path).convert('RGBA')
    
    for filename in os.listdir(dest_dir):
        if filename.endswith('.png'):
            parts = filename.replace('.png', '').split('-')
            if len(parts) >= 2:
                try:
                    size = int(parts[1])
                    print(f"Resizing {filename} to {size}x{size}...")
                    resized = img.resize((size, size), Image.Resampling.LANCZOS)
                    # Convert to RGB if needed to remove alpha, Apple App Store requires no alpha channel
                    # Actually, PIL drops alpha if we convert to RGB.
                    background = Image.new('RGB', resized.size, (17, 21, 18)) # #111512
                    background.paste(resized, mask=resized.split()[3]) # 3 is the alpha channel
                    
                    background.save(os.path.join(dest_dir, filename), 'PNG')
                except ValueError:
                    pass

if __name__ == '__main__':
    main()
