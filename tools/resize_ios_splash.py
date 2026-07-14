import os
import shutil
from PIL import Image

def main():
    src_path = 'assets/brand/app_icon_1024.png'
    dest_dir = 'Chess/Images.xcassets/SplashImage.imageset'
    
    if not os.path.exists(src_path):
        return
        
    img = Image.open(src_path).convert('RGB')
    
    # 3x (1024x1024)
    img.save(os.path.join(dest_dir, 'splash@3x.png'), 'PNG')
    
    # 2x (682x682)
    img_2x = img.resize((682, 682), Image.Resampling.LANCZOS)
    img_2x.save(os.path.join(dest_dir, 'splash@2x.png'), 'PNG')

if __name__ == '__main__':
    main()
