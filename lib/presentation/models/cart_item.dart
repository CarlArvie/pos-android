import '../../data/local/database.dart';

class CartItem {
  final Product product;
  double quantity;
  double unitPrice;
  double discount;

  CartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0.0,
  });

  bool get isFractional => product.sellBy == 'fraction';

  double get rawTotal => quantity * unitPrice;

  double get netSubtotal => (rawTotal - discount).clamp(0.0, double.infinity);

  double get taxAmount {
    if (product.taxPercent <= 0) return 0.0;
    return netSubtotal * (product.taxPercent / 100.0);
  }

  double get lineTotal => netSubtotal + taxAmount;

  String get formattedQuantity {
    if (isFractional) {
      return '${quantity.toStringAsFixed(3)} ${product.unit}';
    }
    return '${quantity.toStringAsFixed(0)} ${product.unit}';
  }
}
