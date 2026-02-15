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

enum MakeupStep {
  foundation,
  settingSpray,
  eyebrow,
  eyeshadow,
  lipstick,
}

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

  bool _isLoadingProducts = true;
  String? _productError;
  bool _cameraUnavailable = false;

  MakeupColorOption? _selectedFoundationColor;
  MakeupProduct? _selectedFoundationProduct;

  MakeupColorOption? _selectedLipstickColor;
  MakeupProduct? _selectedLipstickProduct;

  MakeupColorOption? _selectedEyebrowColor;
  MakeupProduct? _selectedEyebrowProduct;

  MakeupStep _currentStep = MakeupStep.foundation;
  late final AnimationController _tutorialController;

  /// Detected face with contours (used to draw makeup fixed to the real face). ML Kit.
  Face? _detectedFace;
  /// Size of the image the face was detected in (for correct coordinate mapping).
  Size? _detectedImageSize;
  /// When ML Kit is not available (e.g. Windows), TFLite face detection result.
  Rect? _tfliteFaceRect;
  Size? _tfliteImageSize;
  Timer? _faceDetectionTimer;
  bool _faceDetectionStarted = false;
  tflite.FaceDetector? _tfliteDetector;
  final _recommender = CosmeticRecommenderService();
  bool _recommendationRequested = false;

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

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      final initializeFuture = controller.initialize();

      setState(() {
        _cameraController = controller;
        _initializeControllerFuture = initializeFuture;
      });
    } catch (e) {
      debugPrint('Error setting up camera: $e');
      setState(() => _cameraUnavailable = true);
    }
  }

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
      ]);

      setState(() {
        _foundationProducts = results[0];
        _lipstickProducts = results[1].isEmpty
            ? results[0] // fallback: reuse foundation list if lipstick missing
            : results[1];
        _eyebrowProducts = results[2].isEmpty
            ? results[0] // fallback: reuse foundation list if eyebrow missing
            : results[2];
        _isLoadingProducts = false;
      });
    } catch (e) {
      setState(() {
        _productError = 'Failed to load makeup suggestions. Please try again.';
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

  void _startFaceDetectionIfReady() {
    if (_faceDetectionStarted || _cameraController == null) return;
    final ctrl = _cameraController!;
    if (!ctrl.value.isInitialized) return;
    _faceDetectionStarted = true;
    _faceDetectionTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) => _detectFace());
  }

  Future<void> _detectFace() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || !mounted) return;
    XFile? file;
    try {
      file = await controller.takePicture();
    } catch (_) {
      return;
    }
    if (!mounted) return;

    try {
      final inputImage = InputImage.fromFilePath(file.path);
      final detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.15,
          enableContours: true,
          enableLandmarks: false,
        ),
      );
      final faces = await detector.processImage(inputImage);
      await detector.close();
      if (!mounted) return;
      if (faces.isNotEmpty) {
        final face = faces.first;
        var imgSize = inputImage.metadata?.size;
        if (imgSize == null) {
          try {
            final bytes = await file.readAsBytes();
            final decoded = img.decodeImage(bytes);
            if (decoded != null) imgSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
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
      }
    } catch (_) {
      // ML Kit not available (e.g. Windows) or failed; try TFLite.
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
      } catch (_) {
        return;
      }
      final faces = await _tfliteDetector!.detectFaces(bytes);
      if (!mounted) return;
      if (faces.isNotEmpty) {
        final face = faces.first;
        final decoded = img.decodeImage(bytes);
        final imgSize = decoded != null ? Size(decoded.width.toDouble(), decoded.height.toDouble()) : null;
        if (imgSize == null) return;
        final rect = _toRect(face.boundingBox);
        setState(() {
          _detectedFace = null;
          _detectedImageSize = null;
          _tfliteFaceRect = rect;
          _tfliteImageSize = imgSize;
        });
        _runRecommendationIfNeeded(file, rect, imgSize);
      }
    } catch (_) {
      // TFLite not available or failed.
    }
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
        if (foundationRecs.isNotEmpty) {
          _selectedFoundationProduct = foundationRecs.first.product;
          _selectedFoundationColor = foundationRecs.first.color;
        }
        if (lipRecs.isNotEmpty) {
          _selectedLipstickProduct = lipRecs.first.product;
          _selectedLipstickColor = lipRecs.first.color;
        }
        if (browRecs.isNotEmpty) {
          _selectedEyebrowProduct = browRecs.first.product;
          _selectedEyebrowColor = browRecs.first.color;
        }
      });
    } catch (_) {}
    _recommendationRequested = false;
  }

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
        case MakeupStep.settingSpray:
        case MakeupStep.eyeshadow:
          // For now we only visualize foundation / lips / brows.
          break;
      }
    });
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var cleaned = hex.toUpperCase().replaceAll('#', '');
    if (cleaned.length == 3) {
      cleaned = cleaned.split('').map((c) => '$c$c').join();
    }
    if (cleaned.length == 6) {
      cleaned = 'FF$cleaned';
    }
    if (cleaned.length != 8) return null;
    try {
      return Color(int.parse(cleaned, radix: 16));
    } catch (_) {
      return null;
    }
  }

  Color? get _foundationColor =>
      _parseHexColor(_selectedFoundationColor?.hexValue);

  Color? get _lipstickColor =>
      _parseHexColor(_selectedLipstickColor?.hexValue);

  Color? get _eyebrowColor =>
      _parseHexColor(_selectedEyebrowColor?.hexValue);

  void _goToNextStep() {
    setState(() {
      switch (_currentStep) {
        case MakeupStep.foundation:
          _currentStep = MakeupStep.settingSpray;
          break;
        case MakeupStep.settingSpray:
          _currentStep = MakeupStep.eyebrow;
          break;
        case MakeupStep.eyebrow:
          _currentStep = MakeupStep.eyeshadow;
          break;
        case MakeupStep.eyeshadow:
          _currentStep = MakeupStep.lipstick;
          break;
        case MakeupStep.lipstick:
          _currentStep = MakeupStep.foundation;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Makeup Advisor'),
        elevation: 0,
      ),
      body: Row(
        children: [
          // Left: camera + overlay (fixed size area, full face visible)
          Expanded(
            flex: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCameraPreview(),
                if (!_cameraUnavailable) ...[
                  _buildOverlayHints(),
                  _buildSelectedSummaryChip(theme),
                ],
              ],
            ),
          ),
          // Right: steps, products, tutorial
          Expanded(
            flex: 1,
            child: _buildBottomPanel(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraUnavailable) {
      return Container(
        color: Colors.grey[300],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Camera not available',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Live camera is supported on Android and iOS. On Windows or web, pick products below to see makeup colours on the overlay.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _cameraController;
    final initFuture = _initializeControllerFuture;

    if (controller == null || initFuture == null) {
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
        final aspectRatio = controller.value.aspectRatio;
        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final maxH = constraints.maxHeight;
              double w;
              double h;
              if (maxW / maxH > aspectRatio) {
                h = maxH;
                w = maxH * aspectRatio;
              } else {
                w = maxW;
                h = maxW / aspectRatio;
              }
              return Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: CameraPreview(controller),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Maps a point from image coordinates to display (panel) coordinates.
  Offset _imageToDisplay(double ix, double iy, double scale, double offsetY) {
    return Offset(ix * scale, offsetY + iy * scale);
  }

  /// Extracts contour points from face and maps to display coordinates.
  List<Offset>? _contourToDisplay(Face? face, FaceContourType type, double width, double height, Size? imageSize, double scale, double offsetY) {
    if (face == null || imageSize == null) return null;
    final contour = face.contours[type];
    if (contour == null || contour.points.isEmpty) return null;
    return contour.points.map((p) => _imageToDisplay(p.x.toDouble(), p.y.toDouble(), scale, offsetY)).toList();
  }

  /// Builds synthetic contour points from a face bounding box (for TFLite / Windows).
  void _syntheticContoursFromRect(
    Rect displayRect,
    List<Offset> faceContour,
    List<Offset> leftBrowTop,
    List<Offset> leftBrowBottom,
    List<Offset> rightBrowTop,
    List<Offset> rightBrowBottom,
    List<Offset> upperLipTop,
    List<Offset> upperLipBottom,
    List<Offset> lowerLipTop,
    List<Offset> lowerLipBottom,
  ) {
    final cx = displayRect.center.dx;
    final cy = displayRect.center.dy;
    final rx = displayRect.width / 2;
    final ry = displayRect.height / 2;
    const n = 24;
    for (var i = 0; i <= n; i++) {
      final t = (i / n) * 2 * pi;
      faceContour.add(Offset(cx + rx * cos(t), cy + ry * sin(t)));
    }
    final browY = displayRect.top + displayRect.height * 0.22;
    final browW = displayRect.width * 0.2;
    final browH = displayRect.height * 0.04;
    leftBrowTop.addAll([
      Offset(cx - browW * 1.2, browY),
      Offset(cx - browW * 0.4, browY - browH),
    ]);
    leftBrowBottom.addAll([
      Offset(cx - browW * 0.4, browY - browH),
      Offset(cx - browW * 1.2, browY),
    ]);
    rightBrowTop.addAll([
      Offset(cx + browW * 0.4, browY - browH),
      Offset(cx + browW * 1.2, browY),
    ]);
    rightBrowBottom.addAll([
      Offset(cx + browW * 1.2, browY),
      Offset(cx + browW * 0.4, browY - browH),
    ]);
    final lipY = displayRect.top + displayRect.height * 0.62;
    final lipW = displayRect.width * 0.25;
    final lipH = displayRect.height * 0.08;
    upperLipTop.addAll([
      Offset(cx - lipW, lipY),
      Offset(cx, lipY - lipH),
      Offset(cx + lipW, lipY),
    ]);
    upperLipBottom.addAll([
      Offset(cx + lipW, lipY),
      Offset(cx, lipY + lipH * 0.5),
      Offset(cx - lipW, lipY),
    ]);
    lowerLipTop.addAll([
      Offset(cx - lipW, lipY),
      Offset(cx, lipY + lipH * 0.5),
      Offset(cx + lipW, lipY),
    ]);
    lowerLipBottom.addAll([
      Offset(cx + lipW, lipY),
      Offset(cx, lipY + lipH),
      Offset(cx - lipW, lipY),
    ]);
  }

  Widget _buildOverlayHints() {
    final controller = _cameraController;
    final previewSize = controller?.value.previewSize;
    final face = _detectedFace;
    final imageSize = _detectedImageSize ?? _tfliteImageSize ?? previewSize;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        double scale = 1;
        double offsetY = 0;

        if (imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
          scale = min(width / imageSize.width, height / imageSize.height);
          final previewH = imageSize.height * scale;
          offsetY = (height - previewH) / 2;
        }

        List<Offset>? faceContour;
        List<Offset>? leftBrowTop;
        List<Offset>? leftBrowBottom;
        List<Offset>? rightBrowTop;
        List<Offset>? rightBrowBottom;
        List<Offset>? upperLipTop;
        List<Offset>? upperLipBottom;
        List<Offset>? lowerLipTop;
        List<Offset>? lowerLipBottom;
        Rect? faceBoundsDisplay;
        bool hasFace = false;

        if (face != null && imageSize != null) {
          hasFace = true;
          faceContour = _contourToDisplay(face, FaceContourType.face, width, height, imageSize, scale, offsetY);
          leftBrowTop = _contourToDisplay(face, FaceContourType.leftEyebrowTop, width, height, imageSize, scale, offsetY);
          leftBrowBottom = _contourToDisplay(face, FaceContourType.leftEyebrowBottom, width, height, imageSize, scale, offsetY);
          rightBrowTop = _contourToDisplay(face, FaceContourType.rightEyebrowTop, width, height, imageSize, scale, offsetY);
          rightBrowBottom = _contourToDisplay(face, FaceContourType.rightEyebrowBottom, width, height, imageSize, scale, offsetY);
          upperLipTop = _contourToDisplay(face, FaceContourType.upperLipTop, width, height, imageSize, scale, offsetY);
          upperLipBottom = _contourToDisplay(face, FaceContourType.upperLipBottom, width, height, imageSize, scale, offsetY);
          lowerLipTop = _contourToDisplay(face, FaceContourType.lowerLipTop, width, height, imageSize, scale, offsetY);
          lowerLipBottom = _contourToDisplay(face, FaceContourType.lowerLipBottom, width, height, imageSize, scale, offsetY);
          faceBoundsDisplay = _rectToDisplay(_toRect(face.boundingBox), width, height, imageSize, scale, offsetY);
        } else if (_tfliteFaceRect != null && imageSize != null) {
          hasFace = true;
          faceBoundsDisplay = _rectToDisplay(_tfliteFaceRect!, width, height, imageSize, scale, offsetY);
          faceContour = [];
          leftBrowTop = [];
          leftBrowBottom = [];
          rightBrowTop = [];
          rightBrowBottom = [];
          upperLipTop = [];
          upperLipBottom = [];
          lowerLipTop = [];
          lowerLipBottom = [];
          _syntheticContoursFromRect(
            faceBoundsDisplay,
            faceContour,
            leftBrowTop,
            leftBrowBottom,
            rightBrowTop,
            rightBrowBottom,
            upperLipTop,
            upperLipBottom,
            lowerLipTop,
            lowerLipBottom,
          );
        }

        return IgnorePointer(
          child: CustomPaint(
            painter: _MakeupOverlayPainter(
              faceContourDisplay: faceContour,
              leftBrowTop: leftBrowTop,
              leftBrowBottom: leftBrowBottom,
              rightBrowTop: rightBrowTop,
              rightBrowBottom: rightBrowBottom,
              upperLipTop: upperLipTop,
              upperLipBottom: upperLipBottom,
              lowerLipTop: lowerLipTop,
              lowerLipBottom: lowerLipBottom,
              faceBoundsDisplay: faceBoundsDisplay,
              foundationColor: hasFace ? _foundationColor : null,
              lipstickColor: hasFace ? _lipstickColor : null,
              eyebrowColor: hasFace ? _eyebrowColor : null,
            ),
          ),
        );
      },
    );
  }

  Rect _rectToDisplay(Rect r, double width, double height, Size imageSize, double scale, double offsetY) {
    return Rect.fromLTRB(
      r.left * scale,
      offsetY + r.top * scale,
      r.right * scale,
      offsetY + r.bottom * scale,
    );
  }

  Rect _toRect(dynamic box) {
    if (box is Rect) return box;
    try {
      final left = (box.left as num).toDouble();
      final top = (box.top as num).toDouble();
      final right = (box.right as num).toDouble();
      final bottom = (box.bottom as num).toDouble();
      return Rect.fromLTRB(left, top, right, bottom);
    } catch (_) {
      return Rect.zero;
    }
  }

  Widget _buildSelectedSummaryChip(ThemeData theme) {
    final List<String> parts = [];

    if (_selectedFoundationProduct != null) {
      parts.add('Foundation: ${_selectedFoundationProduct!.brand ?? ''} ${_selectedFoundationProduct!.name}');
    }
    if (_selectedLipstickProduct != null) {
      parts.add('Lipstick: ${_selectedLipstickProduct!.brand ?? ''} ${_selectedLipstickProduct!.name}');
    }
    if (_selectedEyebrowProduct != null) {
      parts.add('Eyebrow: ${_selectedEyebrowProduct!.brand ?? ''} ${_selectedEyebrowProduct!.name}');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withAlpha((0.9 * 255).round()),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          parts.join('  •  '),
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildBottomPanel(ThemeData theme) {
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_productError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_productError!),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loadProducts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.06 * 255).round()),
            blurRadius: 12,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 8),
          _buildStepHeader(theme),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildProductListForCurrentStep(theme),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 1,
                  child: _buildTutorialPanel(theme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader(ThemeData theme) {
    String title;
    String subtitle;

    switch (_currentStep) {
      case MakeupStep.foundation:
        title = 'Step 1 · Foundation';
        subtitle = 'Pick your base shade. We will overlay it on your skin.';
        break;
      case MakeupStep.settingSpray:
        title = 'Step 2 · Setting Spray';
        subtitle = 'Lock in your base for long lasting wear.';
        break;
      case MakeupStep.eyebrow:
        title = 'Step 3 · Eyebrow';
        subtitle = 'Shape and fill brows to frame your face.';
        break;
      case MakeupStep.eyeshadow:
        title = 'Step 4 · Eyeshadow';
        subtitle = 'Add depth and dimension to your eyes.';
        break;
      case MakeupStep.lipstick:
        title = 'Step 5 · Lipstick';
        subtitle = 'Finish with a lip colour that matches your look.';
        break;
    }

    return ListTile(
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: FilledButton.icon(
        onPressed: _goToNextStep,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Next'),
      ),
    );
  }

  Widget _buildProductListForCurrentStep(ThemeData theme) {
    List<MakeupProduct> products;

    switch (_currentStep) {
      case MakeupStep.foundation:
        products = _foundationProducts;
        break;
      case MakeupStep.lipstick:
        products = _lipstickProducts;
        break;
      case MakeupStep.eyebrow:
        products = _eyebrowProducts;
        break;
      case MakeupStep.settingSpray:
      case MakeupStep.eyeshadow:
        products = _foundationProducts;
        break;
    }

    if (products.isEmpty) {
      return const Center(
        child: Text('No products found for this step.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      scrollDirection: Axis.horizontal,
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _MakeupProductCard(
          product: product,
          isSelected: product == _selectedFoundationProduct ||
              product == _selectedLipstickProduct ||
              product == _selectedEyebrowProduct,
          onSelect: (color) => _onSelectProduct(product, color),
        );
      },
    );
  }

  Widget _buildTutorialPanel(ThemeData theme) {
    final animationValue = _tutorialController.value;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step-by-step guide',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                _TutorialStepTile(
                  index: 1,
                  title: 'Apply foundation',
                  description:
                      'Start from the center of the face and blend outwards using a damp sponge or brush.',
                  isActive: _currentStep == MakeupStep.foundation,
                  progress: _currentStep == MakeupStep.foundation
                      ? animationValue
                      : (_currentStep.index > MakeupStep.foundation.index
                          ? 1
                          : 0),
                ),
                _TutorialStepTile(
                  index: 2,
                  title: 'Setting spray / powder',
                  description:
                      'Lightly mist or press powder on T-zone and under eyes to fix the base.',
                  isActive: _currentStep == MakeupStep.settingSpray,
                  progress: _currentStep == MakeupStep.settingSpray
                      ? animationValue
                      : (_currentStep.index > MakeupStep.settingSpray.index
                          ? 1
                          : 0),
                ),
                _TutorialStepTile(
                  index: 3,
                  title: 'Eyebrow definition',
                  description:
                      'Outline the lower edge of the brow, then fill in sparse areas with short strokes.',
                  isActive: _currentStep == MakeupStep.eyebrow,
                  progress: _currentStep == MakeupStep.eyebrow
                      ? animationValue
                      : (_currentStep.index > MakeupStep.eyebrow.index
                          ? 1
                          : 0),
                ),
                _TutorialStepTile(
                  index: 4,
                  title: 'Eyeshadow (optional)',
                  description:
                      'Sweep a light shade over the lid, add medium shade in the crease, and deepen the outer corner.',
                  isActive: _currentStep == MakeupStep.eyeshadow,
                  progress: _currentStep == MakeupStep.eyeshadow
                      ? animationValue
                      : (_currentStep.index > MakeupStep.eyeshadow.index
                          ? 1
                          : 0),
                ),
                _TutorialStepTile(
                  index: 5,
                  title: 'Lipstick',
                  description:
                      'Outline the lips, then fill in towards the center. Blot and reapply for intensity.',
                  isActive: _currentStep == MakeupStep.lipstick,
                  progress: _currentStep == MakeupStep.lipstick
                      ? animationValue
                      : (_currentStep.index > MakeupStep.lipstick.index
                          ? 1
                          : 0),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: you can change any colour anytime and see it instantly on your live camera preview.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MakeupOverlayPainter extends CustomPainter {
  final List<Offset>? faceContourDisplay;
  final List<Offset>? leftBrowTop;
  final List<Offset>? leftBrowBottom;
  final List<Offset>? rightBrowTop;
  final List<Offset>? rightBrowBottom;
  final List<Offset>? upperLipTop;
  final List<Offset>? upperLipBottom;
  final List<Offset>? lowerLipTop;
  final List<Offset>? lowerLipBottom;
  final Rect? faceBoundsDisplay;
  final Color? foundationColor;
  final Color? lipstickColor;
  final Color? eyebrowColor;

  _MakeupOverlayPainter({
    this.faceContourDisplay,
    this.leftBrowTop,
    this.leftBrowBottom,
    this.rightBrowTop,
    this.rightBrowBottom,
    this.upperLipTop,
    this.upperLipBottom,
    this.lowerLipTop,
    this.lowerLipBottom,
    this.faceBoundsDisplay,
    this.foundationColor,
    this.lipstickColor,
    this.eyebrowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Foundation: only on detected face, using face contour or fallback to face bounds
    if (foundationColor != null) {
      final paint = Paint()
        ..color = foundationColor!.withAlpha((0.35 * 255).round())
        ..style = PaintingStyle.fill;
      if (faceContourDisplay != null && faceContourDisplay!.length >= 3) {
        final path = Path()..moveTo(faceContourDisplay!.first.dx, faceContourDisplay!.first.dy);
        for (var i = 1; i < faceContourDisplay!.length; i++) {
          path.lineTo(faceContourDisplay![i].dx, faceContourDisplay![i].dy);
        }
        path.close();
        canvas.drawPath(path, paint);
      } else if (faceBoundsDisplay != null) {
        canvas.drawOval(faceBoundsDisplay!, paint);
      }
    }

    // Eyebrows: only on detected face, filled along real eyebrow contours so colour fits the brow
    if (eyebrowColor != null) {
      final paint = Paint()
        ..color = eyebrowColor!.withAlpha((0.92 * 255).round())
        ..style = PaintingStyle.fill;
      paint.isAntiAlias = true;
      void drawBrow(List<Offset>? top, List<Offset>? bottom) {
        final pts = <Offset>[];
        if (top != null && top.isNotEmpty) pts.addAll(top);
        if (bottom != null && bottom.isNotEmpty) {
          pts.addAll(bottom.reversed);
        }
        if (pts.length < 3) return;
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (var i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        path.close();
        canvas.drawPath(path, paint);
      }
      drawBrow(leftBrowTop, leftBrowBottom);
      drawBrow(rightBrowTop, rightBrowBottom);
    }

    // Lips: only on detected face, using lip contours
    if (lipstickColor != null && (upperLipTop != null || upperLipBottom != null || lowerLipTop != null || lowerLipBottom != null)) {
      final path = Path();
      final all = <Offset>[];
      if (upperLipTop != null) all.addAll(upperLipTop!);
      if (upperLipBottom != null) all.addAll(upperLipBottom!);
      if (lowerLipBottom != null) all.addAll(lowerLipBottom!.reversed);
      if (lowerLipTop != null) all.addAll(lowerLipTop!.reversed);
      if (all.length >= 3) {
        path.moveTo(all.first.dx, all.first.dy);
        for (var i = 1; i < all.length; i++) {
          path.lineTo(all[i].dx, all[i].dy);
        }
        path.close();
        canvas.drawPath(
          path,
          Paint()
            ..color = lipstickColor!.withAlpha((0.85 * 255).round())
            ..style = PaintingStyle.fill
            ,
        );
        // ensure anti-aliasing on the paint used for lips
        // (create and set below to avoid using unsupported `antiAlias` setter)
        final lipPaint = Paint()
          ..color = lipstickColor!.withAlpha((0.85 * 255).round())
          ..style = PaintingStyle.fill;
        lipPaint.isAntiAlias = true;
        canvas.drawPath(path, lipPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MakeupOverlayPainter oldDelegate) {
    return oldDelegate.foundationColor != foundationColor ||
        oldDelegate.lipstickColor != lipstickColor ||
        oldDelegate.eyebrowColor != eyebrowColor ||
        oldDelegate.faceContourDisplay != faceContourDisplay ||
        oldDelegate.faceBoundsDisplay != faceBoundsDisplay ||
        oldDelegate.leftBrowTop != leftBrowTop ||
        oldDelegate.rightBrowTop != rightBrowTop ||
        oldDelegate.upperLipTop != upperLipTop ||
        oldDelegate.lowerLipTop != lowerLipTop;
  }
}

class _MakeupProductCard extends StatelessWidget {
  final MakeupProduct product;
  final bool isSelected;
  final void Function(MakeupColorOption? color) onSelect;

  const _MakeupProductCard({
    required this.product,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hasColors = product.colors.isNotEmpty;

    return Container(
      width: 220,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        elevation: isSelected ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onSelect(hasColors ? product.colors.first : null),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: product.imageUrl.isEmpty
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.image_not_supported_outlined),
                            ),
                          )
                        : Image.network(
                            product.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product.brand ?? 'Unknown brand',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  product.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (hasColors)
                  SizedBox(
                    height: 28,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: product.colors.length.clamp(0, 6),
                      separatorBuilder: (_, __) => const SizedBox(width: 4),
                      itemBuilder: (context, index) {
                        final colorOption = product.colors[index];
                        final color = _parseHex(colorOption.hexValue);
                        return GestureDetector(
                          onTap: () => onSelect(colorOption),
                          child: Tooltip(
                            message: colorOption.name,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: color ??
                                  theme.colorScheme.surfaceContainerHighest,
                              child: color == null
                                  ? const Icon(
                                      Icons.color_lens,
                                      size: 14,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (!hasColors)
                  Text(
                    'No colour options listed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color? _parseHex(String hex) {
    var cleaned = hex.toUpperCase().replaceAll('#', '');
    if (cleaned.length == 3) {
      cleaned = cleaned.split('').map((c) => '$c$c').join();
    }
    if (cleaned.length == 6) {
      cleaned = 'FF$cleaned';
    }
    if (cleaned.length != 8) return null;
    try {
      return Color(int.parse(cleaned, radix: 16));
    } catch (_) {
      return null;
    }
  }
}

class _TutorialStepTile extends StatelessWidget {
  final int index;
  final String title;
  final String description;
  final bool isActive;
  final double progress;

  const _TutorialStepTile({
    required this.index,
    required this.title,
    required this.description,
    required this.isActive,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: isActive
                    ? activeColor
                    : (progress >= 1 ? activeColor : inactiveColor),
                child: Text(
                  '$index',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (index < 5)
                Container(
                  width: 2,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        activeColor.withAlpha((progress.clamp(0, 1) * 255).round()),
                        inactiveColor,
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive
                    ? activeColor.withAlpha((0.07 * 255).round())
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive ? activeColor : inactiveColor,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

