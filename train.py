"""Antrenează autoencoder-ul pe sunete SĂNĂTOASE + export TFLite pentru mobil."""
import argparse, glob, os
import numpy as np
import tensorflow as tf
from tensorflow import keras

from src.preprocess import log_mel, extract_frames, to_model_input, load_audio
from src.model import build_autoencoder, frame_errors
from src import synth

def clips_from(folder):
    X = []
    for p in sorted(glob.glob(os.path.join(folder, "*.wav"))):
        X.append(to_model_input(extract_frames(log_mel(load_audio(p)))))
    return np.concatenate(X) if X else None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", choices=["synth", "dir"], default="synth")
    ap.add_argument("--path", default="data/wav")
    ap.add_argument("--epochs", type=int, default=30)
    args = ap.parse_args()

    if args.data == "synth":
        synth.generate(args.path)

    X = clips_from(os.path.join(args.path, "healthy"))
    rng = np.random.default_rng(0)
    idx = rng.permutation(len(X))
    n_val = max(64, len(X) // 10)
    Xval, Xtr = X[idx[:n_val]], X[idx[n_val:]]

    model = build_autoencoder()
    model.compile(optimizer=keras.optimizers.Adam(1e-3), loss="mse")
    model.fit(Xtr, Xtr, epochs=args.epochs, batch_size=64, verbose=0)
    print("✅ Antrenare finalizată.")

    errs = frame_errors(model, Xval)
    mu, sigma = float(errs.mean()), float(errs.std()) + 1e-6

    os.makedirs("models", exist_ok=True)
    model.save("models/autoencoder.keras")
    np.savez("models/baseline.npz", mu=mu, sigma=sigma)
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    open("models/autoencoder.tflite", "wb").write(conv.convert())

    Xf = clips_from(os.path.join(args.path, "faulty"))
    if Xf is not None:
        print(f"eroare normal ≈ {mu:.4f} | anomal ≈ {frame_errors(model, Xf).mean():.4f}")
    print("✅ Model salvat în models/ (keras + tflite)")

if __name__ == "__main__":
    main()
