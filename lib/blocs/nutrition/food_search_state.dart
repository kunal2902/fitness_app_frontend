part of 'food_search_bloc.dart';

enum FoodSearchStatus { initial, debouncing, loading, success, failure }

class FoodSearchState extends Equatable {
  const FoodSearchState({
    this.query = '',
    this.foods = const <Food>[],
    this.status = FoodSearchStatus.initial,
    this.error,
    this.catalogueEmpty = false,
    this.globalLookupUnavailable = false,
  });
  final String query;
  final List<Food> foods;
  final FoodSearchStatus status;
  final ApiException? error;

  /// No food data has been imported at all, so nothing could ever match.
  /// Distinct from [isEmpty], which means this particular word missed.
  final bool catalogueEmpty;

  /// The server was healthy enough to answer, but global catalogue
  /// expansion was disabled or temporarily unreachable.
  final bool globalLookupUnavailable;
  bool get isLoading =>
      status == FoodSearchStatus.debouncing ||
      status == FoodSearchStatus.loading;
  bool get isEmpty => status == FoodSearchStatus.success && foods.isEmpty;

  @override
  List<Object?> get props => <Object?>[
        query,
        foods,
        status,
        error,
        catalogueEmpty,
        globalLookupUnavailable,
      ];
}
