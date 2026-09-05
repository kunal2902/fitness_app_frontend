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

  // Assistance — coaches, chat and calls
  static const String professionals = '/professionals';
  static String professional(String id) => '/professionals/$id';
  static String professionalConversation(String id) =>
      '/professionals/$id/conversation';

  static const String conversations = '/conversations';
  static String conversationMessages(String id) =>
      '/conversations/$id/messages';
  static String conversationRead(String id) => '/conversations/$id/read';

  static const String iceServers = '/calls/ice-servers';
  static const String callHistory = '/calls/history';
  static String endCall(String callId) => '/calls/$callId/end';

  static const String devices = '/devices';
  static String device(String token) => '/devices/$token';

  // Nutrition — food reference data and the meal diary
  static const String foodSearch = '/foods/search';

  /// Accepts either a Mongo id or a stable `externalId` such as
  /// `ifct:A011`. Both resolve server-side, which is what lets a bundled
  /// local corpus and the API be swapped without touching call sites.
  static String food(String idOrExternalId) => '/foods/$idOrExternalId';

  static const String nutritionLogs = '/nutrition/logs';
  static String nutritionLog(String id) => '/nutrition/logs/$id';
  static const String nutritionSummary = '/nutrition/summary';
  static const String nutritionTargets = '/nutrition/targets';
  static const String nutritionRecommendation =
      '/nutrition/targets/recommendation';

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
