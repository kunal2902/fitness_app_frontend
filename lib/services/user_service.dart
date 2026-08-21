import 'package:dio/dio.dart';

import '../config/api_endpoints.dart';
import '../config/app_config.dart';
import '../models/api_exception.dart';
import '../models/user_model.dart';
import 'api_client.dart';

/// Profile reads and writes. Pure I/O — the BLoC decides what to do with
/// the result.
class UserService {
  UserService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<UserModel> fetchProfile() async {
    final Map<String, dynamic> json = await _client.get(ApiEndpoints.profile);
    return _user(json);
  }

  /// Partial update — pass only what changed. Sending an unchanged value is
  /// harmless, but sending everything means a stale field can clobber an
  /// edit made on another device.
  Future<UserModel> updateProfile({
    String? fullName,
    String? username,
    String? email,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      if (fullName != null) 'fullName': fullName.trim(),
      if (username != null) 'username': username.trim(),
      if (email != null) 'email': email.trim().toLowerCase(),
    };

    if (body.isEmpty) {
      throw const ApiException(
        message: 'Nothing to update.',
        code: 'NO_CHANGES',
      );
    }

    final Map<String, dynamic> json = await _client.patch(
      ApiEndpoints.profile,
      body: body,
    );
    return _user(json);
  }

  /// Uploads a new profile picture as multipart under the field `avatar`.
  ///
  /// The field name must be exactly `avatar` — multer is configured with
  /// `.single('avatar')` and rejects anything else with a 400.
  Future<UserModel> uploadAvatar(String filePath) async {
    final Map<String, dynamic> json = await _client.postMultipart(
      ApiEndpoints.avatar,
      timeout: AppConfig.uploadTimeout,
      formBuilder: () async => FormData.fromMap(<String, dynamic>{
        'avatar': await MultipartFile.fromFile(filePath),
      }),
    );
    return _user(json);
  }

  Future<UserModel> removeAvatar() async {
    final Map<String, dynamic> json = await _client.delete(ApiEndpoints.avatar);
    return _user(json);
  }

  // -------------------------------------------------------------------------

  static UserModel _user(Map<String, dynamic> json) {
    final Object? user = json['user'];
    return UserModel.fromJson(user is Map<String, dynamic> ? user : json);
  }
}
