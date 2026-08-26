"""Preprocesare audio -> log-mel spectrogram (amprenta acustică)."""
import numpy as np
import librosa

SR = 16000
N_MELS = 64
N_FFT = 1024
HOP = 512
CLIP_FRAMES = 64
FMAX = 8000

def load_audio(path: str) -> np.ndarray:
    y, _ = librosa.load(path, sr=SR, mono=True)
    return y

def log_mel(y: np.ndarray) -> np.ndarray:
    mel = librosa.feature.melspectrogram(
        y=y, sr=SR, n_fft=N_FFT, hop_length=HOP, n_mels=N_MELS, fmax=FMAX)
    db = librosa.power_to_db(mel, ref=np.max)
    return (db - db.mean()) / (db.std() + 1e-6)

def extract_frames(mel: np.ndarray, step: int = CLIP_FRAMES // 2) -> np.ndarray:
    if mel.shape[1] < CLIP_FRAMES:
        pad = CLIP_FRAMES - mel.shape[1]
        mel = np.pad(mel, ((0, 0), (0, pad)), mode="edge")
    frames = [mel[:, s:s + CLIP_FRAMES]
              for s in range(0, mel.shape[1] - CLIP_FRAMES + 1, step)]
    return np.array(frames)

def to_model_input(frames: np.ndarray) -> np.ndarray:
    return np.transpose(frames, (0, 2, 1))[:, :, :, None]
