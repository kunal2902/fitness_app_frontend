import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fitness_app/config/storage_keys.dart';
import 'package:fitness_app/models/enums.dart';
import 'package:fitness_app/models/onboarding_data.dart';
import 'package:fitness_app/services/api_client.dart';
import 'package:fitness_app/services/storage_service.dart';
import 'package:fitness_app/store/app_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A request the app actually sent, captured for assertions.
class SentRequest {
  SentRequest({
    required this.method,
    required this.path,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;

  /// The `Authorization` header as sent, so a test can prove a replayed
  /// request carried the *refreshed* token rather than the expired one.
  final String? authorization;
  final Map<String, dynamic> body;

  String? get bearer => authorization?.replaceFirst('Bearer ', '');

  @override
  String toString() => '$method $path';
}

/// One canned reply.
class Reply {
  const Reply(this.status, this.body);

  /// Simulates no connection at all — a `DioException` rather than a status.
  const Reply.offline()
      : status = -1,
        body = const <String, dynamic>{};

  final int status;
  final Map<String, dynamic> body;

  bool get isOffline => status == -1;
}

/// Stands in for the network underneath the *real* [ApiClient].
///
/// Swapping Dio's adapter rather than faking `AuthService` is deliberate:
/// it leaves the interceptors, the 401-refresh-and-replay, the error
/// mapping, the secure-storage writes and the store updates all under test.
/// Those are the parts of the authentication mechanism that break, and a
/// fake service would have mocked every one of them away.
class FakeBackend implements HttpClientAdapter {
  final List<SentRequest> sent = <SentRequest>[];
  final Map<String, List<Reply>> _queues = <String, List<Reply>>{};
  final Map<String, Reply> _defaults = <String, Reply>{};
  final Map<String, Completer<void>> _gates = <String, Completer<void>>{};

  /// Holds the reply for [path] until the returned completer is completed,
  /// so a test can act while that request is genuinely in flight.
  Completer<void> hold(String path) =>
      _gates[path] = Completer<void>();

  /// Every reply for [path] until the queue runs out, then [Reply] stays.
  void on(String path, Reply reply) => _defaults[path] = reply;

  /// Replies for successive calls to [path]; the last one repeats.
  void onSequence(String path, List<Reply> replies) =>
      _queues[path] = List<Reply>.of(replies);

  int callsTo(String path) =>
      sent.where((SentRequest r) => r.path == path).length;

  SentRequest? lastTo(String path) {
    for (final SentRequest request in sent.reversed) {
      if (request.path == path) return request;
    }
    return null;
  }

  Reply _replyFor(String path) {
    final List<Reply>? queue = _queues[path];
    if (queue != null && queue.isNotEmpty) {
      return queue.length == 1 ? queue.first : queue.removeAt(0);
    }
    return _defaults[path] ??
        const Reply(404, <String, dynamic>{'message': 'No fake route'});
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Object? data = options.data;
    sent.add(
      SentRequest(
        method: options.method,
        path: options.path,
        authorization: options.headers['Authorization'] as String?,
        body: data is Map
            ? data.map(
                (Object? k, Object? v) =>
                    MapEntry<String, dynamic>(k.toString(), v),
              )
            : <String, dynamic>{},
      ),
    );

    final Completer<void>? gate = _gates[options.path];
    if (gate != null && !gate.isCompleted) await gate.future;

    final Reply reply = _replyFor(options.path);
    if (reply.isOffline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'fake backend is offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A signup/login response in the shape the backend sends.
Map<String, dynamic> sessionBody({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
  String id = 'user-1',
  String username = 'kunal',
  String fullName = 'Kunal Bhardwaj',
  String email = 'kunal@example.com',
}) {
  return <String, dynamic>{
    'tokens': <String, dynamic>{
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    },
    'user': userBody(
      id: id,
      username: username,
      fullName: fullName,
      email: email,
    ),
  };
}

Map<String, dynamic> userBody({
  String id = 'user-1',
  String username = 'kunal',
  String fullName = 'Kunal Bhardwaj',
  String email = 'kunal@example.com',
}) {
  return <String, dynamic>{
    'id': id,
    'username': username,
    'fullName': fullName,
    'email': email,
    'isEmailVerified': true,
  };
}

/// Onboarding answers that satisfy `OnboardingData.isComplete`, so the
/// signup screen is reachable the way it is in the real flow.
const OnboardingData completeOnboarding = OnboardingData(
  gender: Gender.male,
  heightCm: 178,
  weightKg: 74,
  goals: <FitnessGoal>[FitnessGoal.buildMuscle],
  maxPullUps: PullUpRange.from6to10,
  maxPushUps: PushUpRange.from21to30,
  maxSquats: SquatRange.from31to40,
  maxDips: DipRange.from9to15,
  fitnessLevel: FitnessLevel.intermediate,
);

/// The live secure-storage map. Assert on it to prove tokens really landed
/// on (or left) the device, rather than trusting an in-memory mirror.
Map<String, String> secureStore = <String, String>{};

/// Call once per test file, before anything touches storage.
Future<void> initAuthTestStorage() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  FlutterSecureStorage.setMockInitialValues(secureStore);
  await StorageService.instance.init();
}

/// Resets every singleton the auth stack hangs off, then rehydrates the
/// store exactly as `main()` does.
///
/// `StorageService` holds its `SharedPreferences` in a `late final`, so the
/// mock cannot be swapped per test — state is cleared through the app's own
/// API instead, which has the side benefit of exercising it.
Future<FakeBackend> resetAuthWorld({
  Map<String, String> tokens = const <String, String>{},
  Map<String, dynamic>? cachedUser,
  bool onboardingCompleted = false,
  bool hasSeenWelcome = false,
  OnboardingData? onboardingDraft,
}) async {
  // The mock keystore goes in before anything clears or reads it, or
  // `clearAll` below reaches for the real platform channel.
  secureStore = <String, String>{};
  FlutterSecureStorage.setMockInitialValues(secureStore);
  await StorageService.instance.clearAll();
  secureStore.addAll(tokens);

  if (cachedUser != null) {
    await StorageService.instance.setJson(StorageKeys.userJson, cachedUser);
    await StorageService.instance.setBool(StorageKeys.isLoggedIn, value: true);
  }
  if (onboardingCompleted) {
    await StorageService.instance
        .setBool(StorageKeys.onboardingCompleted, value: true);
  }
  if (hasSeenWelcome) {
    await StorageService.instance
        .setBool(StorageKeys.hasSeenWelcome, value: true);
  }
  if (onboardingDraft != null) {
    await StorageService.instance
        .setJson(StorageKeys.onboardingDraft, onboardingDraft.toJson());
  }

  final FakeBackend backend = FakeBackend();
  ApiClient.instance.resetForTest();
  ApiClient.instance.raw.httpClientAdapter = backend;

  await AppStore.instance.bootstrap();
  return backend;
}

/// A device with a session already on it.
Future<FakeBackend> resetSignedIn({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
  bool withCachedUser = true,
}) {
  return resetAuthWorld(
    tokens: <String, String>{
      StorageKeys.accessToken: accessToken,
      StorageKeys.refreshToken: refreshToken,
    },
    cachedUser: withCachedUser ? userBody() : null,
    onboardingCompleted: true,
    hasSeenWelcome: true,
  );
}
