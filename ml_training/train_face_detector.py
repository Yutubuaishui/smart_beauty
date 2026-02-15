"""
Template: train a small CNN for face detection and export to TFLite.
Uses a synthetic dataset for demonstration; replace with real data (e.g. WIDER FACE).

Run: pip install tensorflow
     python train_face_detector.py

For real training:
  - Use WIDER FACE or CelebA (face bounding boxes).
  - Replace load_data() with your loader that returns (images, boxes).
  - boxes: shape (N, 4) with (ymin, xmin, ymax, xmax) normalized 0-1.
"""

import os
import sys

try:
    import tensorflow as tf
    import numpy as np
except ImportError:
    print("Install: pip install tensorflow numpy")
    sys.exit(1)

INPUT_SIZE = 192
BATCH_SIZE = 8
EPOCHS = 5
OUT_DIR = os.path.join(os.path.dirname(__file__), "output")


def build_model():
    """Small CNN that predicts one face box (4 values) from an image."""
    inp = tf.keras.layers.Input(shape=(INPUT_SIZE, INPUT_SIZE, 3))
    x = tf.keras.layers.Conv2D(32, 3, activation="relu", padding="same")(inp)
    x = tf.keras.layers.MaxPool2D(2)(x)
    x = tf.keras.layers.Conv2D(64, 3, activation="relu", padding="same")(x)
    x = tf.keras.layers.MaxPool2D(2)(x)
    x = tf.keras.layers.Conv2D(64, 3, activation="relu", padding="same")(x)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dense(64, activation="relu")(x)
    out = tf.keras.layers.Dense(4, activation="sigmoid", name="box")(x)  # ymin, xmin, ymax, xmax
    model = tf.keras.Model(inp, out)
    return model


def load_synthetic_data(num_samples=200):
    """Synthetic images and random boxes for demo. Replace with real face dataset."""
    X = np.random.randint(0, 255, (num_samples, INPUT_SIZE, INPUT_SIZE, 3), dtype=np.uint8)
    # Random normalized boxes (ymin, xmin, ymax, xmax)
    y = np.random.uniform(0.2, 0.8, (num_samples, 4)).astype(np.float32)
    return X.astype(np.float32) / 255.0, y


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    model = build_model()
    model.compile(optimizer="adam", loss="mse", metrics=["mae"])

    X, y = load_synthetic_data()
    model.fit(X, y, batch_size=BATCH_SIZE, epochs=EPOCHS, validation_split=0.2)

    # Export to TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()
    out_path = os.path.join(OUT_DIR, "face_detection_trained.tflite")
    with open(out_path, "wb") as f:
        f.write(tflite_model)
    print("Saved TFLite model to", out_path)
    print("For production: train on WIDER FACE / CelebA and use proper input preprocessing and NMS.")


if __name__ == "__main__":
    main()
