/// Every backend path in one place. Paths are relative to
/// `AppConfig.apiBaseUrl` — never include the host here.
///
/// Every constant must start with `/` and `apiBaseUrl` must not end with
/// one: Dio concatenates the two, so a trailing slash on the base would
/// double up and a missing leading slash would glue two segments together.
class ApiEndpoints {
  const ApiEndpoints._();

  // Auth
  static const String signup = '/auth/signup';
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String refresh = '/auth/refresh';
  static const String me = '/auth/me';
  static const String checkAvailability = '/auth/check-availability';

  // Profile
  static const String profile = '/users/me';
  static const String avatar = '/users/me/avatar';

  // Reserved for later phases — listed so the surface area is visible.
  // NOTE: none of these are mounted on the backend yet; calling one now
  // returns 404.
  static const String fitnessProfile = '/users/me/fitness-profile';
  static const String workouts = '/workouts';
  static const String activities = '/activities';
  static const String enrolments = '/users/me/enrolments';
  static const String community = '/community/posts';
  static const String subscriptions = '/subscriptions';
}
