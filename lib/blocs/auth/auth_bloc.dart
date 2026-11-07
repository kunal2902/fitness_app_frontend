import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/api_exception.dart';
import '../../models/auth_models.dart';
import '../../models/onboarding_data.dart';
import '../../models/user_model.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../store/app_store.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Owns authentication. Talks to [AuthService] for I/O and writes the
/// resulting session into [AppStore], which persists it.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({AuthService? service, AppStore? store, ApiClient? client})
      : _service = service ?? AuthService(),
        _store = store ?? AppStore.instance,
        _client = client ?? ApiClient.instance,
        super(const AuthState()) {
    on<AuthBootstrapRequested>(_onBootstrap);
    on<AuthSignupSubmitted>(_onSignup);
    on<AuthLoginSubmitted>(_onLogin);
    on<AuthLogoutRequested>(_onLogout);
    on<AuthSessionExpired>(_onSessionExpired);
    on<AuthErrorCleared>(_onErrorCleared);
    on<AuthUserUpdated>(_onUserUpdated);
  }

  final AuthService _service;
  final AppStore _store;
  final ApiClient _client;

  /// Shown when something the service did not translate escapes. Every
  /// handler below has a catch-all for exactly this: a `TypeError` from an
  /// unexpected payload, a plugin failing to reach the keystore. Without
  /// one the bloc dies part-way through a transition and the form it was
  /// serving spins for ever, with no way out but restarting the app.
  static const String _unexpected =
      'Something went wrong. Please try again.';

  Future<void> _onBootstrap(
    AuthBootstrapRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (!_store.isBootstrapped) {
      await _store.bootstrap();
    }

    if (!_store.isAuthenticated) {
      // A token with no usable cached profile is not "signed out". The
      // token still works, so behaving as anonymous would leave it on disk
      // and attached to every request, authorising calls as a user the UI
      // has forgotten. Ask the server who it belongs to instead.
      if (_store.hasSessionToken) {
        await _recoverSession(emit);
        return;
      }
      emit(const AuthState(status: AuthFlowStatus.unauthenticated));
      return;
    }

    // We have a token — trust the cached user immediately so the app opens
    // instantly, then quietly revalidate against the server.
    emit(
      AuthState(
        status: AuthFlowStatus.authenticated,
        user: _store.user,
      ),
    );

    try {
      final UserModel fresh = await _service.me();
      await _store.updateUser(fresh);
      emit(
        AuthState(status: AuthFlowStatus.authenticated, user: fresh),
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _endSession(emit);
      // Any other failure (offline, 5xx) — keep the cached session.
    } catch (_) {
      // A malformed /auth/me is not grounds for throwing away a session
      // that still works. Keep the cached user and move on.
    }
  }

  /// Rebuilds a session we hold tokens for but cannot describe.
  ///
  /// Reached when the cached profile is missing or corrupt — a cleared
  /// SharedPreferences, a cache written by an older build. Only a 401 is
  /// taken as proof the token is dead; being offline at launch leaves it
  /// alone so the next launch can try again.
  Future<void> _recoverSession(Emitter<AuthState> emit) async {
    try {
      final UserModel user = await _service.me();
      await _store.adoptRecoveredUser(user);
      emit(AuthState(status: AuthFlowStatus.authenticated, user: user));
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _endSession(emit);
      } else {
        emit(const AuthState(status: AuthFlowStatus.unauthenticated));
      }
    } catch (_) {
      emit(const AuthState(status: AuthFlowStatus.unauthenticated));
    }
  }

  /// Ends the session everywhere at once.
  ///
  /// The order matters: the API client is told first so a refresh already
  /// in flight cannot write its rotated pair back over the slot the store
  /// is about to clear.
  Future<void> _endSession(
    Emitter<AuthState> emit, {
    bool expired = false,
  }) async {
    _client.invalidateSession();
    await _store.clearSession();
    emit(
      AuthState(
        status: AuthFlowStatus.unauthenticated,
        errorMessage:
            expired ? 'Your session expired. Please sign in again.' : null,
        sessionExpired: expired,
      ),
    );
  }

  Future<void> _onSignup(
    AuthSignupSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthFlowStatus.submitting, clearError: true));

    try {
      final AuthSession session = await _service.signup(
        SignupRequest(
          username: event.username,
          fullName: event.fullName,
          email: event.email,
          password: event.password,
          fitnessProfile: event.fitnessProfile,
        ),
      );

      await _store.setSession(session);
      await _store.markOnboardingCompleted();
      await _store.clearOnboardingDraft();

      emit(
        AuthState(
          status: AuthFlowStatus.authenticated,
          user: session.user,
          justSignedUp: true,
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          status: AuthFlowStatus.failure,
          errorMessage: e.message,
          fieldErrors: e.fieldErrors,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: AuthFlowStatus.failure,
          errorMessage: _unexpected,
        ),
      );
    }
  }

  Future<void> _onLogin(
    AuthLoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthFlowStatus.submitting, clearError: true));

    try {
      final AuthSession session = await _service.login(
        LoginRequest(
          identifier: event.identifier,
          password: event.password,
        ),
      );
      await _store.setSession(session);
      emit(
        AuthState(status: AuthFlowStatus.authenticated, user: session.user),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          status: AuthFlowStatus.failure,
          errorMessage: e.message,
          fieldErrors: e.fieldErrors,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: AuthFlowStatus.failure,
          errorMessage: _unexpected,
        ),
      );
    }
  }

  Future<void> _onLogout(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    // The live token from storage, not the cached copy: the API client
    // rotates tokens straight into secure storage, so the cached one can be
    // a generation behind — and revoking a superseded token leaves the real
    // session alive on the server while the user believes they signed out.
    String? refresh;
    try {
      refresh = await _store.currentRefreshToken();
    } catch (_) {
      refresh = _store.refreshToken;
    }

    try {
      await _service.logout(refreshToken: refresh);
    } catch (_) {
      // Best effort. Revocation can fail — offline, a 500, a keystore that
      // will not open — and none of those may leave the user stuck signed
      // in on this device. The local session goes either way.
    }
    await _endSession(emit);
  }

  Future<void> _onSessionExpired(
    AuthSessionExpired event,
    Emitter<AuthState> emit,
  ) async {
    await _endSession(emit, expired: true);
  }

  void _onErrorCleared(AuthErrorCleared event, Emitter<AuthState> emit) {
    emit(state.copyWith(clearError: true));
  }

  void _onUserUpdated(AuthUserUpdated event, Emitter<AuthState> emit) {
    emit(state.copyWith(user: event.user));
  }
}
