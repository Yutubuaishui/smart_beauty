class Product {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final double price;
  final double? rating;
  final String category;
  final List<String> ingredients;
  final String? brand;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.price,
    this.rating,
    required this.category,
    this.ingredients = const [],
    this.brand,
  });
}
