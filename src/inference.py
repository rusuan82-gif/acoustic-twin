"""Scor de sănătate + verdict din sunet."""
import numpy as np
import librosa
from tensorflow import keras
from .preprocess import SR, HOP, N_MELS, FMAX, log_mel, extract_frames, to_model_input
from .model import frame_errors

class AcousticScorer:
    def __init__(self, model_path="models/autoencoder.keras",
                 stats_path="models/baseline.npz"):
        self.model = keras.models.load_model(model_path)
        s = np.load(stats_path)
        self.mu, self.sigma = float(s["mu"]), float(s["sigma"])
        self.hz = librosa.mel_frequencies(n_mels=N_MELS, fmax=FMAX)

    def score(self, y):
        mel = log_mel(y)
        X = to_model_input(extract_frames(mel))
        err = frame_errors(self.model, X).mean()
        z = (err - self.mu) / self.sigma
        health = int(np.clip(100 - z * (100 / 6), 0, 100))
        verdict = self._diagnose(mel) if health < 85 else "Semnătură acustică normală."
        return health, verdict, mel

    def _diagnose(self, mel):
        flux = np.sum(np.maximum(0, np.diff(mel, axis=1)), axis=0)
        fps = SR / HOP
        clicks_ps = np.sum(flux > 6 * np.median(flux)) / (flux.size / fps)
        band = (self.hz > 1500) & (self.hz < 6000)
        spec = np.exp(mel).mean(axis=1)
        tonal = spec[band].max() / (spec[band].mean() + 1e-9)
        if clicks_ps > 1.5:
            return f"Click-uri anormale ({clicks_ps:.1f}/s) → posibil HDD / mecanism."
        if tonal > 8:
            return "Șuierat tonal în banda înaltă → rulment / ventilator cu uzură."
        return "Semnătură anormală nespecificată → inspectează echipamentul."
