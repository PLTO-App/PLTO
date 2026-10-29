"""Synthesises the game's music and ambience loops, and a few extra sound effects (own creation, no samples).
  music_day.ogg   a light, warm loop: electric piano chords, bass, a little mallet melody and brushed drums (about 42 s)
  amb_town.ogg    birds and a far-away street (20 s)        amb_shop.ogg  a soft room murmur with cups (20 s)
  bell.wav (shop door), register.wav (till), steam.wav (espresso machine), truck.wav (morning delivery), swish.wav (sheet)
Loops are rendered with their reverb tails wrapped to the start, so they repeat without a seam.
Usage: python3 -I make_music.py <out_dir>    (needs numpy and ffmpeg with libvorbis)"""
import os, sys, subprocess, wave
import numpy as np

SR = 44100
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)

def note_hz(n):  # MIDI note -> Hz
    return 440.0 * 2 ** ((n - 69) / 12.0)

def env_adsr(n, a, d, s, r, sr=SR):
    a = max(1, int(a * sr)); d = max(1, int(d * sr)); r = max(1, int(r * sr))
    e = np.ones(n) * s
    e[:min(a, n)] = np.linspace(0, 1, min(a, n))
    if a < n: e[a:min(a + d, n)] = np.linspace(1, s, min(a + d, n) - a)
    if n > r: e[-r:] *= np.linspace(1, 0, r)
    return e

def rhodes(f, dur, vel=1.0):
    n = int(dur * SR); t = np.arange(n) / SR
    idx = 1.6 * np.exp(-t * 5.0) + 0.25
    mod = np.sin(2 * np.pi * f * t) * idx
    car = np.sin(2 * np.pi * f * t + mod)
    tine = np.sin(2 * np.pi * f * 4.0 * t) * 0.18 * np.exp(-t * 14)
    trem = 1.0 + 0.06 * np.sin(2 * np.pi * 4.2 * t)
    return (car + tine) * np.exp(-t * 1.6) * env_adsr(n, 0.004, 0.1, 1.0, 0.08) * trem * vel

def mallet(f, dur, vel=1.0):
    n = int(dur * SR); t = np.arange(n) / SR
    w = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 4.0 * t) * np.exp(-t * 20) + 0.12 * np.sin(2 * np.pi * f * 10.0 * t) * np.exp(-t * 40)
    return w * np.exp(-t * 4.5) * env_adsr(n, 0.002, 0.05, 1.0, 0.05) * vel

def bass(f, dur, vel=1.0):
    n = int(dur * SR); t = np.arange(n) / SR
    w = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * 2 * f * t) + 0.08 * np.sin(2 * np.pi * 3 * f * t)
    return w * env_adsr(n, 0.01, 0.15, 0.7, 0.08) * vel

def kick(vel=1.0):
    n = int(0.35 * SR); t = np.arange(n) / SR
    f = 110 * np.exp(-t * 18) + 45
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * vel

def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR); y = np.zeros_like(x); s = 0.0
    for i in range(len(x)):
        s = (1 - a) * x[i] + a * s; y[i] = s
    return y

def brush(dur, vel=1.0, bright=4000):
    n = int(dur * SR); t = np.arange(n) / SR
    nz = rng.standard_normal(n)
    hp = nz - lowpass(nz, 900)
    return lowpass(hp, bright) * np.exp(-t * 18) * vel

def place(buf, start, sig, gain=1.0):
    i = int(start * SR)
    if i >= len(buf): return
    j = min(len(buf), i + len(sig)); buf[i:j] += sig[:j - i] * gain

def reverb(x, mix=0.22):
    out = np.copy(x)
    for d, g in [(1557, 0.78), (1617, 0.77), (1491, 0.79), (1422, 0.8)]:
        y = np.zeros(len(x) + d)
        y[:len(x)] = x
        for i in range(d, len(y)): y[i] += y[i - d] * g * 0.5
        out = out + y[:len(x)] * (mix / 4)
    return out

