"""Antrenează autoencoder-ul pe sunete SĂNĂTOASE + export TFLite cu TF Select Ops."""
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
        try:
            X.append(to_model_input(extract_frames(log_mel(load_audio(p)))))
        except Exception as e:
            print(f"⚠️ Skip {p}: {e}")
    return np.concatenate(X) if X else None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", choices=["synth", "dir"], default="synth")
    ap.add_argument("--path", default="data/wav")
    ap.add_argument("--epochs", type=int, default=10) # Redus pentru viteză pe CI
    args = ap.parse_args()

    if args.data == "synth":
        synth.generate(args.path)

    X = clips_from(os.path.join(args.path, "healthy"))
    if X is None or len(X) == 0:
        raise ValueError("Nu s-au găsit clipuri sănătoase pentru antrenare!")
        
    rng = np.random.default_rng(0)
    idx = rng.permutation(len(X))
    n_val = max(64, len(X) // 10)
    Xval, Xtr = X[idx[:n_val]], X[idx[n_val:]]

    print(f"📊 Antrenare: {len(Xtr)} clipuri | Validare: {len(Xval)} clipuri")
    model = build_autoencoder()
    model.compile(optimizer=keras.optimizers.Adam(1e-3), loss="mse")
    model.fit(Xtr, Xtr, epochs=args.epochs, batch_size=64, verbose=1)
    print("✅ Antrenare finalizată.")

    errs = frame_errors(model, Xval)
    mu, sigma = float(errs.mean()), float(errs.std()) + 1e-6

    os.makedirs("models", exist_ok=True)
    model.save("models/autoencoder.keras")
    np.savez("models/baseline.npz", mu=mu, sigma=sigma)
    
    # ✅ FIX CRITIC: Activăm TF Select Ops pentru Conv2D în TensorFlow 2.17+
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS
    ]
    tflite_model = converter.convert()
    open("models/autoencoder.tflite", "wb").write(tflite_model)
    print("✅ Model TFLite exportat cu succes (cu SELECT_TF_OPS)")

    Xf = clips_from(os.path.join(args.path, "faulty"))
    if Xf is not None and len(Xf) > 0:
        err_faulty = frame_errors(model, Xf).mean()
        print(f"📈 Verificare: eroare normal ≈ {mu:.4f} | anomal ≈ {err_faulty:.4f}")
    else:
        print("ℹ️ Nu s-au găsit clipuri defecte pentru verificare.")
        
    print("🎉 Build complet! Fișiere salvate în models/")

if __name__ == "__main__":
    main()
