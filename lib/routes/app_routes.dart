/// Named route table. Import this rather than typing route strings.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String onboarding = '/onboarding';
  static const String accountDetails = '/signup/account-details';
  static const String login = '/login';
  static const String home = '/home';
  static const String exerciseLibrary = '/training/exercises';
  static const String exerciseDetail = '/training/exercise';
  static const String trainingEquipment = '/training/equipment';
  static const String activityDetail = '/tracking/activity';
}

class ExerciseLibraryArguments {
  const ExerciseLibraryArguments({
    this.initialMuscleId,
    this.initialMuscleGroup,
    this.initialEquipmentId,
    this.initialAvailableEquipment = false,
  });

  final String? initialMuscleId;
  final String? initialMuscleGroup;
  final String? initialEquipmentId;
  final bool initialAvailableEquipment;
}
