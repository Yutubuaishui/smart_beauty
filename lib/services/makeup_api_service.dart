import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/makeup_product.dart';

class MakeupApiService {
  static const String _baseUrl =
      'https://makeup-api.herokuapp.com/api/v1/products.json';

  /// Valid product_type values accepted by the Makeup API:
  /// blush, bronzer, eyebrow, eyeliner, eyeshadow, foundation,
  /// lip_liner, lipstick, mascara, nail_polish, powder (setting/face powder)
  Future<List<MakeupProduct>> fetchProductsByType(String productType) async {
    final uri = Uri.parse('$_baseUrl?product_type=$productType');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to load makeup products (${response.statusCode})');
    }

    final decoded = json.decode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected response format from Makeup API');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(MakeupProduct.fromJson)
        .toList();
  }
}