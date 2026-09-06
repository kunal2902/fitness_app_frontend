import 'package:equatable/equatable.dart';

import '../utils/nutrition_math.dart';
import 'food_log.dart';
import 'nutrition_models.dart';

/// A reusable, private meal template captured from one diary meal slot.
class SavedMeal extends Equatable {
  const SavedMeal({
    required this.id,
    required this.name,
    required this.defaultMealType,
    required this.items,
    required this.totals,
    required this.useCount,
    this.lastUsedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final MealType? defaultMealType;
  final List<FoodLogItem> items;
  final Macros totals;
  final int useCount;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get itemSummary {
    final List<String> names = items
        .map((FoodLogItem item) => item.name)
        .where((String name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) {
      return '${items.length} food${items.length == 1 ? '' : 's'}';
    }
    if (names.length <= 2) return names.join(' · ');
    return '${names.take(2).join(' · ')} +${names.length - 2} more';
  }

  factory SavedMeal.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    final List<FoodLogItem> items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(FoodLogItem.fromJson)
            .toList()
        : const <FoodLogItem>[];
    final Object? rawTotals = json['totals'];
    return SavedMeal(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      defaultMealType: MealType.fromApi(json['defaultMealType'] as String?),
      items: List<FoodLogItem>.unmodifiable(items),
      totals: rawTotals is Map<String, dynamic>
          ? Macros.fromJson(rawTotals)
          : NutritionMath.sumMacros(
              items.map((FoodLogItem item) => item.macros),
            ),
      useCount: (json['useCount'] as num?)?.toInt() ?? 0,
      lastUsedAt: DateTime.tryParse((json['lastUsedAt'] ?? '').toString()),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        defaultMealType,
        items,
        totals,
        useCount,
        lastUsedAt,
        updatedAt,
      ];
}
