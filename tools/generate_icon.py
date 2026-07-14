from PIL import Image, ImageDraw

def main():
    w = 1024
    img = Image.new('RGBA', (w, w), color='#111512')
    draw = ImageDraw.Draw(img)
    
    origin_x, origin_y = 0, 0
    
    # BG_CARD2 = #293128
    rx, ry = origin_x + w * 0.06, origin_y + w * 0.06
    rw, rh = w * 0.88, w * 0.88
    draw.rectangle([rx, ry, rx + rw, ry + rh], fill='#293128')
    
    # ACCENT_DIM = #5E7F3E
    r1_x = rx + w * 0.08
    r1_y = ry + w * 0.08
    r_size = w * 0.36
    draw.rectangle([r1_x, r1_y, r1_x + r_size, r1_y + r_size], fill='#5E7F3E')
    
    r2_x = rx + w * 0.44
    r2_y = ry + w * 0.44
    draw.rectangle([r2_x, r2_y, r2_x + r_size, r2_y + r_size], fill='#5E7F3E')
    
    # TEXT = #F0F1EC
    k_pts = [
        (origin_x + w * 0.35, origin_y + w * 0.80), # Base Bottom Left
        (origin_x + w * 0.65, origin_y + w * 0.80), # Base Bottom Right
        (origin_x + w * 0.62, origin_y + w * 0.70), # Base Top Right
        (origin_x + w * 0.55, origin_y + w * 0.65), # Neck Back
        (origin_x + w * 0.65, origin_y + w * 0.50), # Head Back
        (origin_x + w * 0.60, origin_y + w * 0.30), # Top Head
        (origin_x + w * 0.45, origin_y + w * 0.35), # Nose Top
        (origin_x + w * 0.30, origin_y + w * 0.45), # Nose Tip
        (origin_x + w * 0.35, origin_y + w * 0.55), # Jaw
        (origin_x + w * 0.45, origin_y + w * 0.50), # Neck Front
        (origin_x + w * 0.38, origin_y + w * 0.70), # Base Top Left
    ]
    draw.polygon(k_pts, fill='#F0F1EC')
    
    # Eye (BG_CARD = #1E241F)
    cx, cy = origin_x + w * 0.52, origin_y + w * 0.42
    cr = w * 0.025
    draw.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill='#1E241F')
    
    # Pedestal (TEXT = #F0F1EC)
    px, py = origin_x + w * 0.30, origin_y + w * 0.82
    pw, ph = w * 0.40, w * 0.06
    draw.rectangle([px, py, px + pw, py + ph], fill='#F0F1EC')
    
    img.save('assets/brand/app_icon_1024.png')
    img.save('assets/brand/splash.png')

if __name__ == '__main__':
    main()
