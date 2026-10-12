# Tileable fabric normal maps (OpenGL convention, +Y up) generated from height fields.
import numpy as np, sys
from PIL import Image
N = 256
out = sys.argv[1]
y, x = np.mgrid[0:N, 0:N] / N * 2 * np.pi
rng = np.random.default_rng(7)

def tile_noise(scale, octaves=3):
    h = np.zeros((N, N))
    for o in range(octaves):
        f = scale * 2 ** o
        F = np.fft.fft2(rng.normal(size=(N, N)))
        ky, kx = np.meshgrid(np.fft.fftfreq(N) * N, np.fft.fftfreq(N) * N, indexing="ij")
        k = np.sqrt(kx ** 2 + ky ** 2)
        F *= np.exp(-((k - f) ** 2) / (2 * (f * 0.5) ** 2))
        h += np.real(np.fft.ifft2(F)) / 2 ** o
    return (h - h.mean()) / (h.std() + 1e-9)

def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8), "RGB")

# wool serge: 2/2 twill diagonals, 16 yarns per tile, soft fibres
k = 16
twill = np.sin((x + y) * k / 2) * 0.6 + np.sin(x * k) * np.sin(y * k) * 0.25
h = twill + tile_noise(40) * 0.15
normal_map(h, 1.2).save(f"{out}/weave_wool_twill_n.png")

# cotton plain weave: alternating over/under
k = 24
plain = np.sin(x * k) * np.sign(np.sin(y * k / 2)) * 0.5 + np.sin(y * k) * np.sign(np.sin(x * k / 2)) * 0.5
h = plain + tile_noise(60) * 0.12
normal_map(h, 1.0).save(f"{out}/weave_cotton_plain_n.png")

# leather grain: cellular-ish noise, low frequency pores
h = -np.abs(tile_noise(18, 2)) + tile_noise(70, 1) * 0.15
normal_map(h, 1.4).save(f"{out}/grain_leather_n.png")
print("ok")
