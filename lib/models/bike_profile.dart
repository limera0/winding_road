class BikeProfile {
  final String id;
  final String brand;
  final String model;
  final int displacement; // cc
  final int year;

  const BikeProfile({
    required this.id,
    required this.brand,
    required this.model,
    required this.displacement,
    required this.year,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'brand': brand,
        'model': model,
        'displacement': displacement,
        'year': year,
      };

  factory BikeProfile.fromJson(Map<String, dynamic> j) => BikeProfile(
        id: j['id'] as String,
        brand: j['brand'] as String,
        model: j['model'] as String,
        displacement: j['displacement'] as int,
        year: j['year'] as int,
      );

  BikeProfile copyWith({
    String? id,
    String? brand,
    String? model,
    int? displacement,
    int? year,
  }) =>
      BikeProfile(
        id: id ?? this.id,
        brand: brand ?? this.brand,
        model: model ?? this.model,
        displacement: displacement ?? this.displacement,
        year: year ?? this.year,
      );

  String get label => '$brand $model (${displacement}cc, $year)';
}
