# Memo game sounds v2 (incremental-game style, after Balatro / idle games):
# one short, soft "pop-clack" per level that climbs a plain major scale, low register.
import numpy as np, wave, sys, os
SR = 44100
out = sys.argv[1]
rng = np.random.default_rng(7)

def write(name, sig, peak):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * peak
    fade = int(0.012 * SR); sig[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(out, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((sig * 32767).astype(np.int16).tobytes())

def pop(f, dur=0.2):
    n = int(SR * dur); t = np.arange(n) / SR
    # Pitch blips up into the note (the "pop"), body decays fast (the "clack").
    fe = f * (1 + 0.5 * np.exp(-t / 0.006))
    ph = 2 * np.pi * np.cumsum(fe) / SR
    amp = np.minimum(t / 0.002, 1) * np.exp(-t / 0.055)
    body = np.sin(ph) + 0.35 * np.sin(2 * ph) * np.exp(-t / 0.02)
    # A tiny woody FM partial for the chip "clack".
    wood = np.sin(2 * np.pi * f * 2.76 * t + 1.5 * np.sin(2 * np.pi * f * 5.4 * t)) * np.exp(-t / 0.012) * 0.25
    # Short filtered-noise tick on the attack.
    noise = rng.standard_normal(n) * np.exp(-t / 0.0025) * 0.35
    noise = np.convolve(noise, np.ones(6) / 6, mode='same')
    return (body + wood) * amp + noise

# C major scale from C4, one step per level.
scale = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16]
for i, s in enumerate(scale):
    write(f'level-up-{i+1}', pop(261.63 * 2 ** (s / 12)), peak=0.42)

# Finish: three soft pops climbing a chord, then a gentle low bell. Short.
buf = np.zeros(int(SR * 0.9))
for k, s in enumerate([0, 4, 7, 12]):
    p = pop(261.63 * 2 ** (s / 12), 0.25) * (0.8 + 0.07 * k)
    i = int(k * 0.07 * SR); buf[i:i + len(p)] += p
t = np.arange(int(SR * 0.6)) / SR
bell = np.sin(2 * np.pi * 523.25 * t) * np.exp(-t / 0.22) * 0.35
i = int(0.21 * SR); buf[i:i + len(bell)] += bell
write('game-complete', buf, peak=0.45)

# Wrong: low muted thud, quick pitch drop.
n = int(SR * 0.16); t = np.arange(n) / SR
f = 150 * np.exp(-t * 3)
ph = 2 * np.pi * np.cumsum(f) / SR
write('wrong-soft', np.sin(ph) * np.minimum(t / 0.003, 1) * np.exp(-t / 0.045), peak=0.4)
print('ok')
