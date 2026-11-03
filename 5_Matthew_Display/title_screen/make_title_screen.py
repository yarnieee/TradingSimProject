"""Draws the monitor's title screen: Bull vs Bear, the five bots, PRESS START.

320 x 180 pixels in 16 colours, shown 4x on the 1280 x 720 monitor.
Writes title_screen.mem (one hex digit a pixel, row by row, 57,600 lines)
next to vga_screen's other .mem files, and title_screen_preview.png (4x).

Colour 15 blinks in vga_screen (bright, then the button's own colour), so
the PRESS START text is drawn in colour 15.

    python3 make_title_screen.py
"""
import os
from PIL import Image, ImageDraw

W, H = 320, 180
HERE = os.path.dirname(os.path.abspath(__file__))

# 16 colours, 4 bits each of R, G, B (the VGA port). Keep in step with title_rgb in vga_screen.v.
PALETTE = [
    0x112,  # 0  background
    0x224,  # 1  grid
    0x349,  # 2  panel blue
    0xFFF,  # 3  white
    0xAAB,  # 4  robot grey
    0x000,  # 5  outline
    0xFD2,  # 6  yellow
    0xF82,  # 7  orange
    0x3D4,  # 8  green
    0x173,  # 9  dark green
    0xE33,  # 10 red
    0x812,  # 11 dark red
    0xEDA,  # 12 cream
    0x5DF,  # 13 cyan
    0x226,  # 14 button
    0xFF6,  # 15 PRESS START (blinks to colour 14)
]
BG, GRID, PANEL, WHITE, GREY, K, YEL, ORA, GRN, DGRN, RED, DRED, CREAM, CYAN, BTN, BLINK = range(16)

FONT = {
    'A': "01110 10001 10001 11111 10001 10001 10001", 'B': "11110 10001 10001 11110 10001 10001 11110",
    'C': "01110 10001 10000 10000 10000 10001 01110", 'D': "11100 10010 10001 10001 10001 10010 11100",
    'E': "11111 10000 10000 11110 10000 10000 11111", 'G': "01110 10001 10000 10111 10001 10001 01111",
    'H': "10001 10001 10001 11111 10001 10001 10001", 'I': "01110 00100 00100 00100 00100 00100 01110",
    'K': "10001 10010 10100 11000 10100 10010 10001", 'L': "10000 10000 10000 10000 10000 10000 11111",
    'M': "10001 11011 10101 10101 10001 10001 10001", 'N': "10001 10001 11001 10101 10011 10001 10001",
    'O': "01110 10001 10001 10001 10001 10001 01110", 'P': "11110 10001 10001 11110 10000 10000 10000",
    'R': "11110 10001 10001 11110 10100 10010 10001", 'S': "01111 10000 10000 01110 00001 00001 11110",
    'T': "11111 00100 00100 00100 00100 00100 00100", 'U': "10001 10001 10001 10001 10001 10001 01110",
    'V': "10001 10001 10001 10001 10001 01010 00100", 'W': "10001 10001 10001 10101 10101 10101 01010",
    'Y': "10001 10001 01010 00100 00100 00100 00100", 'Z': "11111 00001 00010 00100 01000 10000 11111",
    '/': "00001 00010 00010 00100 01000 01000 10000", '$': "00100 01111 10100 01110 00101 11110 00100",
    '%': "11000 11001 00010 00100 01000 10011 00011", '-': "00000 00000 00000 11111 00000 00000 00000",
    '!': "00100 00100 00100 00100 00100 00000 00100", ' ': "00000 00000 00000 00000 00000 00000 00000",
    '>': "10000 01000 00100 00010 00100 01000 10000", '(': "00010 00100 01000 01000 01000 00100 00010",
    ')': "01000 00100 00010 00010 00010 00100 01000",
}

img = Image.new('P', (W, H), BG)
d = ImageDraw.Draw(img)


