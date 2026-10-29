"""Synthesises the game's sound effects (own creation, no samples, no licence questions).
Usage: python3 -I make_sounds.py <out_dir>"""
import math, os, random, struct, sys, wave

RATE = 44100
out = sys.argv[1]; os.makedirs(out, exist_ok=True)

def write(name, samples, peak=0.6):
    m = max(1e-9, max(abs(s) for s in samples))
    data = b''.join(struct.pack('<h', int(max(-1, min(1, s / m * peak)) * 32767)) for s in samples)
    with wave.open(os.path.join(out, name), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data)

def tone(freq, dur, decay, harm=(1.0, 0.35, 0.12), attack=0.004):
    n = int(dur * RATE); res = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-decay * t)
        res.append(env * sum(a * math.sin(2 * math.pi * freq * (k + 1) * t) for k, a in enumerate(harm)))
    return res

def mix(parts, total):
    res = [0.0] * int(total * RATE)
    for start, s in parts:
        o = int(start * RATE)
        for i, v in enumerate(s):
            if o + i < len(res): res[o + i] += v
    return res

# coin: a quick two-note "ding"
write('coin.wav', mix([(0.0, tone(988, 0.09, 10)), (0.07, tone(1319, 0.45, 8))], 0.55))
# pickup: short rising pop
n = int(0.14 * RATE); sw = []
for i in range(n):
    t = i / RATE; f = 420 + 520 * (t / 0.14); sw.append(math.sin(2 * math.pi * f * t) * math.exp(-16 * t))
write('pickup.wav', sw, 0.5)
# place: soft low thud with a tiny click
random.seed(7); n = int(0.2 * RATE); th = []
for i in range(n):
    t = i / RATE; f = 170 - 80 * (t / 0.2)
    th.append(math.sin(2 * math.pi * f * t) * math.exp(-20 * t) + (random.random() - 0.5) * 0.25 * math.exp(-90 * t))
write('place.wav', th, 0.6)
# level up: rising arpeggio
notes = [523.25, 659.25, 783.99, 1046.5]
write('levelup.wav', mix([(0.11 * i, tone(f, 0.7 if i == 3 else 0.3, 5 if i == 3 else 9)) for i, f in enumerate(notes)], 1.2), 0.6)
# tap: short click for buttons
write('tap.wav', tone(720, 0.06, 40, (1.0, 0.2)), 0.4)
# arrive: two soft notes, a customer came in
write('arrive.wav', mix([(0.0, tone(659.25, 0.25, 9)), (0.14, tone(880, 0.4, 7))], 0.6), 0.45)
# star: a bright ping for a star on the day's rating (the game raises the pitch for each star)
write('star.wav', mix([(0.0, tone(1318.5, 0.55, 7, (1.0, 0.4, 0.15)))], 0.55), 0.5)
# close: three soft descending notes, the shop closes for the day
write('close.wav', mix([(0.0, tone(783.99, 0.6, 5)), (0.28, tone(659.25, 0.6, 5)), (0.56, tone(523.25, 1.0, 4))], 1.6), 0.5)
# deny: two short low blips, a tap that cannot be done
write('deny.wav', mix([(0.0, tone(233, 0.09, 28, (1.0, 0.3))), (0.1, tone(196, 0.14, 22, (1.0, 0.3)))], 0.3), 0.45)
print('ok', sorted(os.listdir(out)))
