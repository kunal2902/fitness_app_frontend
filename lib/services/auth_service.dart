import '../config/api_endpoints.dart';
import '../models/auth_models.dart';
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
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> login(LoginRequest request) async {
    final Map<String, dynamic> json = await _client.post(
      ApiEndpoints.login,
      body: request.toJson(),
      skipAuth: true,
    );
    return AuthSession.fromJson(json);
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

  Future<UserModel> me() async {
    final Map<String, dynamic> json = await _client.get(ApiEndpoints.me);
    final Object? user = json['user'];
    return UserModel.fromJson(
      user is Map<String, dynamic> ? user : json,
    );
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
