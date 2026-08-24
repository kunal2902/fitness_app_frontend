part of 'professionals_bloc.dart';

class ProfessionalsState extends Equatable {
  const ProfessionalsState({
    this.professionals = const <Professional>[],
    this.selected,
    this.isLoading = false,
    this.isLoadingDetail = false,
    this.errorMessage,
  });

  final List<Professional> professionals;

  /// The coach whose detail screen is open, with the full portfolio. The
  /// list version carries the same fields, but this is refetched so a
  /// portfolio edited server-side shows up without reloading the list.
  final Professional? selected;

  final bool isLoading;
  final bool isLoadingDetail;
  final String? errorMessage;

  bool get isEmpty => !isLoading && professionals.isEmpty;
  int get onlineCount =>
      professionals.where((Professional p) => p.isOnline).length;

  ProfessionalsState copyWith({
    List<Professional>? professionals,
    Professional? selected,
    bool? isLoading,
    bool? isLoadingDetail,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProfessionalsState(
      professionals: professionals ?? this.professionals,
      selected: selected ?? this.selected,
      isLoading: isLoading ?? this.isLoading,
      isLoadingDetail: isLoadingDetail ?? this.isLoadingDetail,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        professionals,
        selected,
        isLoading,
        isLoadingDetail,
        errorMessage,
      ];
}
