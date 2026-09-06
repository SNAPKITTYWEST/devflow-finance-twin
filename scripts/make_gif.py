"""Generate a sleek animated GIF for the README."""
from PIL import Image, ImageDraw, ImageFont
import math

W, H = 800, 200
BG = (10, 10, 15)
GOLD = (207, 181, 59)
CYAN = (0, 200, 220)
WHITE = (255, 255, 255)
DIM = (40, 40, 50)

frames = []

def draw_rounded_rect(draw, xy, radius, fill):
    x0, y0, x1, y1 = xy
    draw.rectangle([x0+radius, y0, x1-radius, y1], fill=fill)
    draw.rectangle([x0, y0+radius, x1, y1-radius], fill=fill)
    draw.pieslice([x0, y0, x0+2*radius, y0+2*radius], 180, 270, fill=fill)
    draw.pieslice([x1-2*radius, y0, x1, y0+2*radius], 270, 360, fill=fill)
    draw.pieslice([x0, y1-2*radius, x0+2*radius, y1], 90, 180, fill=fill)
    draw.pieslice([x1-2*radius, y1-2*radius, x1, y1], 0, 90, fill=fill)

for frame_idx in range(24):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    # Progress bar animation
    progress = frame_idx / 23.0
    bar_x = int(50 + progress * 700)
    draw.line([(50, 100), (750, 100)], fill=DIM, width=4)
    draw.line([(50, 100), (bar_x, 100)], fill=GOLD, width=4)

    # Pulsing dots along the bar
    for i in range(6):
        x = 50 + int(i * 140)
        phase = (frame_idx + i * 4) % 24
        pulse = 1.0 + 0.3 * math.sin(phase * math.pi / 12)
        r = int(6 * pulse)
        color = CYAN if i < int(progress * 6) + 1 else DIM
        draw.ellipse([x-r, 100-r, x+r, 100+r], fill=color)

    # Title text
    try:
        font_title = ImageFont.truetype("arial.ttf", 28)
        font_sub = ImageFont.truetype("arial.ttf", 14)
    except:
        font_title = ImageFont.load_default()
        font_sub = ImageFont.load_default()

    title = "DEVFLOW FINANCE TWIN"
    bbox = draw.textbbox((0,0), title, font=font_title)
    tw = bbox[2] - bbox[0]
    draw.text(((W - tw) // 2, 20), title, fill=GOLD, font=font_title)

    # Subtitle with phase labels
    phases = ["WORM", "QUANTUM", "LEDGER", "AUDIT", "Sovereign", "TWIN"]
    phase_idx = int(progress * 6) % 6
    sub = f"{phases[phase_idx]} :: DEED-089"
    bbox2 = draw.textbbox((0,0), sub, font=font_sub)
    sw = bbox2[2] - bbox2[0]
    draw.text(((W - sw) // 2, 145), sub, fill=CYAN, font=font_sub)

    # Bottom line
    draw.line([(50, 180), (750, 180)], fill=DIM, width=1)

    frames.append(img.copy())

out = "assets/sovharmony.gif"
import os
os.makedirs("assets", exist_ok=True)
frames[0].save(out, save_all=True, append_images=frames[1:], duration=80, loop=0)
print(f"Created {out}")
