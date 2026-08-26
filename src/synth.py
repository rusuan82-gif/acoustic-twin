"""Date sintetice pentru demo (ventilator sănătos, rulment uzat, HDD)."""
import os
import numpy as np
import soundfile as sf
from .preprocess import SR

def _clip(rng, dur, fault):
    n = int(SR * dur)
    t = np.arange(n) / SR
    fund = rng.uniform(100, 140)
    sig = np.zeros(n)
    for h in range(1, 7):
        sig += np.sin(2 * np.pi * fund * h * t + rng.uniform(0, 2 * np.pi)) / h ** 1.4
    airflow = np.convolve(rng.standard_normal(n), np.ones(60) / 60, "same")
    sig += 0.7 * airflow
    sig *= 1 + 0.05 * np.sin(2 * np.pi * rng.uniform(0.5, 1.2) * t)
    if fault == "bearing":
        f = rng.uniform(2200, 3600)
        sig += 0.5 * np.sin(2 * np.pi * f * t + 2.5 * np.sin(2 * np.pi * rng.uniform(1.5, 3) * t))
    elif fault == "clicks":
        for _ in range(int(dur * rng.uniform(2, 5))):
            pos = rng.integers(0, n - 200)
            f = rng.uniform(1500, 3000)
            tc = np.arange(200) / SR
            sig[pos:pos + 200] += 1.2 * np.sin(2 * np.pi * f * tc) * np.exp(-tc * 900)
    sig /= np.max(np.abs(sig)) + 1e-9
    return (0.9 * sig).astype(np.float32)

def generate(base="data/wav", n_healthy=40, n_fault=10, dur=5.0, seed=7):
    rng = np.random.default_rng(seed)
    for sub in ("healthy", "faulty"):
        os.makedirs(os.path.join(base, sub), exist_ok=True)
    for i in range(n_healthy):
        sf.write(f"{base}/healthy/{i:03d}.wav", _clip(rng, dur, None), SR)
    for i in range(n_fault):
        kind = "bearing" if i % 2 == 0 else "clicks"
        sf.write(f"{base}/faulty/{i:03d}.wav", _clip(rng, dur, kind), SR)
    print(f"✅ {n_healthy} clipuri sănătoase + {n_fault} defecte în {base}/")
