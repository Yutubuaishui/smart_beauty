import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

import '../models/makeup_product.dart';
import 'makeup_api_service.dart';

/// Estimates skin tone from a face region and recommends makeup products by colour match.
class CosmeticRecommenderService {
  final MakeupApiService _api = MakeupApiService();

  /// Estimates skin tone from decoded image bytes and face rect.
  /// Returns dominant skin colour as hex (e.g. "#C4A484").
  String? getSkinToneFromImageBytes(Uint8List imageBytes, Rect faceRect) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // Sample from the centre-upper region of the face (avoids hair and chin)
      final cx = (faceRect.left + faceRect.width * 0.25).round();
      final cy = (faceRect.top + faceRect.height * 0.3).round();
      final w = (faceRect.width * 0.6).round().clamp(1, image.width);
      final h = (faceRect.height * 0.5).round().clamp(1, image.height);

      int rSum = 0, gSum = 0, bSum = 0;
      int count = 0;
      const step = 4;
      for (int dy = 0; dy < h; dy += step) {
        for (int dx = 0; dx < w; dx += step) {
          final px = (cx + dx).clamp(0, image.width - 1);
          final py = (cy + dy).clamp(0, image.height - 1);
          final pixel = image.getPixel(px, py);
          rSum += pixel.r.toInt();
          gSum += pixel.g.toInt();
          bSum += pixel.b.toInt();
          count++;
        }
      }
      if (count == 0) return null;
      final r = (rSum / count).round().clamp(0, 255);
      final g = (gSum / count).round().clamp(0, 255);
      final b = (bSum / count).round().clamp(0, 255);
      return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  static double _colorDistance(String hex1, String hex2) {
    final c1 = _hexToRgb(hex1);
    final c2 = _hexToRgb(hex2);
    if (c1 == null || c2 == null) return double.infinity;
    return sqrt(
      pow(c1.$1 - c2.$1, 2) + pow(c1.$2 - c2.$2, 2) + pow(c1.$3 - c2.$3, 2),
    );
  }

  static (int, int, int)? _hexToRgb(String hex) {
    final h = hex.replaceAll('#', '').toUpperCase();
    if (h.length == 6) {
      final r = int.tryParse(h.substring(0, 2), radix: 16);
      final g = int.tryParse(h.substring(2, 4), radix: 16);
      final b = int.tryParse(h.substring(4, 6), radix: 16);
      if (r != null && g != null && b != null) return (r, g, b);
    }
    return null;
  }

  /// Foundation: match colour closest to detected skin tone.
  Future<List<({MakeupProduct product, MakeupColorOption color})>>
      recommendFoundation(
    String skinToneHex, {
    int limit = 5,
  }) async {
    // API type = "foundation"
    final list = await _api.fetchProductsByType('foundation');
    return _recommendByColor(list, skinToneHex, limit: limit);
  }

  /// Lipstick: complement or match skin tone.
  Future<List<({MakeupProduct product, MakeupColorOption color})>>
      recommendLipstick(
    String? skinToneHex, {
    int limit = 5,
  }) async {
    // API type = "lipstick"
    final list = await _api.fetchProductsByType('lipstick');
    final target = skinToneHex ?? '#8B4513';
    return _recommendByColor(list, target, limit: limit);
  }

  /// Eyebrow: neutral browns that suit most skin tones.
  Future<List<({MakeupProduct product, MakeupColorOption color})>>
      recommendEyebrow(
    String? skinToneHex, {
    int limit = 5,
  }) async {
    // API type = "eyebrow"
    final list = await _api.fetchProductsByType('eyebrow');
    if (list.isEmpty) return [];
    final target = skinToneHex ?? '#5C4033';
    return _recommendByColor(list, target, limit: limit);
  }

  /// Eyeshadow: recommend palettes/shadows close to a complementary tone.
  Future<List<({MakeupProduct product, MakeupColorOption color})>>
      recommendEyeshadow(
    String? skinToneHex, {
    int limit = 5,
  }) async {
    // API type = "eyeshadow"  (was 'palette' — fixed)
    final list = await _api.fetchProductsByType('eyeshadow');
    if (list.isEmpty) return [];
    final target = skinToneHex ?? '#8B6F47';
    return _recommendByColor(list, target, limit: limit);
  }

  /// Setting/face powder: no colour overlay but fetch correct product type.
  Future<List<MakeupProduct>> fetchSettingPowder() async {
    // API type = "powder"  (was 'setting powder' — fixed)
    return _api.fetchProductsByType('powder');
  }

  List<({MakeupProduct product, MakeupColorOption color})>
      _recommendByColor(
    List<MakeupProduct> products,
    String targetHex, {
    required int limit,
  }) {
    final withDistance =
        <({MakeupProduct product, MakeupColorOption color, double distance})>[];
    for (final p in products) {
      for (final c in p.colors) {
        if (c.hexValue.isEmpty) continue;
        final d = _colorDistance(c.hexValue, targetHex);
        withDistance.add((product: p, color: c, distance: d));
      }
    }
    withDistance.sort((a, b) => a.distance.compareTo(b.distance));
    return withDistance
        .take(limit)
        .map((e) => (product: e.product, color: e.color))
        .toList();
  }
}