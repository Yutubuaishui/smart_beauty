import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as tflite;
import 'package:image/image.dart' as img;

import '../models/makeup_product.dart';
import '../services/makeup_api_service.dart';
import '../services/cosmetic_recommender_service.dart';

// Setting powder removed — no visual overlay possible.
enum MakeupStep { foundation, eyebrow, eyeshadow, lipstick }

class SmartAdvisorPage extends StatefulWidget {
  const SmartAdvisorPage({super.key});

  @override
  State<SmartAdvisorPage> createState() => _SmartAdvisorPageState();
}

class _SmartAdvisorPageState extends State<SmartAdvisorPage>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;

  final _makeupApi = MakeupApiService();

  List<MakeupProduct> _foundationProducts = [];
  List<MakeupProduct> _lipstickProducts = [];
  List<MakeupProduct> _eyebrowProducts = [];
  List<MakeupProduct> _eyeshadowProducts = [];

  bool _isLoadingProducts = true;
  String? _productError;
  bool _cameraUnavailable = false;

  // All selected colours persist across steps
  MakeupColorOption? _selectedFoundationColor;
  MakeupProduct? _selectedFoundationProduct;
  MakeupColorOption? _selectedLipstickColor;
  MakeupProduct? _selectedLipstickProduct;
  MakeupColorOption? _selectedEyebrowColor;
  MakeupProduct? _selectedEyebrowProduct;
  MakeupColorOption? _selectedEyeshadowColor;
  MakeupProduct? _selectedEyeshadowProduct;

  MakeupStep _currentStep = MakeupStep.foundation;
  late final AnimationController _tutorialController;

  // Face detection
  Face? _detectedFace;
  Size? _detectedImageSize;
  // Sensor rotation reported by camera (0, 90, 180, 270)
  int _sensorRotation = 0;
  Rect? _tfliteFaceRect;
  Size? _tfliteImageSize;
  Timer? _faceDetectionTimer;
  bool _faceDetectionStarted = false;
  tflite.FaceDetector? _tfliteDetector;

  final _recommender = CosmeticRecommenderService();
  bool _recommendationRequested = false;

  bool get _hasFaceDetected =>
      _detectedFace != null || _tfliteFaceRect != null;

  @override
  void initState() {
    super.initState();
    _tutorialController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _setupCamera();
    _loadProducts();
  }

  // ── Camera ───────────────────────────────────────────────────────────────

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraUnavailable = true);
        return;
      }
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      // Store sensor orientation so we can rotate face coordinates correctly
      _sensorRotation = frontCamera.sensorOrientation;
      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      final initFuture = controller.initialize();
      setState(() {
        _cameraController = controller;
        _initializeControllerFuture = initFuture;
      });
    } catch (e) {
      debugPrint('Camera setup error: $e');
      setState(() => _cameraUnavailable = true);
    }
  }

  // ── Products ─────────────────────────────────────────────────────────────

  Future<void> _loadProducts() async {
    setState(() {
      _isLoadingProducts = true;
      _productError = null;
    });
    try {
      final results = await Future.wait<List<MakeupProduct>>([
        _makeupApi.fetchProductsByType('foundation'),
        _makeupApi.fetchProductsByType('lipstick'),
        _makeupApi.fetchProductsByType('eyebrow'),
        _makeupApi.fetchProductsByType('eyeshadow'),
      ]);
      setState(() {
        _foundationProducts = results[0];
        _lipstickProducts = results[1].isEmpty ? results[0] : results[1];
        _eyebrowProducts = results[2].isEmpty ? results[0] : results[2];
        _eyeshadowProducts = results[3].isEmpty ? results[0] : results[3];
        _isLoadingProducts = false;
      });
    } catch (e) {
      setState(() {
        _productError = 'Failed to load products. Please retry.';
        _isLoadingProducts = false;
      });
    }
  }

  @override
  void dispose() {
    _faceDetectionTimer?.cancel();
    _tfliteDetector?.dispose();
    _tutorialController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ── Face detection ────────────────────────────────────────────────────────

  void _startFaceDetectionIfReady() {
    if (_faceDetectionStarted || _cameraController == null) return;
    if (!_cameraController!.value.isInitialized) return;
    _faceDetectionStarted = true;
    _faceDetectionTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => _detectFace(),
    );
  }

  Future<void> _detectFace() async {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized || !mounted) return;
    XFile? file;
    try { file = await ctrl.takePicture(); } catch (_) { return; }
    if (!mounted) return;

    try {
      final inputImage = InputImage.fromFilePath(file.path);
      final detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.10,
          enableContours: true,
          enableLandmarks: true,
        ),
      );
      final faces = await detector.processImage(inputImage);
      await detector.close();
      if (!mounted) return;

      if (faces.isNotEmpty) {
        final face = faces.first;
        // Prefer metadata size; fall back to decoding the JPEG
        var imgSize = inputImage.metadata?.size;
        if (imgSize == null) {
          try {
            final bytes = await file.readAsBytes();
            final decoded = img.decodeImage(bytes);
            if (decoded != null) {
              imgSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
            }
          } catch (_) {}
        }
        setState(() {
          _detectedFace = face;
          _detectedImageSize = imgSize;
          _tfliteFaceRect = null;
          _tfliteImageSize = null;
        });
        _runRecommendationIfNeeded(file, _toRect(face.boundingBox), imgSize);
        return;
      } else {
        if (mounted) setState(() { _detectedFace = null; _detectedImageSize = null; });
      }
    } catch (_) {
      // ML Kit not available — fall through to TFLite
    }
    await _detectFaceTflite(file);
  }

  Future<void> _detectFaceTflite(XFile file) async {
    if (!mounted) return;
    try {
      final bytes = await file.readAsBytes();
      _tfliteDetector ??= tflite.FaceDetector();
      try {
        await _tfliteDetector!.initialize(model: tflite.FaceDetectionModel.frontCamera);
      } catch (_) { return; }
      final faces = await _tfliteDetector!.detectFaces(bytes);
      if (!mounted) return;
      if (faces.isNotEmpty) {
        final face = faces.first;
        final decoded = img.decodeImage(bytes);
        final imgSize = decoded != null
            ? Size(decoded.width.toDouble(), decoded.height.toDouble())
            : null;
        if (imgSize == null) return;
        final rect = _toRect(face.boundingBox);
        setState(() {
          _detectedFace = null;
          _detectedImageSize = null;
          _tfliteFaceRect = rect;
          _tfliteImageSize = imgSize;
        });
        _runRecommendationIfNeeded(file, rect, imgSize);
      } else {
        if (mounted) setState(() { _tfliteFaceRect = null; _tfliteImageSize = null; });
      }
    } catch (_) {}
  }

  Future<void> _runRecommendationIfNeeded(XFile file, Rect faceRect, Size? imageSize) async {
    if (_recommendationRequested || imageSize == null || !mounted) return;
    _recommendationRequested = true;
    try {
      final bytes = await file.readAsBytes();
      final skinHex = _recommender.getSkinToneFromImageBytes(bytes, faceRect);
      if (skinHex == null || !mounted) return;
      final foundationRecs = await _recommender.recommendFoundation(skinHex, limit: 3);
      final lipRecs = await _recommender.recommendLipstick(skinHex, limit: 2);
      final browRecs = await _recommender.recommendEyebrow(skinHex, limit: 2);
      if (!mounted) return;
      setState(() {
        if (foundationRecs.isNotEmpty && _selectedFoundationProduct == null) {
          _selectedFoundationProduct = foundationRecs.first.product;
          _selectedFoundationColor = foundationRecs.first.color;
        }
        if (lipRecs.isNotEmpty && _selectedLipstickProduct == null) {
          _selectedLipstickProduct = lipRecs.first.product;
          _selectedLipstickColor = lipRecs.first.color;
        }
        if (browRecs.isNotEmpty && _selectedEyebrowProduct == null) {
          _selectedEyebrowProduct = browRecs.first.product;
          _selectedEyebrowColor = browRecs.first.color;
        }
      });
    } catch (_) {}
    _recommendationRequested = false;
  }

  // ── Product selection ─────────────────────────────────────────────────────

  void _onSelectProduct(MakeupProduct product, MakeupColorOption? color) {
    setState(() {
      switch (_currentStep) {
        case MakeupStep.foundation:
          _selectedFoundationProduct = product;
          _selectedFoundationColor = color;
          break;
        case MakeupStep.lipstick:
          _selectedLipstickProduct = product;
          _selectedLipstickColor = color;
          break;
        case MakeupStep.eyebrow:
          _selectedEyebrowProduct = product;
          _selectedEyebrowColor = color;
          break;
        case MakeupStep.eyeshadow:
          _selectedEyeshadowProduct = product;
          _selectedEyeshadowColor = color;
          break;
      }
    });
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var c = hex.toUpperCase().replaceAll('#', '');
    if (c.length == 3) c = c.split('').map((x) => '$x$x').join();
    if (c.length == 6) c = 'FF$c';
    if (c.length != 8) return null;
    try { return Color(int.parse(c, radix: 16)); } catch (_) { return null; }
  }

  Color? get _foundationColor => _parseHexColor(_selectedFoundationColor?.hexValue);
  Color? get _lipstickColor   => _parseHexColor(_selectedLipstickColor?.hexValue);
  Color? get _eyebrowColor    => _parseHexColor(_selectedEyebrowColor?.hexValue);
  Color? get _eyeshadowColor  => _parseHexColor(_selectedEyeshadowColor?.hexValue);

  void _goToNextStep() {
    setState(() {
      switch (_currentStep) {
        case MakeupStep.foundation: _currentStep = MakeupStep.eyebrow; break;
        case MakeupStep.eyebrow:    _currentStep = MakeupStep.eyeshadow; break;
        case MakeupStep.eyeshadow:  _currentStep = MakeupStep.lipstick; break;
        case MakeupStep.lipstick:   _currentStep = MakeupStep.foundation; break;
      }
    });
  }

  // ── Coordinate mapping ────────────────────────────────────────────────────

  /// Maps an image-space rect to display-space, accounting for:
  ///  • Camera sensor rotation (the JPEG is rotated relative to display)
  ///  • BoxFit.cover scaling (CameraPreview fills the panel)
  ///
  /// [imgSize] is the JPEG pixel dimensions BEFORE any rotation is applied.
  /// [rotation] is the sensor orientation (0 / 90 / 180 / 270).
  Rect _toDisplayCover(
    Rect ir,
    Size imgSize,
    double dW,
    double dH,
    int rotation,
  ) {
    // 1. Rotate the point / rect to match how the JPEG is actually oriented.
    //    ML Kit returns coords in the rotated (display-oriented) image space,
    //    but the JPEG may be stored in sensor space. We need to normalise.
    //    For front cameras Flutter typically receives the image already rotated
    //    by the sensor orientation, so the stored JPEG is in display orientation.
    //    Hence imgSize.width/height already match display orientation width/height.
    //    No additional rotation transform is needed here — we just do cover-fit.

    if (imgSize.width <= 0 || imgSize.height <= 0) return ir;

    // 2. Cover-fit scale: use the axis that fills the panel completely
    final scaleX = dW / imgSize.width;
    final scaleY = dH / imgSize.height;
    final scale = max(scaleX, scaleY);

    // 3. Crop offsets (negative means the image extends beyond the display)
    final ox = (dW - imgSize.width * scale) / 2;
    final oy = (dH - imgSize.height * scale) / 2;

    return Rect.fromLTRB(
      (ir.left  * scale + ox).clamp(0.0, dW),
      (ir.top   * scale + oy).clamp(0.0, dH),
      (ir.right * scale + ox).clamp(0.0, dW),
      (ir.bottom * scale + oy).clamp(0.0, dH),
    );
  }

  List<Offset>? _mlkitContour(
    Face face,
    FaceContourType type,
    Size imgSize,
    double dW,
    double dH,
  ) {
    final contour = face.contours[type];
    if (contour == null || contour.points.isEmpty) return null;
    if (imgSize.width <= 0 || imgSize.height <= 0) return null;
    final scale = max(dW / imgSize.width, dH / imgSize.height);
    final ox = (dW - imgSize.width * scale) / 2;
    final oy = (dH - imgSize.height * scale) / 2;
    return contour.points
        .map((p) => Offset(p.x.toDouble() * scale + ox,
                           p.y.toDouble() * scale + oy))
        .toList();
  }

  // ── Synthetic contours for guide oval / TFLite ────────────────────────────

  void _buildSyntheticContours(
    Rect r, {
    required List<Offset> faceContour,
    required List<Offset> leftBrowTop,
    required List<Offset> leftBrowBottom,
    required List<Offset> rightBrowTop,
    required List<Offset> rightBrowBottom,
    required List<Offset> upperLipTop,
    required List<Offset> upperLipBottom,
    required List<Offset> lowerLipTop,
    required List<Offset> lowerLipBottom,
    // Extra contours used for eye-shadow positioning
    required List<Offset> leftEyeContour,
    required List<Offset> rightEyeContour,
  }) {
    final cx = r.center.dx;
    final cy = r.center.dy;
    final rx = r.width / 2;
    final ry = r.height / 2;

    // Face oval
    const n = 36;
    for (var i = 0; i <= n; i++) {
      final t = (i / n) * 2 * pi;
      faceContour.add(Offset(cx + rx * cos(t), cy + ry * sin(t)));
    }

    // Eyebrows — ~48 % up from centre
    final browCY = cy - ry * 0.46;
    final browH  = ry * 0.07;
    leftBrowTop
      ..add(Offset(cx - rx * 0.58, browCY + browH * 0.4))
      ..add(Offset(cx - rx * 0.16, browCY - browH * 0.5));
    leftBrowBottom
      ..add(Offset(cx - rx * 0.16, browCY + browH * 0.3))
      ..add(Offset(cx - rx * 0.58, browCY + browH));
    rightBrowTop
      ..add(Offset(cx + rx * 0.16, browCY - browH * 0.5))
      ..add(Offset(cx + rx * 0.58, browCY + browH * 0.4));
    rightBrowBottom
      ..add(Offset(cx + rx * 0.58, browCY + browH))
      ..add(Offset(cx + rx * 0.16, browCY + browH * 0.3));

    // Eyes (small ovals) — for eyeshadow placement
    final eyeCY  = cy - ry * 0.28;
    final eyeW   = rx * 0.36;
    final eyeH   = ry * 0.12;
    const eyeN   = 16;
    for (var i = 0; i <= eyeN; i++) {
      final t = (i / eyeN) * 2 * pi;
      leftEyeContour.add(Offset(cx - rx * 0.36 + eyeW / 2 * cos(t),
                                 eyeCY + eyeH / 2 * sin(t)));
      rightEyeContour.add(Offset(cx + rx * 0.36 + eyeW / 2 * cos(t),
                                  eyeCY + eyeH / 2 * sin(t)));
    }

    // Lips — ~30 % below centre
    final lipCY = cy + ry * 0.28;
    final lipW  = rx * 0.46;
    final lipH  = ry * 0.16;
    upperLipTop
      ..add(Offset(cx - lipW,         lipCY))
      ..add(Offset(cx - lipW * 0.44,  lipCY - lipH * 0.75))
      ..add(Offset(cx,                lipCY - lipH * 0.30))
      ..add(Offset(cx + lipW * 0.44,  lipCY - lipH * 0.75))
      ..add(Offset(cx + lipW,         lipCY));
    upperLipBottom
      ..add(Offset(cx + lipW, lipCY))
      ..add(Offset(cx,        lipCY + lipH * 0.35))
      ..add(Offset(cx - lipW, lipCY));
    lowerLipTop
      ..add(Offset(cx - lipW, lipCY))
      ..add(Offset(cx,        lipCY + lipH * 0.35))
      ..add(Offset(cx + lipW, lipCY));
    lowerLipBottom
      ..add(Offset(cx + lipW, lipCY))
      ..add(Offset(cx,        lipCY + lipH))
      ..add(Offset(cx - lipW, lipCY));
  }

  // ── Overlay builder ───────────────────────────────────────────────────────

  Widget _buildOverlayHints() {
    final face = _detectedFace;
    final imageSize = _detectedImageSize ?? _tfliteImageSize;

    return LayoutBuilder(builder: (context, constraints) {
      final dW = constraints.maxWidth;
      final dH = constraints.maxHeight;

      List<Offset>? faceContour;
      List<Offset>? lbt, lbb, rbt, rbb, ult, ulb, llt, llb;
      List<Offset>? leftEye, rightEye;
      Rect? faceBounds;

      if (face != null && imageSize != null) {
        // ── ML Kit real face ─────────────────────────────────────────────
        faceBounds = _toDisplayCover(
            _toRect(face.boundingBox), imageSize, dW, dH, _sensorRotation);
        faceContour = _mlkitContour(face, FaceContourType.face,        imageSize, dW, dH);
        lbt = _mlkitContour(face, FaceContourType.leftEyebrowTop,      imageSize, dW, dH);
        lbb = _mlkitContour(face, FaceContourType.leftEyebrowBottom,   imageSize, dW, dH);
        rbt = _mlkitContour(face, FaceContourType.rightEyebrowTop,     imageSize, dW, dH);
        rbb = _mlkitContour(face, FaceContourType.rightEyebrowBottom,  imageSize, dW, dH);
        ult = _mlkitContour(face, FaceContourType.upperLipTop,         imageSize, dW, dH);
        ulb = _mlkitContour(face, FaceContourType.upperLipBottom,      imageSize, dW, dH);
        llt = _mlkitContour(face, FaceContourType.lowerLipTop,         imageSize, dW, dH);
        llb = _mlkitContour(face, FaceContourType.lowerLipBottom,      imageSize, dW, dH);
        // Use left/right eye contours for eyeshadow placement
        leftEye  = _mlkitContour(face, FaceContourType.leftEye,  imageSize, dW, dH);
        rightEye = _mlkitContour(face, FaceContourType.rightEye, imageSize, dW, dH);
      } else if (_tfliteFaceRect != null && imageSize != null) {
        // ── TFLite real face — synthetic ─────────────────────────────────
        faceBounds = _toDisplayCover(
            _tfliteFaceRect!, imageSize, dW, dH, _sensorRotation);
        faceContour = []; lbt=[]; lbb=[]; rbt=[]; rbb=[];
        ult=[]; ulb=[]; llt=[]; llb=[]; leftEye=[]; rightEye=[];
        _buildSyntheticContours(faceBounds,
          faceContour: faceContour, leftBrowTop: lbt, leftBrowBottom: lbb,
          rightBrowTop: rbt, rightBrowBottom: rbb,
          upperLipTop: ult, upperLipBottom: ulb,
          lowerLipTop: llt, lowerLipBottom: llb,
          leftEyeContour: leftEye, rightEyeContour: rightEye);
      } else {
        // ── No face — centred guide oval with full makeup preview ─────────
        // Use a natural portrait aspect ratio (3:4) for the guide oval.
        final ovalH = dH * 0.70;
        final ovalW = ovalH * 0.72; // slightly narrower than tall
        faceBounds = Rect.fromCenter(
          center: Offset(dW * 0.5, dH * 0.50),
          width: ovalW,
          height: ovalH,
        );
        faceContour = []; lbt=[]; lbb=[]; rbt=[]; rbb=[];
        ult=[]; ulb=[]; llt=[]; llb=[]; leftEye=[]; rightEye=[];
        _buildSyntheticContours(faceBounds,
          faceContour: faceContour, leftBrowTop: lbt, leftBrowBottom: lbb,
          rightBrowTop: rbt, rightBrowBottom: rbb,
          upperLipTop: ult, upperLipBottom: ulb,
          lowerLipTop: llt, lowerLipBottom: llb,
          leftEyeContour: leftEye, rightEyeContour: rightEye);
      }

      return IgnorePointer(
        child: CustomPaint(
          size: Size(dW, dH),
          painter: _MakeupOverlayPainter(
            faceContourDisplay: faceContour,
            leftBrowTop: lbt, leftBrowBottom: lbb,
            rightBrowTop: rbt, rightBrowBottom: rbb,
            upperLipTop: ult, upperLipBottom: ulb,
            lowerLipTop: llt, lowerLipBottom: llb,
            leftEyeContour: leftEye,
            rightEyeContour: rightEye,
            faceBoundsDisplay: faceBounds,
            foundationColor: _foundationColor,
            lipstickColor:   _lipstickColor,
            eyebrowColor:    _eyebrowColor,
            eyeshadowColor:  _eyeshadowColor,
            hasFaceDetected: _hasFaceDetected,
          ),
        ),
      );
    });
  }

  Rect _toRect(dynamic box) {
    if (box is Rect) return box;
    try {
      return Rect.fromLTRB(
        (box.left as num).toDouble(), (box.top as num).toDouble(),
        (box.right as num).toDouble(), (box.bottom as num).toDouble());
    } catch (_) { return Rect.zero; }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Makeup Advisor'), elevation: 0),
      body: Row(children: [
        Expanded(
          flex: 1,
          child: Stack(fit: StackFit.expand, children: [
            _buildCameraPreview(),
            _buildOverlayHints(),
            _buildSelectedSummaryChip(theme),
          ]),
        ),
        Expanded(flex: 1, child: _buildBottomPanel(theme)),
      ]),
    );
  }

  // ── Camera preview ────────────────────────────────────────────────────────

  Widget _buildCameraPreview() {
    if (_cameraUnavailable) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Camera not available',
                style: TextStyle(fontSize: 16, color: Colors.grey[400])),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Pick products on the right — preview shows on the guide oval.',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ),
          ]),
        ),
      );
    }

    final ctrl = _cameraController;
    final initFuture = _initializeControllerFuture;
    if (ctrl == null || initFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startFaceDetectionIfReady();
        });
        // Wrap in LayoutBuilder so we can constrain to natural aspect ratio
        // without stretching the preview.
        return LayoutBuilder(builder: (ctx, constraints) {
          final previewAspect = ctrl.value.aspectRatio; // width / height
          final panelW = constraints.maxWidth;
          final panelH = constraints.maxHeight;

          // Fit the camera preview so it fills the panel using BoxFit.cover
          // (same as CameraPreview default) — this preserves the original
          // camera aspect ratio; the face overlay uses the same maths.
          return SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width:  ctrl.value.previewSize?.width  ?? panelW,
                height: ctrl.value.previewSize?.height ?? panelH,
                child: CameraPreview(ctrl),
              ),
            ),
          );
        });
      },
    );
  }

  // ── Summary chip ──────────────────────────────────────────────────────────

  Widget _buildSelectedSummaryChip(ThemeData theme) {
    final parts = <String>[];
    if (_selectedFoundationProduct != null)
      parts.add('Foundation: ${_selectedFoundationProduct!.brand ?? ''} ${_selectedFoundationProduct!.name}');
    if (_selectedEyebrowProduct != null)
      parts.add('Eyebrow: ${_selectedEyebrowProduct!.brand ?? ''} ${_selectedEyebrowProduct!.name}');
    if (_selectedEyeshadowProduct != null)
      parts.add('Eyeshadow: ${_selectedEyeshadowProduct!.brand ?? ''} ${_selectedEyeshadowProduct!.name}');
    if (_selectedLipstickProduct != null)
      parts.add('Lipstick: ${_selectedLipstickProduct!.brand ?? ''} ${_selectedLipstickProduct!.name}');
    if (parts.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 16, right: 16, bottom: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withAlpha((0.88 * 255).round()),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(parts.join('  •  '),
            style: theme.textTheme.bodySmall, maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ),
    );
  }

  // ── Right panel ───────────────────────────────────────────────────────────

  Widget _buildBottomPanel(ThemeData theme) {
    if (_isLoadingProducts) return const Center(child: CircularProgressIndicator());
    if (_productError != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_productError!),
        const SizedBox(height: 8),
        FilledButton(onPressed: _loadProducts, child: const Text('Retry')),
      ]));
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
        boxShadow: [BoxShadow(
          color: Colors.black.withAlpha((0.06 * 255).round()),
          blurRadius: 12, offset: const Offset(-4, 0))],
      ),
      child: Column(children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(999))),
        const SizedBox(height: 8),
        _buildStepHeader(theme),
        const Divider(height: 1),
        Expanded(child: Row(children: [
          Expanded(flex: 2, child: _buildProductListForCurrentStep(theme)),
          const VerticalDivider(width: 1),
          Expanded(flex: 1, child: _buildTutorialPanel(theme)),
        ])),
      ]),
    );
  }

  Widget _buildStepHeader(ThemeData theme) {
    final (title, subtitle) = switch (_currentStep) {
      MakeupStep.foundation => ('Step 1 · Foundation',  'Pick your base shade.'),
      MakeupStep.eyebrow    => ('Step 2 · Eyebrow',     'Shape and fill brows.'),
      MakeupStep.eyeshadow  => ('Step 3 · Eyeshadow',   'Add depth to your eyes.'),
      MakeupStep.lipstick   => ('Step 4 · Lipstick',    'Finish with a lip colour.'),
    };
    return ListTile(
      title: Text(title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: FilledButton.icon(
        onPressed: _goToNextStep,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Next'),
      ),
    );
  }

  Widget _buildProductListForCurrentStep(ThemeData theme) {
    final products = switch (_currentStep) {
      MakeupStep.foundation => _foundationProducts,
      MakeupStep.eyebrow    => _eyebrowProducts,
      MakeupStep.eyeshadow  => _eyeshadowProducts,
      MakeupStep.lipstick   => _lipstickProducts,
    };
    if (products.isEmpty) {
      return const Center(child: Text('No products found for this step.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      scrollDirection: Axis.horizontal,
      itemCount: products.length,
      itemBuilder: (ctx, i) {
        final product = products[i];
        return _MakeupProductCard(
          product: product,
          isSelected: product == _selectedFoundationProduct ||
              product == _selectedLipstickProduct ||
              product == _selectedEyebrowProduct ||
              product == _selectedEyeshadowProduct,
          onSelect: (color) => _onSelectProduct(product, color),
        );
      },
    );
  }

  Widget _buildTutorialPanel(ThemeData theme) {
    final anim = _tutorialController.value;
    int si(MakeupStep s) => s.index;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Guide', style: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(child: ListView(children: [
          _TutorialStepTile(index: 1, title: 'Foundation',
            description: 'Blend from centre outward with a damp sponge.',
            isActive: _currentStep == MakeupStep.foundation,
            progress: _currentStep == MakeupStep.foundation ? anim
                : (si(_currentStep) > si(MakeupStep.foundation) ? 1.0 : 0.0)),
          _TutorialStepTile(index: 2, title: 'Eyebrow',
            description: 'Outline brow edge, fill sparse areas with short strokes.',
            isActive: _currentStep == MakeupStep.eyebrow,
            progress: _currentStep == MakeupStep.eyebrow ? anim
                : (si(_currentStep) > si(MakeupStep.eyebrow) ? 1.0 : 0.0)),
          _TutorialStepTile(index: 3, title: 'Eyeshadow',
            description: 'Light on lid, medium in crease, deepen outer corner.',
            isActive: _currentStep == MakeupStep.eyeshadow,
            progress: _currentStep == MakeupStep.eyeshadow ? anim
                : (si(_currentStep) > si(MakeupStep.eyeshadow) ? 1.0 : 0.0)),
          _TutorialStepTile(index: 4, title: 'Lipstick',
            description: 'Outline lips then fill toward centre. Blot and reapply.',
            isActive: _currentStep == MakeupStep.lipstick,
            progress: _currentStep == MakeupStep.lipstick ? anim
                : (si(_currentStep) > si(MakeupStep.lipstick) ? 1.0 : 0.0)),
        ])),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _hasFaceDetected
              ? Row(key: const ValueKey('on'), children: [
                  Icon(Icons.face, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Expanded(child: Text('Face detected — live overlay active.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary))),
                ])
              : Row(key: const ValueKey('off'), children: [
                  Icon(Icons.face_retouching_natural, size: 14,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(child: Text('Align face with the oval guide.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                ]),
        ),
        const SizedBox(height: 4),
        Text('All selected colours stay on as you move between steps.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Makeup Overlay Painter
// ─────────────────────────────────────────────────────────────────────────────

class _MakeupOverlayPainter extends CustomPainter {
  final List<Offset>? faceContourDisplay;
  final List<Offset>? leftBrowTop, leftBrowBottom;
  final List<Offset>? rightBrowTop, rightBrowBottom;
  final List<Offset>? upperLipTop, upperLipBottom;
  final List<Offset>? lowerLipTop, lowerLipBottom;
  final List<Offset>? leftEyeContour, rightEyeContour;
  final Rect? faceBoundsDisplay;
  final Color? foundationColor, lipstickColor, eyebrowColor, eyeshadowColor;
  final bool hasFaceDetected;

  const _MakeupOverlayPainter({
    this.faceContourDisplay,
    this.leftBrowTop, this.leftBrowBottom,
    this.rightBrowTop, this.rightBrowBottom,
    this.upperLipTop, this.upperLipBottom,
    this.lowerLipTop, this.lowerLipBottom,
    this.leftEyeContour, this.rightEyeContour,
    this.faceBoundsDisplay,
    this.foundationColor, this.lipstickColor,
    this.eyebrowColor, this.eyeshadowColor,
    required this.hasFaceDetected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = faceBoundsDisplay;
    if (r == null) return;

    // ── 1. Guide outline ──────────────────────────────────────────────────
    final guidePaint = Paint()
      ..color = hasFaceDetected
          ? Colors.greenAccent.withAlpha(210)
          : Colors.white.withAlpha(160)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..isAntiAlias = true;
    hasFaceDetected
        ? canvas.drawOval(r, guidePaint)
        : _drawDashedOval(canvas, r, guidePaint);

    // ── 2. Foundation — semi-transparent skin tone tint over face region ──
    if (foundationColor != null) {
      // Use a soft blending: fill the face contour (or oval) with the colour
      // at moderate opacity so the skin texture still shows through.
      final p = Paint()
        ..color = foundationColor!.withAlpha((0.55 * 255).round())
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.srcOver
        ..isAntiAlias = true;
      if (faceContourDisplay != null && faceContourDisplay!.length >= 3) {
        canvas.drawPath(_pointsToPath(faceContourDisplay!), p);
      } else {
        canvas.drawOval(r, p);
      }
    }

    // ── 3. Eyeshadow — drawn over the eye lid region ───────────────────────
    if (eyeshadowColor != null) {
      final p = Paint()
        ..color = eyeshadowColor!.withAlpha((0.68 * 255).round())
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.multiply
        ..isAntiAlias = true;

      // Try to use real eye contours first
      if (leftEyeContour != null && leftEyeContour!.length >= 3) {
        // Extend the eye contour upward to cover the lid (not just the eye opening)
        final lidPts = _expandEyeLid(leftEyeContour!, r, isLeft: true);
        canvas.drawPath(_pointsToPath(lidPts), p);
      } else {
        _drawEyeshadowOval(canvas, r, isLeft: true, p: p);
      }

      if (rightEyeContour != null && rightEyeContour!.length >= 3) {
        final lidPts = _expandEyeLid(rightEyeContour!, r, isLeft: false);
        canvas.drawPath(_pointsToPath(lidPts), p);
      } else {
        _drawEyeshadowOval(canvas, r, isLeft: false, p: p);
      }
    }

    // ── 4. Eyebrows ───────────────────────────────────────────────────────
    if (eyebrowColor != null) {
      final p = Paint()
        ..color = eyebrowColor!.withAlpha((0.88 * 255).round())
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.srcOver
        ..isAntiAlias = true;
      final lOk = _drawBrow(canvas, leftBrowTop,  leftBrowBottom,  p);
      final rOk = _drawBrow(canvas, rightBrowTop, rightBrowBottom, p);
      if (!lOk && !rOk) {
        // Fallback arched rectangles
        final browY = r.top + r.height * 0.26;
        final bW = r.width * 0.24;
        final bH = r.height * 0.055;
        for (final bx in [r.center.dx - r.width * 0.27, r.center.dx + r.width * 0.27]) {
          canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(bx, browY), width: bW, height: bH),
            const Radius.circular(8)), p);
        }
      }
    }

    // ── 5. Lipstick ───────────────────────────────────────────────────────
    if (lipstickColor != null) {
      final p = Paint()
        ..color = lipstickColor!.withAlpha((0.85 * 255).round())
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.srcOver
        ..isAntiAlias = true;
      final all = <Offset>[
        ...?upperLipTop, ...?upperLipBottom,
        if (lowerLipBottom != null) ...lowerLipBottom!.reversed,
        if (lowerLipTop    != null) ...lowerLipTop!.reversed,
      ];
      if (all.length >= 3) {
        canvas.drawPath(_pointsToPath(all), p);
      } else {
        // Fallback oval lip
        canvas.drawOval(Rect.fromCenter(
          center: Offset(r.center.dx, r.top + r.height * 0.72),
          width: r.width * 0.44, height: r.height * 0.14), p);
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Extends eye contour upward to simulate the eyelid/eyeshadow area.
  List<Offset> _expandEyeLid(List<Offset> eye, Rect face, {required bool isLeft}) {
    if (eye.isEmpty) return eye;
    final minY = eye.map((e) => e.dy).reduce(min);
    final lidH = face.height * 0.07;
    // Take only the top half of the eye contour and push it upward
    final top = eye.where((e) => e.dy <= minY + (face.height * 0.04)).toList();
    if (top.isEmpty) return eye;
    final expanded = [
      ...eye,
      ...top.reversed.map((e) => Offset(e.dx, e.dy - lidH)),
    ];
    return expanded;
  }

  void _drawEyeshadowOval(Canvas canvas, Rect r, {required bool isLeft, required Paint p}) {
    final eyeY = r.top + r.height * 0.30;
    final eyeW = r.width  * 0.22;
    final eyeH = r.height * 0.10;
    final cx = isLeft
        ? r.center.dx - r.width * 0.24
        : r.center.dx + r.width * 0.24;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, eyeY), width: eyeW, height: eyeH), p);
  }

  bool _drawBrow(Canvas canvas, List<Offset>? top, List<Offset>? bottom, Paint p) {
    final pts = <Offset>[...?top, if (bottom != null) ...bottom.reversed];
    if (pts.length < 3) return false;
    canvas.drawPath(_pointsToPath(pts), p);
    return true;
  }

  Path _pointsToPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) path.lineTo(pts[i].dx, pts[i].dy);
    return path..close();
  }

  void _drawDashedOval(Canvas canvas, Rect rect, Paint paint) {
    const dashCount = 28;
    const gap = 0.35;
    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(rect, (i / dashCount) * 2 * pi,
          (1 - gap) / dashCount * 2 * pi, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MakeupOverlayPainter old) =>
      old.foundationColor != foundationColor ||
      old.lipstickColor   != lipstickColor   ||
      old.eyebrowColor    != eyebrowColor    ||
      old.eyeshadowColor  != eyeshadowColor  ||
      old.faceContourDisplay != faceContourDisplay ||
      old.faceBoundsDisplay  != faceBoundsDisplay  ||
      old.leftBrowTop     != leftBrowTop  ||
      old.rightBrowTop    != rightBrowTop ||
      old.upperLipTop     != upperLipTop  ||
      old.lowerLipTop     != lowerLipTop  ||
      old.leftEyeContour  != leftEyeContour ||
      old.rightEyeContour != rightEyeContour ||
      old.hasFaceDetected != hasFaceDetected;
}

// ─────────────────────────────────────────────────────────────────────────────
// Product Card
// ─────────────────────────────────────────────────────────────────────────────

class _MakeupProductCard extends StatelessWidget {
  final MakeupProduct product;
  final bool isSelected;
  final void Function(MakeupColorOption? color) onSelect;

  const _MakeupProductCard({
    required this.product, required this.isSelected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasColors = product.colors.isNotEmpty;
    return Container(
      width: 220, margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        elevation: isSelected ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isSelected
              ? theme.colorScheme.primary : theme.colorScheme.outlineVariant)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onSelect(hasColors ? product.colors.first : null),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: product.imageUrl.isEmpty
                    ? Container(color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(child: Icon(Icons.image_not_supported_outlined)))
                    : Image.network(product.imageUrl, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Center(child: Icon(Icons.broken_image_outlined,
                              color: theme.colorScheme.onSurfaceVariant)))),
              )),
              const SizedBox(height: 8),
              Text(product.brand ?? 'Unknown brand',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(product.name,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              if (hasColors)
                SizedBox(height: 28, child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: product.colors.length.clamp(0, 6),
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (ctx, i) {
                    final co = product.colors[i];
                    final c = _parseHex(co.hexValue);
                    return GestureDetector(
                      onTap: () => onSelect(co),
                      child: Tooltip(message: co.name,
                        child: CircleAvatar(radius: 12,
                          backgroundColor: c ?? theme.colorScheme.surfaceContainerHighest,
                          child: c == null ? const Icon(Icons.color_lens, size: 14) : null)));
                  },
                )),
              if (!hasColors)
                Text('No colour options listed',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }

  Color? _parseHex(String hex) {
    var c = hex.toUpperCase().replaceAll('#', '');
    if (c.length == 3) c = c.split('').map((x) => '$x$x').join();
    if (c.length == 6) c = 'FF$c';
    if (c.length != 8) return null;
    try { return Color(int.parse(c, radix: 16)); } catch (_) { return null; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tutorial Step Tile
// ─────────────────────────────────────────────────────────────────────────────

class _TutorialStepTile extends StatelessWidget {
  final int index;
  final String title, description;
  final bool isActive;
  final double progress;

  const _TutorialStepTile({
    required this.index, required this.title, required this.description,
    required this.isActive, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active   = theme.colorScheme.primary;
    final inactive = theme.colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: (isActive || progress >= 1) ? active : inactive,
            child: Text('$index', style: theme.textTheme.labelSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          if (index < 4)
            Container(width: 2, height: 32, decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [active.withAlpha((progress.clamp(0,1)*255).round()), inactive]))),
        ]),
        const SizedBox(width: 8),
        Expanded(child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive ? active.withAlpha((0.07*255).round()) : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? active : inactive)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(description, style: theme.textTheme.bodySmall),
          ]),
        )),
      ]),
    );
  }
}