def wrap(sig, loop_len):
    """fold everything after loop_len back onto the start (seamless loop)"""
    n = int(loop_len * SR)
    out = sig[:n].copy()
    tail = sig[n:]
    out[:min(n, len(tail))] += tail[:min(n, len(tail))]
    return out

def norm(x, peak=0.8):
    return x / max(1e-9, np.max(np.abs(x))) * peak

def save_wav(name, x):
    x = np.clip(x, -1, 1)
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype('<i2').tobytes())

def save_ogg(name, x):
    tmp = os.path.join(OUT, '_tmp.wav'); save_wav('_tmp.wav', x)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '3', os.path.join(OUT, name)], check=True)
    os.remove(tmp)

# ------------------------------------------------------------------ music
BPM = 92; beat = 60.0 / BPM; bar = 4 * beat
# F major: Fmaj7, Dm7, Gm7, C7 | Fmaj7, Am7, Bbmaj7, C7 (two bars each)
chords = [(53, [57, 60, 64, 65]), (50, [57, 60, 62, 65]), (55, [58, 62, 65, 67]), (48, [58, 60, 64, 67]),
          (53, [57, 60, 64, 69]), (57, [60, 64, 67, 69]), (58, [62, 65, 69, 70]), (48, [55, 58, 60, 64])]
L = len(chords) * 2 * bar
buf = np.zeros(int((L + 4) * SR))
for ci, (root, voice) in enumerate(chords):
    for b in range(2):
        t0 = (ci * 2 + b) * bar
        # piano comping: 1, the "and" of 2, 4 (swung)
        for pos, v in [(0.0, 0.55), (1.5 + 0.08, 0.38), (3.0, 0.42)]:
            for k, nn in enumerate(voice):
                place(buf, t0 + pos * beat + k * 0.012, rhodes(note_hz(nn), 1.4, v * 0.32))
        # bass on 1 and 3, a walking note before the next chord
        place(buf, t0, bass(note_hz(root - 12), beat * 1.8, 0.55))
        nxt = chords[(ci + (1 if b == 1 else 0)) % len(chords)][0]
        place(buf, t0 + 2 * beat, bass(note_hz((root if b == 0 else nxt + 2) - 12), beat * 1.6, 0.45))
        # drums
        place(buf, t0, kick(0.5)); place(buf, t0 + 2 * beat, kick(0.42))
        place(buf, t0 + beat, brush(0.25, 0.16)); place(buf, t0 + 3 * beat, brush(0.25, 0.16))
        for k in range(8):
            sw = 0.09 if k % 2 else 0.0
            place(buf, t0 + (k * 0.5 + sw) * beat, brush(0.08, 0.05 if k % 2 else 0.07, 7000))
# a light melody on the mallet (F major pentatonic), sparse and repeating with a variation
motif = [(0, 72, 0.5), (0.5, 74, 0.5), (1, 77, 1.0), (2.5, 74, 0.5), (3, 72, 1.0)]
answer = [(0, 69, 0.5), (0.5, 72, 0.5), (1, 74, 1.5), (3, 77, 0.75), (3.5, 79, 0.5)]
for phrase in range(len(chords)):
    t0 = phrase * 2 * bar + bar
    m = motif if phrase % 2 == 0 else answer
    shift = 0 if phrase < 4 else (2 if phrase % 2 == 0 else 0)
    for pos, nn, ln in m:
        place(buf, t0 + pos * beat, mallet(note_hz(nn + shift), ln * beat + 0.4, 0.3))
music = wrap(reverb(buf, 0.3), L)
fade = int(0.01 * SR); music[:fade] *= np.linspace(0.6, 1, fade)
save_ogg('music_day.ogg', norm(music, 0.7))

