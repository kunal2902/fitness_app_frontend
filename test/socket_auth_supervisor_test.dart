import 'dart:async';

import 'package:fitness_app/services/socket_auth_supervisor.dart';
import 'package:fitness_app/services/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the loop that shipped: a socket handshake the server kept refusing
/// produced an unbounded `/auth/me` + reconnect cycle, one iteration every few
/// milliseconds, for as long as the app was open.
void main() {
  late StreamController<SocketStatus> status;
  late List<String> calls;
  late List<Duration> waits;
  late String token;
  late bool authenticated;
  late SocketAuthSupervisor supervisor;

  const List<Duration> backoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
  ];

  /// Builds a supervisor whose clock the test controls, so three nominal
  /// backoff steps cost no real time.
  SocketAuthSupervisor build({
    bool refreshRotatesToken = false,
    Object? refreshThrows,
    bool clearTokenOnRefresh = false,
  }) {
    return SocketAuthSupervisor(
      statusStream: status.stream,
      readAccessToken: () async {
        calls.add('readToken');
        return token;
      },
      refreshSession: () async {
        calls.add('refresh');
        if (refreshThrows != null) throw refreshThrows;
        if (clearTokenOnRefresh) token = '';
        if (refreshRotatesToken) token = 'rotated-${token.length}';
      },
      reauthenticate: () async => calls.add('reauthenticate'),
      isAuthenticated: () => authenticated,
      backoff: backoff,
      sleep: (Duration d) async => waits.add(d),
    );
  }

  setUp(() {
    status = StreamController<SocketStatus>.broadcast();
    calls = <String>[];
    waits = <Duration>[];
    token = 'access-1';
    authenticated = true;
  });

  tearDown(() async {
    await supervisor.stop();
    await status.close();
  });

  /// Pushes a refusal and lets the resulting async recovery finish.
  Future<void> refuse() async {
    status.add(SocketStatus.unauthorized);
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a refusal triggers one spaced recovery attempt', () async {
    supervisor = build(refreshRotatesToken: true)..start();

    await refuse();

    expect(calls, <String>['readToken', 'refresh', 'readToken', 'reauthenticate']);
    // Spaced, not immediate. The shipped version waited not at all.
    expect(waits, <Duration>[backoff.first]);
    expect(supervisor.attempts, 1);
  });

  test('repeated refusals stop instead of looping forever', () async {
    supervisor = build()..start();

    // Ten refusals in a row — the shape the device log showed.
    for (int i = 0; i < 10; i++) {
      await refuse();
    }

    // Capped at the backoff length, not ten.
    expect(supervisor.attempts, backoff.length);
    expect(supervisor.hasGivenUp, isTrue);
    expect(waits, backoff);
    expect(
      calls.where((String c) => c == 'refresh').length,
      backoff.length,
      reason: 'one /auth/me per attempt, not one per refusal',
    );
  });

  test('each attempt waits longer than the last', () async {
    supervisor = build()..start();

    for (int i = 0; i < backoff.length; i++) {
      await refuse();
    }

    for (int i = 1; i < waits.length; i++) {
      expect(waits[i], greaterThan(waits[i - 1]));
    }
  });

  test('a successful connect restores the full budget', () async {
    supervisor = build()..start();

    await refuse();
    await refuse();
    expect(supervisor.attempts, 2);

    status.add(SocketStatus.connected);
    await Future<void>.delayed(Duration.zero);
    expect(supervisor.attempts, 0);
    expect(supervisor.hasGivenUp, isFalse);

    // And the budget really is spendable again.
    await refuse();
    expect(supervisor.attempts, 1);
  });

  test('a refusal while signed out is ignored', () async {
    authenticated = false;
    supervisor = build()..start();

    await refuse();

    // Signing out removes the token on purpose; reconnecting would be
    // refused and AuthBloc is already routing the user out.
    expect(calls, isEmpty);
    expect(waits, isEmpty);
    expect(supervisor.attempts, 0);
  });

  test('signing out mid-recovery abandons the reconnect', () async {
    supervisor = SocketAuthSupervisor(
      statusStream: status.stream,
      readAccessToken: () async => token,
      refreshSession: () async => calls.add('refresh'),
      reauthenticate: () async => calls.add('reauthenticate'),
      isAuthenticated: () => authenticated,
      backoff: backoff,
      sleep: (Duration d) async {
        // The user signs out while the supervisor is waiting out its backoff.
        authenticated = false;
      },
    )..start();

    await refuse();

    expect(calls, isEmpty);
  });

  test('a session that ends during refresh does not reconnect', () async {
    supervisor = build(clearTokenOnRefresh: true)..start();

    await refuse();

    expect(calls, contains('refresh'));
    expect(calls, isNot(contains('reauthenticate')));
  });

  test('an unchanged token still gets a retry, because a refusal is not '
      'proof the token is bad', () async {
    // The server answers UNAUTHORIZED for a database hiccup during the
    // account lookup too, and that clears on its own.
    supervisor = build()..start();

    await refuse();

    expect(calls, contains('reauthenticate'));
    expect(supervisor.attempts, 1);
  });

  test('a throwing refresh is contained and still counts as an attempt',
      () async {
    supervisor = build(refreshThrows: StateError('offline'))..start();

    await refuse();

    expect(calls, isNot(contains('reauthenticate')));
    expect(supervisor.attempts, 1);
    // And the supervisor is not wedged — the next refusal is still handled.
    await refuse();
    expect(supervisor.attempts, 2);
  });

  test('concurrent refusals collapse into a single recovery', () async {
    supervisor = build()..start();

    status.add(SocketStatus.unauthorized);
    status.add(SocketStatus.unauthorized);
    status.add(SocketStatus.unauthorized);
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(supervisor.attempts, 1);
    expect(calls.where((String c) => c == 'refresh').length, 1);
  });

  test('stop() detaches the supervisor', () async {
    supervisor = build()..start();
    await supervisor.stop();

    await refuse();

    expect(calls, isEmpty);
    expect(supervisor.attempts, 0);
  });
}
