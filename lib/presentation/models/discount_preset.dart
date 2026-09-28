import 'dart:convert';

/// Representation of a quick discount preset configured by Admin
class DiscountPreset {
  final String id;
  final String label;
  final double percent;
  final bool isSystem;

  const DiscountPreset({
    required this.id,
    required this.label,
    required this.percent,
    this.isSystem = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'percent': percent,
        'isSystem': isSystem,
      };

  factory DiscountPreset.fromJson(Map<String, dynamic> json) {
    return DiscountPreset(
      id: json['id'] as String? ?? 'preset_${DateTime.now().millisecondsSinceEpoch}',
      label: json['label'] as String? ?? 'Discount',
      percent: (json['percent'] as num?)?.toDouble() ?? 0.0,
      isSystem: json['isSystem'] as bool? ?? false,
    );
  }

  static String encodeList(List<DiscountPreset> list) {
    return jsonEncode(list.map((p) => p.toJson()).toList());
  }

  static List<DiscountPreset> decodeList(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .map((item) => DiscountPreset.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
