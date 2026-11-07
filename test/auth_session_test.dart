import 'dart:async';

import 'package:fitness_app/blocs/auth/auth_bloc.dart';
import 'package:fitness_app/config/api_endpoints.dart';
import 'package:fitness_app/config/storage_keys.dart';
import 'package:fitness_app/models/api_exception.dart';
import 'package:fitness_app/models/user_model.dart';
import 'package:fitness_app/services/api_client.dart';
import 'package:fitness_app/services/auth_service.dart';
import 'package:fitness_app/services/storage_service.dart';
import 'package:fitness_app/store/app_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_harness.dart';

/// End-to-end over the session machinery: a real [ApiClient] with its
/// interceptors, a real [AuthService], a real [AppStore] and a real
/// [StorageService] on mock platform channels. Only the socket underneath
/// Dio is fake, so everything that can actually break is exercised.
void main() {
  setUpAll(initAuthTestStorage);

  AuthBloc blocFor(FakeBackend backend) => AuthBloc();

  group('sign in', () {
    test('persists tokens and user, and sends the token on the next call',
        () async {
      final FakeBackend backend = await resetAuthWorld();
      backend.on(ApiEndpoints.login, const Reply(200, <String, dynamic>{}));
      backend.on(
        ApiEndpoints.login,
        Reply(200, sessionBody(accessToken: 'A1', refreshToken: 'R1')),
      );
      backend.on(ApiEndpoints.me, Reply(200, userBody()));

      final AuthBloc bloc = blocFor(backend);
      bloc.add(
        const AuthLoginSubmitted(
          identifier: 'kunal@example.com',
          password: 'correct-horse',
        ),
      );
      await bloc.stream.firstWhere((AuthState s) => !s.isSubmitting);

      expect(bloc.state.isAuthenticated, isTrue);
      expect(bloc.state.user?.username, 'kunal');
      expect(AppStore.instance.isAuthenticated, isTrue);
      // Proof it reached the keystore, not just an in-memory mirror.
      expect(secureStore[StorageKeys.accessToken], 'A1');
      expect(secureStore[StorageKeys.refreshToken], 'R1');

      await AuthService().me();
      expect(backend.lastTo(ApiEndpoints.me)?.bearer, 'A1');
      await bloc.close();
    });

    test('a wrong password never spends the refresh token', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(
        ApiEndpoints.login,
        const Reply(401, <String, dynamic>{'message': 'Invalid credentials'}),
      );

      final AuthBloc bloc = blocFor(backend);
      bloc.add(
        const AuthLoginSubmitted(identifier: 'kunal', password: 'wrong'),
      );
      await bloc.stream.firstWhere((AuthState s) => !s.isSubmitting);

      expect(bloc.state.status, AuthFlowStatus.failure);
      expect(bloc.state.errorMessage, 'Invalid credentials');
      // The critical assertion: refreshing on a login 401 would burn a good
      // refresh token and could sign the user into whichever account the
      // stored one belongs to.
      expect(backend.callsTo(ApiEndpoints.refresh), 0);
      expect(secureStore[StorageKeys.refreshToken], 'refresh-1');
      await bloc.close();
    });

    test('a 200 with no usable session is refused, not accepted', () async {
      final FakeBackend backend = await resetAuthWorld();
      backend.on(
        ApiEndpoints.login,
        Reply(200, sessionBody(accessToken: '')),
      );

      final AuthBloc bloc = blocFor(backend);
      bloc.add(
        const AuthLoginSubmitted(identifier: 'kunal', password: 'pw'),
      );
      await bloc.stream.firstWhere((AuthState s) => !s.isSubmitting);

      // Accepting it would be the worst outcome available: authenticated to
      // the router, anonymous to the server, and no way back.
      expect(bloc.state.status, AuthFlowStatus.failure);
      expect(bloc.state.isAuthenticated, isFalse);
      expect(AppStore.instance.isAuthenticated, isFalse);
      expect(secureStore, isEmpty);
      await bloc.close();
    });

    test('a server 500 leaves a retryable failure, not a stuck form',
        () async {
      final FakeBackend backend = await resetAuthWorld();
      backend.onSequence(ApiEndpoints.login, <Reply>[
        const Reply(500, <String, dynamic>{}),
        Reply(200, sessionBody()),
      ]);

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthLoginSubmitted(identifier: 'k', password: 'p'));
      await bloc.stream.firstWhere((AuthState s) => !s.isSubmitting);
      expect(bloc.state.status, AuthFlowStatus.failure);
      expect(bloc.state.isSubmitting, isFalse);

      bloc.add(const AuthLoginSubmitted(identifier: 'k', password: 'p'));
      await bloc.stream.firstWhere((AuthState s) => s.isAuthenticated);
      expect(bloc.state.isAuthenticated, isTrue);
      await bloc.close();
    });
  });

  group('token refresh', () {
    test('a 401 refreshes, rotates storage and replays with the new token',
        () async {
      final FakeBackend backend = await resetSignedIn();
      backend.onSequence(ApiEndpoints.me, <Reply>[
        const Reply(401, <String, dynamic>{'message': 'expired'}),
        Reply(200, userBody(fullName: 'Kunal B')),
      ]);
      backend.on(
        ApiEndpoints.refresh,
        Reply(200, sessionBody(accessToken: 'A2', refreshToken: 'R2')),
      );

      final UserModel user = await AuthService().me();

      expect(user.fullName, 'Kunal B');
      expect(backend.callsTo(ApiEndpoints.refresh), 1);
      expect(backend.callsTo(ApiEndpoints.me), 2);
      // The replay must carry the refreshed token; carrying the expired one
      // would 401 again and look like a dead session.
      expect(backend.lastTo(ApiEndpoints.me)?.bearer, 'A2');
      expect(secureStore[StorageKeys.accessToken], 'A2');
      expect(secureStore[StorageKeys.refreshToken], 'R2');
    });

    test('a rotation that omits a new refresh token keeps the old one',
        () async {
      final FakeBackend backend = await resetSignedIn();
      backend.onSequence(ApiEndpoints.me, <Reply>[
        const Reply(401, <String, dynamic>{}),
        Reply(200, userBody()),
      ]);
      backend.on(
        ApiEndpoints.refresh,
        const Reply(200, <String, dynamic>{'accessToken': 'A2'}),
      );

      await AuthService().me();

      expect(secureStore[StorageKeys.accessToken], 'A2');
      expect(secureStore[StorageKeys.refreshToken], 'refresh-1');
    });

    test('concurrent 401s collapse into a single refresh', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.onSequence(ApiEndpoints.me, <Reply>[
        const Reply(401, <String, dynamic>{}),
        const Reply(401, <String, dynamic>{}),
        const Reply(401, <String, dynamic>{}),
        Reply(200, userBody()),
      ]);
      backend.on(
        ApiEndpoints.refresh,
        Reply(200, sessionBody(accessToken: 'A2', refreshToken: 'R2')),
      );

      final AuthService service = AuthService();
      await Future.wait<UserModel>(<Future<UserModel>>[
        service.me(),
        service.me(),
        service.me(),
      ]);

      // Three refreshes would rotate three times and invalidate each other.
      expect(backend.callsTo(ApiEndpoints.refresh), 1);
      expect(secureStore[StorageKeys.refreshToken], 'R2');
    });

    test('a rejected refresh clears the session and reports it once',
        () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.me, const Reply(401, <String, dynamic>{}));
      backend.on(
        ApiEndpoints.refresh,
        const Reply(401, <String, dynamic>{'message': 'revoked'}),
      );

      int expiries = 0;
      ApiClient.instance.onSessionExpired = () => expiries++;

      await expectLater(AuthService().me(), throwsA(isA<ApiException>()));

      expect(expiries, 1);
      expect(secureStore, isEmpty);
    });

    test('a refresh that fails offline keeps the tokens', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.me, const Reply(401, <String, dynamic>{}));
      backend.on(ApiEndpoints.refresh, const Reply.offline());

      await expectLater(AuthService().me(), throwsA(isA<ApiException>()));

      // Signing the user out over a dropped connection would be the wrong
      // read of a network failure — the refresh token is probably fine.
      expect(secureStore[StorageKeys.refreshToken], 'refresh-1');
      expect(secureStore[StorageKeys.accessToken], 'access-1');
    });

    test('a 429 on refresh does not discard the session', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.me, const Reply(401, <String, dynamic>{}));
      backend.on(ApiEndpoints.refresh, const Reply(429, <String, dynamic>{}));

      await expectLater(AuthService().me(), throwsA(isA<ApiException>()));

      expect(secureStore[StorageKeys.refreshToken], 'refresh-1');
    });

    test('a refresh landing after sign-out does not resurrect the session',
        () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.me, const Reply(401, <String, dynamic>{}));
      backend.on(
        ApiEndpoints.refresh,
        Reply(200, sessionBody(accessToken: 'A2', refreshToken: 'R2')),
      );
      backend.on(ApiEndpoints.logout, const Reply(200, <String, dynamic>{}));

      // Hold the refresh open so the sign-out below genuinely lands while
      // it is in flight. Without the hold the refresh finishes first and the
      // test would pass without ever exercising the guard.
      final Completer<void> release = backend.hold(ApiEndpoints.refresh);
      final Future<UserModel> pending = AuthService().me();
      for (int i = 0;
          i < 100 && backend.callsTo(ApiEndpoints.refresh) == 0;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(backend.callsTo(ApiEndpoints.refresh), 1);

      // The user signs out while the rotation is still on the wire.
      ApiClient.instance.invalidateSession();
      await StorageService.instance.clearTokens();
      release.complete();
      await expectLater(pending, throwsA(isA<ApiException>()));

      // Without the epoch guard the rotated pair lands here and the next
      // cold start signs the user back into the account they just left.
      expect(secureStore, isEmpty);
    });
  });

  group('sign out', () {
    test('revokes the rotated refresh token, not the stale cached one',
        () async {
      final FakeBackend backend = await resetSignedIn();
      backend.onSequence(ApiEndpoints.me, <Reply>[
        const Reply(401, <String, dynamic>{}),
        Reply(200, userBody(fullName: 'After Rotation')),
      ]);
      backend.on(
        ApiEndpoints.refresh,
        Reply(200, sessionBody(accessToken: 'A2', refreshToken: 'R2')),
      );
      backend.on(ApiEndpoints.logout, const Reply(200, <String, dynamic>{}));

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthBootstrapRequested());
      // Waiting on the renamed user, not on any authenticated state: the
      // cached emission arrives first and would let sign-out run before the
      // rotation it is meant to be tested against.
      await bloc.stream
          .firstWhere((AuthState s) => s.user?.fullName == 'After Rotation');
      expect(secureStore[StorageKeys.refreshToken], 'R2');

      bloc.add(const AuthLogoutRequested());
      await bloc.stream.firstWhere(
        (AuthState s) => s.status == AuthFlowStatus.unauthenticated,
      );

      // The cached copy is a generation behind after the rotation above.
      // Revoking it would leave the live session alive on the server while
      // the user believes they signed out.
      expect(backend.lastTo(ApiEndpoints.logout)?.body['refreshToken'], 'R2');
      expect(secureStore, isEmpty);
      expect(AppStore.instance.user, isNull);
      await bloc.close();
    });

    test('clears the device even when revocation fails', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.logout, const Reply.offline());

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthLogoutRequested());
      await bloc.stream.firstWhere(
        (AuthState s) => s.status == AuthFlowStatus.unauthenticated,
      );

      // A failed revocation must never leave the user stuck signed in.
      expect(secureStore, isEmpty);
      expect(AppStore.instance.isAuthenticated, isFalse);
      expect(
        StorageService.instance.getJson(StorageKeys.userJson),
        isNull,
      );
      await bloc.close();
    });

    test('signing out is not announced as an expiry', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.logout, const Reply(200, <String, dynamic>{}));

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthLogoutRequested());
      final AuthState state = await bloc.stream.firstWhere(
        (AuthState s) => s.status == AuthFlowStatus.unauthenticated,
      );

      expect(state.sessionExpired, isFalse);
      expect(state.errorMessage, isNull);
      await bloc.close();
    });
  });

  group('cold start', () {
    test('no tokens means unauthenticated', () async {
      final FakeBackend backend = await resetAuthWorld();

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthBootstrapRequested());
      final AuthState state = await bloc.stream.first;

      expect(state.status, AuthFlowStatus.unauthenticated);
      expect(backend.callsTo(ApiEndpoints.me), 0);
      await bloc.close();
    });

    test('a cached session opens immediately, then revalidates', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.me, Reply(200, userBody(fullName: 'Renamed')));

      final AuthBloc bloc = blocFor(backend);
      final List<AuthState> seen = <AuthState>[];
      final sub = bloc.stream.listen(seen.add);
      bloc.add(const AuthBootstrapRequested());
      await bloc.stream.firstWhere((AuthState s) => s.user?.fullName == 'Renamed');
      await sub.cancel();

      // Cached first so the app opens instantly, fresh second.
      expect(seen.first.isAuthenticated, isTrue);
      expect(seen.first.user?.fullName, 'Kunal Bhardwaj');
      expect(seen.last.user?.fullName, 'Renamed');
      await bloc.close();
    });

    test('an offline revalidation keeps the cached session', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.me, const Reply.offline());

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthBootstrapRequested());
      await bloc.stream.first;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.isAuthenticated, isTrue);
      expect(secureStore[StorageKeys.accessToken], 'access-1');
      await bloc.close();
    });

    test('a revalidation 401 ends the session', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.me, const Reply(401, <String, dynamic>{}));
      backend.on(ApiEndpoints.refresh, const Reply(401, <String, dynamic>{}));

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthBootstrapRequested());
      await bloc.stream.firstWhere(
        (AuthState s) => s.status == AuthFlowStatus.unauthenticated,
      );

      expect(secureStore, isEmpty);
      expect(AppStore.instance.user, isNull);
      await bloc.close();
    });

    test('tokens with no cached profile are recovered, not thrown away',
        () async {
      final FakeBackend backend = await resetSignedIn(withCachedUser: false);
      backend.on(ApiEndpoints.me, Reply(200, userBody(username: 'restored')));

      expect(AppStore.instance.isAuthenticated, isFalse);
      expect(AppStore.instance.hasSessionToken, isTrue);

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthBootstrapRequested());
      await bloc.stream.firstWhere((AuthState s) => s.isAuthenticated);

      // Treating this as "signed out" would leave a working token on disk,
      // attached to every request, as a user the UI had forgotten.
      expect(bloc.state.user?.username, 'restored');
      expect(AppStore.instance.isAuthenticated, isTrue);
      expect(
        StorageService.instance.getJson(StorageKeys.userJson)?['username'],
        'restored',
      );
      await bloc.close();
    });

    test('an unrecoverable orphan token is cleared', () async {
      final FakeBackend backend = await resetSignedIn(withCachedUser: false);
      backend.on(ApiEndpoints.me, const Reply(401, <String, dynamic>{}));
      backend.on(ApiEndpoints.refresh, const Reply(401, <String, dynamic>{}));

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthBootstrapRequested());
      await bloc.stream.firstWhere(
        (AuthState s) => s.status == AuthFlowStatus.unauthenticated,
      );

      expect(secureStore, isEmpty);
      await bloc.close();
    });

    test('a corrupt cached profile is discarded and refetched', () async {
      final FakeBackend backend = await resetAuthWorld(
        tokens: <String, String>{
          StorageKeys.accessToken: 'access-1',
          StorageKeys.refreshToken: 'refresh-1',
        },
        // An id-less record is a corrupt cache, not a user.
        cachedUser: <String, dynamic>{'username': 'ghost'},
      );
      backend.on(ApiEndpoints.me, Reply(200, userBody(username: 'real')));

      expect(AppStore.instance.user, isNull);

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthBootstrapRequested());
      await bloc.stream.firstWhere((AuthState s) => s.isAuthenticated);

      expect(bloc.state.user?.username, 'real');
      await bloc.close();
    });

    test('a malformed revalidation does not drop a working session',
        () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(
        ApiEndpoints.me,
        const Reply(200, <String, dynamic>{'user': <String, dynamic>{}}),
      );

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthBootstrapRequested());
      await bloc.stream.first;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.isAuthenticated, isTrue);
      expect(bloc.state.user?.username, 'kunal');
      expect(secureStore[StorageKeys.accessToken], 'access-1');
      await bloc.close();
    });
  });

  group('session expiry', () {
    test('expiry clears everything and flags itself exactly once', () async {
      final FakeBackend backend = await resetSignedIn();
      backend.on(ApiEndpoints.me, Reply(200, userBody()));

      final AuthBloc bloc = blocFor(backend);
      bloc.add(const AuthSessionExpired());
      final AuthState expired = await bloc.stream.firstWhere(
        (AuthState s) => s.status == AuthFlowStatus.unauthenticated,
      );

      expect(expired.sessionExpired, isTrue);
      expect(expired.errorMessage, contains('expired'));
      expect(secureStore, isEmpty);

      // One-shot: the next state must not re-announce it, or every return to
      // the sign-in screen would replay an expiry the user already handled.
      bloc.add(const AuthErrorCleared());
      final AuthState after = await bloc.stream.first;
      expect(after.sessionExpired, isFalse);
      expect(after.errorMessage, isNull);
      await bloc.close();
    });

    test('justSignedUp does not survive into later states', () async {
      final FakeBackend backend = await resetAuthWorld();
      backend.on(ApiEndpoints.signup, Reply(200, sessionBody()));

      final AuthBloc bloc = blocFor(backend);
      bloc.add(
        const AuthSignupSubmitted(
          username: 'kunal',
          fullName: 'Kunal Bhardwaj',
          email: 'kunal@example.com',
          password: 'Str0ng-pass!',
          fitnessProfile: completeOnboarding,
        ),
      );
      final AuthState signedUp =
          await bloc.stream.firstWhere((AuthState s) => s.isAuthenticated);
      expect(signedUp.justSignedUp, isTrue);

      bloc.add(
        AuthUserUpdated(signedUp.user!.copyWith(fullName: 'Edited')),
      );
      final AuthState later = await bloc.stream.first;

      // Left sticky, every later state looks like a fresh signup and the
      // account screen would route to Home again from under the user.
      expect(later.justSignedUp, isFalse);
      await bloc.close();
    });
  });

  group('unexpected failures', () {
    test('an untranslated error still clears the submitting state', () async {
      final FakeBackend backend = await resetAuthWorld();
      final AuthBloc bloc = AuthBloc(service: _ExplodingAuthService());

      bloc.add(const AuthLoginSubmitted(identifier: 'k', password: 'p'));
      await bloc.stream.firstWhere((AuthState s) => !s.isSubmitting);

      // Without a catch-all the bloc dies mid-transition and the sign-in
      // button spins for ever with no way out but restarting the app.
      expect(bloc.state.status, AuthFlowStatus.failure);
      expect(bloc.state.errorMessage, isNotNull);
      expect(backend.callsTo(ApiEndpoints.login), 0);
      await bloc.close();
    });

    test('an untranslated error during sign-out still clears the device',
        () async {
      await resetSignedIn();
      final AuthBloc bloc = AuthBloc(service: _ExplodingAuthService());

      bloc.add(const AuthLogoutRequested());
      await bloc.stream.firstWhere(
        (AuthState s) => s.status == AuthFlowStatus.unauthenticated,
      );

      expect(secureStore, isEmpty);
      expect(AppStore.instance.isAuthenticated, isFalse);
      await bloc.close();
    });
  });
}

/// Throws something that is deliberately *not* an [ApiException], standing in
/// for a payload that does not parse or a keystore plugin that fails.
class _ExplodingAuthService extends AuthService {
  @override
  Future<Never> login(_) => throw StateError('unexpected');

  @override
  Future<Never> signup(_) => throw StateError('unexpected');

  @override
  Future<Never> logout({String? refreshToken}) =>
      throw StateError('unexpected');
}
