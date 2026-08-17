import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/api_exception.dart';
import '../../models/auth_models.dart';
import '../../models/onboarding_data.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../store/app_store.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Owns authentication. Talks to [AuthService] for I/O and writes the
/// resulting session into [AppStore], which persists it.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({AuthService? service, AppStore? store})
      : _service = service ?? AuthService(),
        _store = store ?? AppStore.instance,
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

  Future<void> _onBootstrap(
    AuthBootstrapRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (!_store.isBootstrapped) {
      await _store.bootstrap();
    }

    if (!_store.isAuthenticated) {
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
      if (e.isUnauthorized) {
        await _store.clearSession();
        emit(const AuthState(status: AuthFlowStatus.unauthenticated));
      }
      // Any other failure (offline, 5xx) — keep the cached session.
    }
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
    }
  }

  Future<void> _onLogout(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    final String? refresh = _store.refreshToken;
    try {
      await _service.logout(refreshToken: refresh);
    } on ApiException {
      // Best effort — the local session is cleared either way.
    }
    await _store.clearSession();
    emit(const AuthState(status: AuthFlowStatus.unauthenticated));
  }

  Future<void> _onSessionExpired(
    AuthSessionExpired event,
    Emitter<AuthState> emit,
  ) async {
    await _store.clearSession();
    emit(
      const AuthState(
        status: AuthFlowStatus.unauthenticated,
        errorMessage: 'Your session expired. Please sign in again.',
      ),
    );
  }

  void _onErrorCleared(AuthErrorCleared event, Emitter<AuthState> emit) {
    emit(state.copyWith(clearError: true));
  }

  void _onUserUpdated(AuthUserUpdated event, Emitter<AuthState> emit) {
    emit(state.copyWith(user: event.user));
  }
}
