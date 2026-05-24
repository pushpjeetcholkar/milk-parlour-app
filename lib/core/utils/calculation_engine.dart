class CalculationEngine {
  /// KG FAT = (Quantity × FAT) / 100
  static double calculateKgFat({
    required double quantity,
    required double fat,
  }) {
    final result = (quantity * fat) / 100.0;
    return double.parse(result.toStringAsFixed(4));
  }

  /// Amount = Quantity × FAT × Rate
  static double calculateAmount({
    required double quantity,
    required double fat,
    required double rate,
  }) {
    final result = quantity * fat * rate;
    return double.parse(result.toStringAsFixed(2));
  }
}