def px(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        img.putpixel((x, y), c)


def text(s, x, y, c, scale=1, shadow=None, outline=None):
    """5x7 letters, `scale` pixels per dot, 1 dot apart; returns the width."""
    def draw(ox, oy, col):
        cx = ox
        for ch in s:
            rows = FONT[ch].split()
            for r, bits in enumerate(rows):
                for b, bit in enumerate(bits):
                    if bit == '1':
                        d.rectangle([cx + b * scale, oy + r * scale,
                                     cx + b * scale + scale - 1, oy + r * scale + scale - 1], fill=col)
            cx += 6 * scale
    if outline is not None:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                draw(x + dx, y + dy, outline)
    if shadow is not None:
        draw(x + max(1, scale // 2), y + max(1, scale // 2), shadow)
    draw(x, y, c)
    return 6 * scale * len(s) - scale


def text_w(s, scale=1):
    return 6 * scale * len(s) - scale


def ctext(s, cx, y, c, scale=1, **kw):
    text(s, cx - text_w(s, scale) // 2, y, c, scale, **kw)


def ellipse(box, fill, outline=K):
    x0, y0, x1, y1 = box
    d.ellipse([x0 - 1, y0 - 1, x1 + 1, y1 + 1], fill=outline)
    d.ellipse(box, fill=fill)


def poly(pts, fill, outline=K):
    d.polygon(pts, fill=fill, outline=outline)


# ------------------------------------------------------------------ background
for x in range(0, W, 16):
    d.line([x, 44, x, 112], fill=GRID)
for y in range(48, 113, 16):
    d.line([0, y, W - 1, y], fill=GRID)
# a rising market behind the bull, a falling one behind the bear
rise = [(0, 108), (14, 100), (24, 104), (40, 88), (52, 94), (70, 74), (84, 80), (104, 58)]
fall = [(216, 58), (232, 66), (244, 60), (262, 80), (274, 74), (292, 96), (304, 90), (319, 108)]
d.line(rise, fill=DGRN, width=2)
d.line(fall, fill=DRED, width=2)

# ------------------------------------------------------------------ title
ctext("SCAM STOCK", W // 2, 4, YEL, 3, shadow=ORA, outline=K)
ctext("TRADING SIMULATOR", W // 2, 30, WHITE, 2, outline=K)


# ------------------------------------------------------------------ the bull (left) and the bear (right)
def bull(ox, oy):
    # horns
    poly([(ox + 14, oy + 16), (ox + 3, oy + 14), (ox - 2, oy + 2), (ox + 4, oy + 7), (ox + 15, oy + 9)], CREAM)
    poly([(ox + 42, oy + 16), (ox + 53, oy + 14), (ox + 58, oy + 2), (ox + 52, oy + 7), (ox + 41, oy + 9)], CREAM)
    # ears
    ellipse((ox + 4, oy + 18, ox + 15, oy + 25), DGRN)
    ellipse((ox + 41, oy + 18, ox + 52, oy + 25), DGRN)
    # head
    ellipse((ox + 12, oy + 8, ox + 44, oy + 52), GRN)
    d.ellipse((ox + 17, oy + 12, ox + 39, oy + 22), fill=GRN)
    # angry brows and eyes
    d.line([(ox + 16, oy + 22), (ox + 25, oy + 26)], fill=K, width=2)
    d.line([(ox + 40, oy + 22), (ox + 31, oy + 26)], fill=K, width=2)
    d.rectangle([ox + 19, oy + 27, ox + 24, oy + 30], fill=RED)
    d.rectangle([ox + 32, oy + 27, ox + 37, oy + 30], fill=RED)
    px(ox + 21, oy + 28, WHITE); px(ox + 34, oy + 28, WHITE)
    # muzzle, nostrils, ring
    ellipse((ox + 16, oy + 36, ox + 40, oy + 52), CREAM)
    d.ellipse((ox + 21, oy + 41, ox + 25, oy + 45), fill=K)
    d.ellipse((ox + 31, oy + 41, ox + 35, oy + 45), fill=K)
    d.ellipse((ox + 24, oy + 48, ox + 32, oy + 56), outline=YEL, width=2)


def bear(ox, oy):
    # ears
    ellipse((ox + 8, oy + 4, ox + 20, oy + 16), RED)
    ellipse((ox + 36, oy + 4, ox + 48, oy + 16), RED)
    d.ellipse((ox + 11, oy + 7, ox + 17, oy + 13), fill=DRED)
    d.ellipse((ox + 39, oy + 7, ox + 45, oy + 13), fill=DRED)
    # head
    ellipse((ox + 8, oy + 8, ox + 48, oy + 52), RED)
    # angry brows and eyes
    d.line([(ox + 15, oy + 21), (ox + 24, oy + 25)], fill=K, width=2)
    d.line([(ox + 41, oy + 21), (ox + 32, oy + 25)], fill=K, width=2)
    d.rectangle([ox + 18, oy + 26, ox + 23, oy + 29], fill=YEL)
    d.rectangle([ox + 33, oy + 26, ox + 38, oy + 29], fill=YEL)
    px(ox + 22, oy + 27, K); px(ox + 34, oy + 27, K)
    # snout, nose, roaring mouth with fangs
    ellipse((ox + 17, oy + 32, ox + 39, oy + 51), CREAM)
    ellipse((ox + 23, oy + 33, ox + 33, oy + 38), K)
    d.rectangle([ox + 22, oy + 42, ox + 34, oy + 48], fill=DRED, outline=K)
    poly([(ox + 23, oy + 42), (ox + 25, oy + 42), (ox + 24, oy + 45)], WHITE, WHITE)
    poly([(ox + 31, oy + 42), (ox + 33, oy + 42), (ox + 32, oy + 45)], WHITE, WHITE)


bull(30, 44)
bear(234, 44)
ctext("BULL", 58, 100, GRN, 1, outline=K)
ctext("BEAR", 262, 100, RED, 1, outline=K)

# VS with a lightning bolt behind it
poly([(166, 46), (148, 76), (160, 76), (150, 106), (176, 70), (163, 70), (174, 46)], ORA, ORA)
for dx in (-2, -1, 0, 1, 2):                                          # a thick dark red edge
    for dy in (-2, -1, 0, 1, 2):
        ctext("VS", W // 2 + dx, 62 + dy, DRED, 4)
ctext("VS", W // 2, 62, YEL, 4)

# ------------------------------------------------------------------ the five bots
SLOT = 64
BOT_Y = 118                          # top of a bot's head


def robot(cx, y, eyes='open', antenna=True, body=GREY):
    """A small robot, head 14 x 10 centred on cx, body below; returns the body box."""
    if antenna:
        d.line([cx, y - 4, cx, y - 1], fill=K)
        px(cx, y - 5, RED)
    d.rectangle([cx - 7, y, cx + 7, y + 10], fill=body, outline=K)
    if eyes == 'open':
        d.rectangle([cx - 4, y + 3, cx - 2, y + 5], fill=CYAN)
        d.rectangle([cx + 2, y + 3, cx + 4, y + 5], fill=CYAN)
    elif eyes == 'closed':
        d.line([cx - 5, y + 5, cx - 2, y + 5], fill=K)
        d.line([cx + 2, y + 5, cx + 5, y + 5], fill=K)
    elif eyes == 'glasses':
        d.rectangle([cx - 6, y + 2, cx - 1, y + 6], fill=CYAN, outline=K)
        d.rectangle([cx + 1, y + 2, cx + 6, y + 6], fill=CYAN, outline=K)
        px(cx - 3, y + 4, K); px(cx + 3, y + 4, K)
    elif eyes == 'focused':
        d.rectangle([cx - 4, y + 4, cx - 2, y + 5], fill=CYAN)
        d.rectangle([cx + 2, y + 4, cx + 4, y + 5], fill=CYAN)
        d.line([cx - 5, y + 2, cx - 2, y + 3], fill=K)
        d.line([cx + 5, y + 2, cx + 2, y + 3], fill=K)
    d.line([cx - 2, y + 8, cx + 2, y + 8], fill=K)                 # mouth
    d.rectangle([cx - 6, y + 12, cx + 6, y + 22], fill=WHITE, outline=K)
    d.rectangle([cx - 3, y + 15, cx + 3, y + 18], fill=PANEL)       # chest panel
    return (cx - 6, y + 12, cx + 6, y + 22)


def legs(cx, y, run=False):
    if run:
        d.line([cx - 3, y + 23, cx - 7, y + 27], fill=K, width=2)
        d.line([cx + 3, y + 23, cx + 6, y + 28], fill=K, width=2)
    else:
        d.rectangle([cx - 4, y + 23, cx - 2, y + 27], fill=K)
        d.rectangle([cx + 2, y + 23, cx + 4, y + 27], fill=K)


def arm(x0, y0, x1, y1):
    d.line([x0, y0, x1, y1], fill=K, width=2)


def name(s, slot, c):
    ctext(s, slot * SLOT + SLOT // 2, 151, c, 1, outline=K)


# 1  MA BOT: glasses, studying a board with the price and its smooth average
cx = 0 * SLOT + 22
robot(cx, BOT_Y, 'glasses')
legs(cx, BOT_Y)
arm(cx + 7, BOT_Y + 15, cx + 13, BOT_Y + 12)
d.rectangle([cx + 13, BOT_Y - 2, cx + 38, BOT_Y + 18], fill=BG, outline=GREY)
d.line([(cx + 15, BOT_Y + 14), (cx + 19, BOT_Y + 6), (cx + 22, BOT_Y + 12), (cx + 26, BOT_Y + 3),
        (cx + 30, BOT_Y + 10), (cx + 36, BOT_Y + 1)], fill=WHITE)
d.line([(cx + 15, BOT_Y + 12), (cx + 22, BOT_Y + 10), (cx + 29, BOT_Y + 7), (cx + 36, BOT_Y + 4)], fill=YEL)
name("MA BOT", 0, WHITE)

# 2  OVERNIGHT: asleep in a nightcap under the moon, Zz
cx = 1 * SLOT + 26
robot(cx, BOT_Y, 'closed', antenna=False)
legs(cx, BOT_Y)
poly([(cx - 8, BOT_Y), (cx + 8, BOT_Y), (cx + 12, BOT_Y - 9)], PANEL)
d.ellipse((cx + 11, BOT_Y - 12, cx + 15, BOT_Y - 8), fill=WHITE)
text("Z", cx + 14, BOT_Y + 2, WHITE, 1)
text("Z", cx + 20, BOT_Y - 6, WHITE, 1)
d.ellipse((cx - 22, BOT_Y - 8, cx - 12, BOT_Y + 2), fill=YEL)            # moon
d.ellipse((cx - 19, BOT_Y - 10, cx - 9, BOT_Y), fill=BG)
name("OVERNIGHT", 1, CYAN)

# 3  MOMENTUM: running on rocket boots, speed lines, a green up arrow
cx = 2 * SLOT + 34
robot(cx, BOT_Y, 'focused')
legs(cx, BOT_Y, run=True)
for i, ly in enumerate((BOT_Y + 3, BOT_Y + 9, BOT_Y + 15, BOT_Y + 21)):
    d.line([cx - 26 + 2 * i, ly, cx - 11, ly], fill=GREY)
d.polygon([(cx - 9, BOT_Y + 28), (cx - 5, BOT_Y + 28), (cx - 7, BOT_Y + 32)], fill=ORA)
d.polygon([(cx + 4, BOT_Y + 29), (cx + 8, BOT_Y + 29), (cx + 6, BOT_Y + 33)], fill=YEL)
poly([(cx + 16, BOT_Y + 2), (cx + 22, BOT_Y - 6), (cx + 28, BOT_Y + 2), (cx + 24, BOT_Y + 2),
      (cx + 24, BOT_Y + 10), (cx + 20, BOT_Y + 10), (cx + 20, BOT_Y + 2)], GRN)
name("MOMENTUM", 2, GRN)

# 4  AVG DOWN: a shopping basket, red stairs going down (buying the dip)
cx = 3 * SLOT + 22
robot(cx, BOT_Y)
legs(cx, BOT_Y)
arm(cx + 7, BOT_Y + 15, cx + 11, BOT_Y + 19)
d.rectangle([cx + 9, BOT_Y + 18, cx + 19, BOT_Y + 25], fill=ORA, outline=K)
d.arc([cx + 10, BOT_Y + 12, cx + 18, BOT_Y + 24], 180, 360, fill=K)
for i in range(4):                                                     # stairs down
    d.rectangle([cx + 22 + 5 * i, BOT_Y - 2 + 6 * i, cx + 27 + 5 * i, BOT_Y + 3 + 6 * i], fill=RED)
d.polygon([(cx + 36, BOT_Y + 22), (cx + 42, BOT_Y + 22), (cx + 39, BOT_Y + 27)], fill=RED)
name("AVG DOWN", 3, ORA)

# 5  SL / TP: a red stop-loss shield and a green take-profit target
cx = 4 * SLOT + 32
robot(cx, BOT_Y)
legs(cx, BOT_Y)
arm(cx - 7, BOT_Y + 15, cx - 12, BOT_Y + 14)
arm(cx + 7, BOT_Y + 15, cx + 12, BOT_Y + 14)
poly([(cx - 22, BOT_Y + 6), (cx - 12, BOT_Y + 6), (cx - 12, BOT_Y + 16), (cx - 17, BOT_Y + 21),
      (cx - 22, BOT_Y + 16)], RED)
d.line([cx - 20, BOT_Y + 12, cx - 14, BOT_Y + 12], fill=WHITE)
for r, c in ((6, GRN), (4, WHITE), (2, GRN)):
    d.ellipse((cx + 17 - r, BOT_Y + 13 - r, cx + 17 + r, BOT_Y + 13 + r), fill=c, outline=K if r == 6 else c)
px(cx + 17, BOT_Y + 13, WHITE)
name("SL / TP", 4, WHITE)

# ------------------------------------------------------------------ PRESS START
d.rectangle([78, 160, 241, 178], fill=BTN, outline=YEL)
d.rectangle([79, 161, 240, 177], outline=ORA)
ctext("PRESS START", W // 2, 163, BLINK, 2)
text(">", 84, 166, BLINK, 1)
text(">", 232, 166, BLINK, 1)

# ------------------------------------------------------------------ out
pix = list(img.get_flattened_data()) if hasattr(img, 'get_flattened_data') else list(img.getdata())
assert max(pix) < 16
with open(os.path.join(HERE, '..', 'title_screen.mem'), 'w') as f:
    for p in pix:
        f.write('%x\n' % p)
rgb = Image.new('RGB', (W, H))
rgb.putdata([((PALETTE[p] >> 8) * 17, ((PALETTE[p] >> 4) & 15) * 17, (PALETTE[p] & 15) * 17) for p in pix])
rgb.resize((W * 4, H * 4), Image.NEAREST).save(os.path.join(HERE, 'title_screen_preview.png'))
print('title_screen.mem: %d pixels' % len(pix))
