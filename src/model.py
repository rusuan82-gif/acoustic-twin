"""Autoencoder convoluțional — antrenat DOAR pe sunete sănătoase."""
import numpy as np
from tensorflow import keras
from tensorflow.keras import layers
from .preprocess import N_MELS, CLIP_FRAMES

def build_autoencoder():
    inp = keras.Input(shape=(CLIP_FRAMES, N_MELS, 1))
    x = layers.Conv2D(32, 3, padding="same", activation="relu")(inp)
    x = layers.MaxPooling2D(2)(x)
    x = layers.Conv2D(16, 3, padding="same", activation="relu")(x)
    x = layers.MaxPooling2D(2)(x)
    x = layers.Conv2D(8, 3, padding="same", activation="relu")(x)
    x = layers.UpSampling2D(2)(x)
    x = layers.Conv2D(16, 3, padding="same", activation="relu")(x)
    x = layers.UpSampling2D(2)(x)
    out = layers.Conv2D(1, 3, padding="same")(x)
    return keras.Model(inp, out)

def frame_errors(model, X):
    pred = model.predict(X, verbose=0)
    return np.mean((pred - X) ** 2, axis=(1, 2, 3))
