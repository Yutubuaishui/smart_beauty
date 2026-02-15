class MakeupColorOption {
  final String hexValue;
  final String name;

  const MakeupColorOption({
    required this.hexValue,
    required this.name,
  });
}

class MakeupProduct {
  final int id;
  final String? brand;
  final String name;
  final String? description;
  final String imageUrl;
  final String productType;
  final String? category;
  final String? price;
  final String? priceSign;
  final String? currency;
  final List<MakeupColorOption> colors;

  const MakeupProduct({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.productType,
    this.brand,
    this.description,
    this.category,
    this.price,
    this.priceSign,
    this.currency,
    this.colors = const [],
  });

  factory MakeupProduct.fromJson(Map<String, dynamic> json) {
    final colorsJson = json['product_colors'] as List<dynamic>? ?? [];
    return MakeupProduct(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      brand: (json['brand'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['brand'] as String).trim(),
      name: (json['name'] as String?) ?? 'Unknown',
      description: json['description'] as String?,
      imageUrl: (json['image_link'] as String?) ?? '',
      productType: (json['product_type'] as String?) ?? '',
      category: json['category'] as String?,
      price: json['price'] as String?,
      priceSign: json['price_sign'] as String?,
      currency: json['currency'] as String?,
      colors: colorsJson
          .whereType<Map<String, dynamic>>()
          .map(
            (c) => MakeupColorOption(
              hexValue: (c['hex_value'] as String?) ?? '#000000',
              name: (c['colour_name'] as String?) ?? '',
            ),
          )
          .toList(),
    );
  }
}

