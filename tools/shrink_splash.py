from PIL import Image

def main():
    src_path = 'assets/brand/app_icon_1024.png'
    dest_path = 'assets/brand/splash.png'
    
    img = Image.open(src_path).convert('RGBA')
    
    # Resize the image to 256x256 so it looks normal-sized in the center of the Godot boot screen
    # rather than filling the entire display
    img_resized = img.resize((256, 256), Image.Resampling.LANCZOS)
    img_resized.save(dest_path, 'PNG')
    print("Shrunk splash.png to 256x256")

if __name__ == '__main__':
    main()
