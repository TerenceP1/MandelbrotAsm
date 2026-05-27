#CHATGPT BUT PELLETES ARE HUMAN

import cv2
import numpy as np

usecolors = [
    (0, 0, 0),
    (0, 255, 153),
    (0, 204, 255),
    (153, 0, 255),
    (255, 0, 153),
    (0, 0, 0)
]

TOTAL_STEPS = 256

# --- float palette ---
palette = [np.array(c, dtype=np.float32) for c in usecolors]
n = len(palette)

gradient = []

# --- generate smooth gradient ---
for i in range(TOTAL_STEPS):
    t = i / (TOTAL_STEPS - 1)

    pos = t * (n - 1)
    i0 = int(pos)
    i1 = min(i0 + 1, n - 1)

    local_t = pos - i0

    c1 = palette[i0]
    c2 = palette[i1]

    rgb = c1 * (1 - local_t) + c2 * local_t
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)

    gradient.append(rgb)

# --- flatten to raw byte array ---
data = np.array(gradient, dtype=np.uint8).flatten()

# --- save binary file ---
with open("neon-p.dat", "wb") as f:
    f.write(data.tobytes())

print("Saved neon-p.dat (", len(data), "bytes )")