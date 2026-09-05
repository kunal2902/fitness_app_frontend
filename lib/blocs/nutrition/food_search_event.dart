part of 'food_search_bloc.dart';

sealed class FoodSearchEvent extends Equatable {
  const FoodSearchEvent();
}

/// Also use this with the current query to retry a failed search.
final class FoodSearchChanged extends FoodSearchEvent {
  const FoodSearchChanged(this.query);
  final String query;
  @override
  List<Object?> get props => <Object?>[query];
}
