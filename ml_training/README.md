# Face detection model training / export for Smart Beauty

This folder contains scripts to **train or export** a face detection model (CNN) for use on all platforms, including Windows.

## Option 1: Use a pre-trained TFLite model (no training)

The app already uses:
- **Android/iOS**: Google ML Kit (contours + bbox).
- **Windows**: `face_detection_tflite` package with a bundled MediaPipe-style model.

No training is required for basic face detection.

## Option 2: Train or fine-tune a custom face detector (CNN)

If you want to **train your own** model (e.g. on custom data or to improve accuracy):

### Requirements

```bash
pip install tensorflow>=2.10 opencv-python matplotlib
```

### Data

- **WIDER FACE** or **CelebA** for face bounding boxes.
- Or your own dataset: images + text/JSON annotations (xmin, ymin, xmax, ymax per face).

### Quick start: export pre-trained to TFLite

```bash
python export_face_detector_tflite.py
```

This script downloads a pre-trained face detection model (e.g. from TF Hub or a small MobileNetV2-based detector) and exports it to `.tflite` for use in the app. No training step.

### Full training (optional)

```bash
python train_face_detector.py --data_dir path/to/wider_face --epochs 20
```

- Uses a small CNN (e.g. MobileNetV2 backbone + detection head).
- Saves best weights and exports to TFLite at the end.
- Place the output `.tflite` in your app assets and wire it to your TFLite interpreter (e.g. replace or complement the model used by `face_detection_tflite` if you use raw TFLite).

## Output

- `face_detection.tflite`: model file you can bundle in the app.
- Optionally: `labelmap.txt` if your model has classes.

## Auto cosmetic recommendation (colour code)

The app already implements **auto cosmetic recommendation**:

1. **Face detection** (ML Kit on Android/iOS, TFLite on Windows) gives a face bounding box.
2. **Skin tone** is estimated by sampling pixels in the face region (center 60%×50%) and averaging RGB → hex.
3. **Recommendation** uses the Makeup API: products are ranked by **colour distance** (RGB) to the skin tone; the closest foundation/lipstick/eyebrow shades (with brand + colour code) are suggested and applied to the overlay.

No extra training is needed for recommendation; it is rule-based from the detected face and API colours.
