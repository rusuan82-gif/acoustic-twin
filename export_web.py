"""Exportă modelul + baseline-ul într-un weights.js pentru pagina HTML."""
import json
import numpy as np
from tensorflow import keras

model = keras.models.load_model("models/autoencoder.keras")
d = np.load("models/baseline.npz")
w = []
for l in model.layers:
    if "conv2d" in l.name and l.weights:
        k, b = l.weights
        w.append([k.numpy().tolist(), b.numpy().tolist()])
js = "window.AT_MODEL=" + json.dumps(
    {"mu": float(d["mu"]), "sigma": float(d["sigma"]), "w": w}) + ";"
open("weights.js", "w").write(js)
print("✅ weights.js generat")