# ------------------------------------------------------------------ town ambience: birds and a far street
LA = 20.0; amb = np.zeros(int((LA + 2) * SR))
street = lowpass(rng.standard_normal(len(amb)), 180) * 0.6
street *= 0.7 + 0.3 * np.sin(2 * np.pi * np.arange(len(amb)) / SR / 7.0)
amb += street
for i in range(26):
    t0 = rng.uniform(0, LA); f0 = rng.uniform(2600, 4200); n = int(rng.uniform(0.06, 0.16) * SR); t = np.arange(n) / SR
    for k in range(int(rng.integers(1, 4))):
        f = f0 * (1 + 0.25 * np.sin(2 * np.pi * rng.uniform(8, 18) * t)) * (1 + 0.3 * t / t[-1])
        chirp = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) * 0.18
        place(amb, t0 + k * 0.17, chirp)
for i in range(2):
    t0 = rng.uniform(1, LA - 4); n = int(4 * SR); t = np.arange(n) / SR
    car = lowpass(rng.standard_normal(n), 400) * np.sin(np.pi * t / 4) ** 2 * 1.4
    place(amb, t0, car)
save_ogg('amb_town.ogg', norm(wrap(amb, LA), 0.35))

# ------------------------------------------------------------------ shop ambience: murmur and cups
shop = np.zeros(int((LA + 2) * SR))
mur = rng.standard_normal(len(shop)); mur = lowpass(mur - lowpass(mur, 250), 1100)
am = lowpass(np.abs(rng.standard_normal(len(shop))), 3.0); am = am / np.max(am)
shop += mur * (0.4 + 0.8 * am)
for i in range(14):
    t0 = rng.uniform(0, LA); f = rng.uniform(2300, 3600); n = int(0.25 * SR); t = np.arange(n) / SR
    clink = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.7 * t)) * np.exp(-t * 28) * 0.25
    place(shop, t0, clink)
save_ogg('amb_shop.ogg', norm(wrap(shop, LA), 0.3))

# ------------------------------------------------------------------ extra effects
def bellsig(f, dur, decay):
    n = int(dur * SR); t = np.arange(n) / SR
    return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * decay * (1 + 0.4 * k)) for k, (r, a) in enumerate([(1, 1.0), (2.76, 0.5), (5.4, 0.25), (8.9, 0.12)]))
door = np.zeros(int(1.2 * SR)); place(door, 0.0, bellsig(1568, 1.0, 3.2) * 0.6); place(door, 0.12, bellsig(1318.5, 1.0, 3.2) * 0.5)
save_wav('bell.wav', norm(door, 0.55))
reg = np.zeros(int(0.9 * SR)); n = int(0.05 * SR)
place(reg, 0.0, rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 80) * 0.6)
place(reg, 0.06, rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 80) * 0.5)
place(reg, 0.14, bellsig(2093, 0.7, 4.0) * 0.7)
save_wav('register.wav', norm(reg, 0.6))
n = int(1.2 * SR); t = np.arange(n) / SR
st = rng.standard_normal(n); st = st - lowpass(st, 2500)
st *= np.minimum(1, t / 0.15) * np.exp(-np.maximum(0, t - 0.6) * 5) * (0.8 + 0.2 * np.sin(2 * np.pi * 9 * t))
save_wav('steam.wav', norm(st, 0.4))
n = int(1.6 * SR); t = np.arange(n) / SR
eng = (np.sin(2 * np.pi * 52 * t) + 0.5 * np.sin(2 * np.pi * 104 * t) + 0.3 * lowpass(rng.standard_normal(n), 300)) * np.sin(np.pi * t / t[-1])
place(eng, 1.05, (np.sin(2 * np.pi * 900 * t[:int(0.12 * SR)]) * 0.4))
save_wav('truck.wav', norm(eng, 0.45))
n = int(0.25 * SR); t = np.arange(n) / SR
sw = rng.standard_normal(n); sw = lowpass(sw - lowpass(sw, 600), 5000) * np.sin(np.pi * t / t[-1]) ** 2
save_wav('swish.wav', norm(sw, 0.25))
print('ok', sorted(os.listdir(OUT)))
