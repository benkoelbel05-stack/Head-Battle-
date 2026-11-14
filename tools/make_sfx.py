# Synthetisiert die Knet-Soundeffekte für Clay Battle (weich, rund, verspielt).
import numpy as np, subprocess, os
from scipy.signal import butter, sosfilt
SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)

def t(d): return np.arange(int(SR*d))/SR
def env(n, a=0.005, d=0.1, curve=4.0):
    x = np.arange(n)/SR
    att = np.clip(x/a, 0, 1) if a > 0 else np.ones(n)
    dec = np.exp(-curve * x / max(d, 1e-4))
    return att*dec
def sweep(f0, f1, d, shape="exp"):
    x = t(d)
    if shape == "exp":
        f = f0 * (f1/f0) ** (x/d)
    else:
        f = f0 + (f1-f0)*(x/d)
    return np.sin(2*np.pi*np.cumsum(f)/SR)
def noise(d): return rng.uniform(-1, 1, int(SR*d))
def lp(x, fc, order=2): return sosfilt(butter(order, fc, 'low', fs=SR, output='sos'), x)
def hp(x, fc, order=2): return sosfilt(butter(order, fc, 'high', fs=SR, output='sos'), x)
def bp(x, lo, hi, order=2): return sosfilt(butter(order, [lo, hi], 'band', fs=SR, output='sos'), x)
def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts: out[:len(p)] += p
    return out
def tone(freq, d, decay=0.3, harmonics=((1,1.0),)):
    x = t(d); s = sum(a*np.sin(2*np.pi*freq*h*x) for h, a in harmonics)
    return s*env(len(x), 0.003, decay)
def sweep_band(d, f0, f1, width=0.5):
    # Rauschen durch einen wandernden Bandpass (Whoosh), in Blöcken gefiltert
    n = int(SR*d); out = np.zeros(n); src = noise(d); block = 512
    for i in range(0, n, block):
        frac = i/n; fc = f0*(f1/f0)**frac
        seg = src[max(0,i-block):i+block]
        f = bp(seg, fc*(1-width/2), min(fc*(1+width/2), SR/2-100))
        out[i:i+block] = f[-min(block, n-i):] if i>0 else f[:min(block, n-i)]
    return out
def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    fade = int(SR*0.004); x[-fade:] *= np.linspace(1, 0, fade)
    wav = f"{OUT}/{name}.wav"
    import scipy.io.wavfile as w
    w.write(wav, SR, (x*32767).astype(np.int16))
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",wav,"-c:a","libvorbis","-q:a","6",f"{OUT}/{name}.ogg"], check=True)
    os.remove(wav)

# Menü
save("ui_click", mix(sweep(700, 280, 0.09)*env(int(SR*0.09),0.002,0.05), lp(noise(0.03),3000)*env(int(SR*0.03),0.001,0.01)*0.3), 0.7)
save("ui_hover", tone(1500, 0.05, 0.02, ((1,1),(2,0.3))), 0.35)
# Bewegung
d=0.18; save("jump", sweep(240, 560, d)*env(int(SR*d),0.004,0.12)*(1+0.15*np.sin(2*np.pi*30*t(d))), 0.6)
d=0.16; save("double_jump", mix(sweep(420, 980, d)*env(int(SR*d),0.003,0.1), tone(2400,0.12,0.05)*0.25), 0.6)
d=0.14; save("land", mix(sweep(140, 55, d)*env(int(SR*d),0.002,0.07), lp(noise(d),900)*env(int(SR*d),0.001,0.04)*0.6), 0.7)
d=0.28; save("dash", sweep_band(d, 500, 3000, 0.6)*env(int(SR*d),0.03,0.18), 0.6)
# Fähigkeiten
d=0.4; save("thruster", mix(sweep(180, 90, 0.08)*env(int(SR*0.08),0.001,0.05), lp(noise(d),1800)*env(int(SR*d),0.02,0.3)*0.6), 0.7)
d=0.22; save("grenade_throw", sweep_band(d, 900, 2600, 0.5)*env(int(SR*d),0.01,0.14), 0.55)
d=1.1; save("explosion", mix(lp(noise(d),700,4)*env(int(SR*d),0.002,0.5), sweep(90, 35, d)*env(int(SR*d),0.002,0.45)*0.9, hp(noise(0.15),2500)*env(int(SR*0.15),0.001,0.05)*0.3), 0.95)
d=0.2; save("sword", mix(sweep_band(d, 2000, 6000, 0.4)*env(int(SR*d),0.005,0.1), tone(2600,0.35,0.2,((1,1),(2.76,0.4)))*0.18), 0.6)
d=0.5; save("missile_launch", mix(sweep_band(d, 400, 1600, 0.7)*env(int(SR*d),0.02,0.35), sweep(200, 420, d)*env(int(SR*d),0.01,0.3)*0.25), 0.65)
d=0.32; save("eliminate", mix(lp(noise(d),1400)*env(int(SR*d),0.002,0.12), sweep(500, 90, d)*env(int(SR*d),0.002,0.2)*0.7), 0.8)
d=0.13; save("respawn_pop", sweep(300, 950, d)*env(int(SR*d),0.002,0.07), 0.55)
# Runden
save("countdown_tick", tone(660, 0.3, 0.12, ((1,1),(2,0.35),(3,0.12))), 0.6)
d=0.7; save("countdown_go", mix(*(tone(f, d, 0.35, ((1,1),(2,0.3))) for f in (523.25, 659.25, 783.99, 1046.5))), 0.7)
save("map_tick", mix(tone(1100, 0.05, 0.015), lp(noise(0.02),4000)*env(int(SR*0.02),0.001,0.006)*0.3), 0.4)
notes=[(783.99,0.0),(1046.5,0.09),(1318.5,0.18)]
x=np.zeros(int(SR*0.6))
for f, start in notes:
    s=tone(f,0.4,0.18,((1,1),(2,0.25))); i=int(SR*start); x[i:i+len(s)]+=s[:len(x)-i]
save("map_select", x, 0.6)
notes=[(523.25,0.0),(659.25,0.12),(783.99,0.24),(1046.5,0.36)]
x=np.zeros(int(SR*1.3))
for f, start in notes:
    s=tone(f,0.9 if f>1000 else 0.4,0.5 if f>1000 else 0.18,((1,1),(2,0.3),(3,0.1))); i=int(SR*start); x[i:i+len(s)]+=s[:len(x)-i]
save("round_win", x, 0.75)
print(sorted(os.listdir(OUT)))
