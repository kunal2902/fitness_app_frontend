import '../config/api_endpoints.dart';
import '../models/api_exception.dart';
import '../models/auth_models.dart';
import '../models/json_coercion.dart';
import '../models/user_model.dart';
import 'api_client.dart';

/// All auth network calls. Pure I/O — no state, no storage. The BLoC owns
/// what happens with the result.
class AuthService {
  AuthService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// Creates the account and the fitness profile in one request.
  Future<AuthSession> signup(SignupRequest request) async {
    final Map<String, dynamic> json = await _client.post(
      ApiEndpoints.signup,
      body: request.toJson(),
      skipAuth: true,
    );
    return _session(json);
  }

  Future<AuthSession> login(LoginRequest request) async {
    final Map<String, dynamic> json = await _client.post(
      ApiEndpoints.login,
      body: request.toJson(),
      skipAuth: true,
    );
    return _session(json);
  }

  /// A 2xx that does not carry a usable session is a failure, not a sign-in.
  ///
  /// This is the boundary where "the server answered" becomes "the user is
  /// signed in", and the only place that can refuse the difference. Letting
  /// an empty token through puts the app into a state no screen can get out
  /// of: authenticated as far as the router is concerned, anonymous as far
  /// as the server is concerned. Raised as an ordinary [ApiException] so the
  /// form reports it and the user can simply try again.
  AuthSession _session(Map<String, dynamic> json) {
    final AuthSession session = AuthSession.fromJson(json);
    if (!session.isUsable) {
      throw const ApiException(
        message: 'Sign-in did not complete. Please try again.',
        code: 'MALFORMED_SESSION',
      );
    }
    return session;
  }

  /// Live check while the user types on the account details screen.
  Future<AvailabilityResult> checkAvailability({
    String? username,
    String? email,
  }) async {
    final Map<String, dynamic> query = <String, dynamic>{};
    if (username != null && username.isNotEmpty) query['username'] = username;
    if (email != null && email.isNotEmpty) query['email'] = email;

    final Map<String, dynamic> json = await _client.get(
      ApiEndpoints.checkAvailability,
      query: query,
      skipAuth: true,
    );
    return AvailabilityResult.fromJson(json);
  }

  /// The signed-in user, from `GET /auth/me`.
  ///
  /// A user with no id is rejected rather than returned: bootstrap caches
  /// whatever comes back, and caching an empty record would greet the user
  /// by no name on every launch thereafter with no way to correct it.
  Future<UserModel> me() async {
    final Map<String, dynamic> json = await _client.get(ApiEndpoints.me);
    final UserModel user =
        UserModel.fromJson(asStringMap(json['user']) ?? json);
    if (user.id.isEmpty) {
      throw const ApiException(
        message: 'Could not load your account. Please try again.',
        code: 'MALFORMED_USER',
      );
    }
    return user;
  }

  Future<void> logout({String? refreshToken}) async {
    await _client.post(
      ApiEndpoints.logout,
      body: <String, dynamic>{
        if (refreshToken != null) 'refreshToken': refreshToken,
      },
    );
  }
}
