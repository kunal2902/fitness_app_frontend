import 'dart:async';
import 'dart:developer' as developer;

import 'socket_service.dart';

typedef SocketAuthAction = Future<void> Function();
typedef SocketTokenReader = Future<String?> Function();
typedef SocketSleeper = Future<void> Function(Duration);

/// Recovers the socket when its handshake is refused.
///
/// The handshake authenticates once, so a live socket survives an access
/// token expiring — but a *reconnect* with a stale token is refused. Touching
/// an authenticated endpoint runs the normal refresh path, after which the
/// socket can reconnect with the new token.
///
/// The hard part is what to do when that does not work. The first version of
/// this had no backoff and no limit, so a refusal the refresh could not fix
/// produced an unbounded tight loop: refuse, call `/auth/me`, reconnect,
/// refuse. On a device that is a request every few milliseconds for as long
/// as the app is open, and the user sees nothing at all.
///
/// Two things prevent that here. Attempts are spaced by [defaultBackoff] and
/// capped at its length, and the counter only resets when the socket actually
/// connects. A refusal that cannot be recovered therefore costs a handful of
/// requests and then stops.
///
/// Retries continue even when the refresh left the token unchanged, because a
/// refusal is not proof the token is bad: the server answers `UNAUTHORIZED`
/// for a database hiccup during the account lookup too, and that one clears
/// on its own. The log line says which case it was, since that is the
/// difference between "wait" and "something is actually wrong".
class SocketAuthSupervisor {
  SocketAuthSupervisor({
    required Stream<SocketStatus> statusStream,
    required SocketTokenReader readAccessToken,
    required SocketAuthAction refreshSession,
    required SocketAuthAction reauthenticate,
    required bool Function() isAuthenticated,
    List<Duration>? backoff,
    SocketSleeper? sleep,
  })  : _statusStream = statusStream,
        _readAccessToken = readAccessToken,
        _refreshSession = refreshSession,
        _reauthenticate = reauthenticate,
        _isAuthenticated = isAuthenticated,
        _backoff = backoff ?? defaultBackoff,
        _sleep = sleep ?? Future<void>.delayed;

  /// Spacing between recovery attempts, and — by its length — how many are
  /// made before giving up until the next successful connect.
  static const List<Duration> defaultBackoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 8),
    Duration(seconds: 30),
  ];

  final Stream<SocketStatus> _statusStream;
  final SocketTokenReader _readAccessToken;
  final SocketAuthAction _refreshSession;
  final SocketAuthAction _reauthenticate;
  final bool Function() _isAuthenticated;
  final List<Duration> _backoff;
  final SocketSleeper _sleep;

  StreamSubscription<SocketStatus>? _subscription;
  bool _recovering = false;
  int _attempts = 0;

  /// Recovery attempts since the last successful connection.
  int get attempts => _attempts;

  /// True once the backoff list is exhausted. Cleared by a connect.
  bool get hasGivenUp => _attempts >= _backoff.length;

  void start() {
    _subscription ??= _statusStream.listen(_onStatus);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onStatus(SocketStatus status) {
    if (status == SocketStatus.connected) {
      // Recovered. Allow the full budget again for the next failure, so a
      // long session is not left with a spent counter.
      _attempts = 0;
      return;
    }
    if (status != SocketStatus.unauthorized) return;
    unawaited(_recover());
  }

  Future<void> _recover() async {
    if (_recovering) return;
    // Signed out: the token is gone on purpose and AuthBloc is already
    // routing the user out. Reconnecting would be refused and meaningless.
    if (!_isAuthenticated()) return;
    if (hasGivenUp) return;

    _recovering = true;
    final Duration wait = _backoff[_attempts];
    _attempts += 1;

    try {
      await _sleep(wait);
      // Re-checked after the wait: a sign-out during it makes the rest of
      // this pointless.
      if (!_isAuthenticated()) return;

      final String? before = await _readAccessToken();
      await _refreshSession();
      final String? after = await _readAccessToken();

      if (after == null || after.isEmpty) {
        developer.log(
          'socket auth: session ended during recovery, not reconnecting',
          name: 'socket',
        );
        return;
      }

      developer.log(
        after == before
            ? 'socket auth: token unchanged after refresh, retrying anyway '
                '(attempt $_attempts of ${_backoff.length})'
            : 'socket auth: token refreshed, reconnecting '
                '(attempt $_attempts of ${_backoff.length})',
        name: 'socket',
      );
      await _reauthenticate();
    } catch (error) {
      developer.log('socket auth recovery failed: $error', name: 'socket');
    } finally {
      _recovering = false;
      if (hasGivenUp) {
        developer.log(
          'socket auth: giving up after ${_backoff.length} attempts. Realtime '
              'features stay off until the socket connects again.',
          name: 'socket',
        );
      }
    }
  }
}
