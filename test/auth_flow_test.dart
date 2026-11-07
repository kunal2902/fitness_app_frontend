import 'package:fitness_app/blocs/auth/auth_bloc.dart';
import 'package:fitness_app/blocs/onboarding/onboarding_bloc.dart';
import 'package:fitness_app/config/api_endpoints.dart';
import 'package:fitness_app/config/storage_keys.dart';
import 'package:fitness_app/routes/app_router.dart';
import 'package:fitness_app/routes/app_routes.dart';
import 'package:fitness_app/services/storage_service.dart';
import 'package:fitness_app/store/app_store.dart';
import 'package:fitness_app/theme/app_theme.dart';
import 'package:fitness_app/widgets/auth_session_gate.dart';
import 'package:fitness_app/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'support/auth_harness.dart';

/// Drives the real auth screens through the real router, the real
/// [AuthBloc], the real HTTP stack and the real [AppStore], with only the
/// network socket faked.
///
/// The one substitution is the `/home` route: the signed-in shell boots
/// nutrition, tracking and health on mount, and none of that is what these
/// tests are asking. The question here is whether each flow *lands* a user
/// at home, so home is a marker.
///
/// Two environment notes, both learned the hard way:
///  * Storage setup runs inside [WidgetTester.runAsync]. The
///    SharedPreferences and keystore mocks answer through the platform
///    message loop, which the widget tester's fake clock never turns —
///    awaiting them on the fake clock hangs the test outright.
///  * Fixed pumps rather than `pumpAndSettle`: several of these screens
///    have continuous background animation, which `pumpAndSettle` waits on
///    for ever.
void main() {
  setUpAll(initAuthTestStorage);

  const String shell = 'SIGNED-IN SHELL';

  Route<dynamic> route(RouteSettings settings) {
    if (settings.name == AppRoutes.home) {
      return MaterialPageRoute<dynamic>(
        settings: settings,
        builder: (_) => const Scaffold(body: Center(child: Text(shell))),
      );
    }
    return AppRouter.onGenerateRoute(settings);
  }

  late AuthBloc authBloc;
  late OnboardingBloc onboardingBloc;
  late GlobalKey<NavigatorState> navigatorKey;

  Widget app({String initialRoute = AppRoutes.splash}) {
    navigatorKey = GlobalKey<NavigatorState>();
    return ChangeNotifierProvider<AppStore>.value(
      value: AppStore.instance,
      child: MultiBlocProvider(
        providers: <SingleChildWidget>[
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<OnboardingBloc>.value(value: onboardingBloc),
        ],
        child: AuthSessionGate(
          navigatorKey: navigatorKey,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: AppTheme.dark,
            initialRoute: initialRoute,
            onGenerateRoute: route,
          ),
        ),
      ),
    );
  }

  /// Seeds the device on the real event loop. See the note above.
  Future<FakeBackend> seed(
    WidgetTester tester,
    Future<FakeBackend> Function() setup,
  ) async {
    return (await tester.runAsync(setup))!;
  }

  /// Lets real async work — an HTTP round trip, a storage write — finish,
  /// then renders whatever it produced.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Boots the app and lets splash finish its hold and route onward.
  Future<void> launch(
    WidgetTester tester, {
    String initialRoute = AppRoutes.splash,
  }) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(initialRoute: initialRoute));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    await settle(tester);
  }

  setUp(() {
    authBloc = AuthBloc();
    onboardingBloc = OnboardingBloc();
  });

  tearDown(() async {
    await authBloc.close();
    await onboardingBloc.close();
  });

  Finder signInButton() => find.widgetWithText(PrimaryButton, 'Sign in');
  Finder createButton() =>
      find.widgetWithText(PrimaryButton, 'Create account');

  group('cold start lands on the right screen', () {
    testWidgets('a fresh install sees the welcome screen', (tester) async {
      await seed(tester, resetAuthWorld);
      await launch(tester);

      expect(find.text('Get started'), findsOneWidget);
      expect(find.text(shell), findsNothing);
    });

    testWidgets('a stored session opens straight into the app',
        (tester) async {
      final FakeBackend backend = await seed(tester, resetSignedIn);
      backend.on(ApiEndpoints.me, Reply(200, userBody()));

      await launch(tester);

      expect(find.text(shell), findsOneWidget);
    });

    testWidgets('a signed-out returning user gets sign-in, not the signup '
        'questionnaire', (tester) async {
      await seed(
        tester,
        () => resetAuthWorld(onboardingCompleted: true, hasSeenWelcome: true),
      );
      await launch(tester);

      // They have had an account on this device. Dropping them into the nine
      // onboarding questions, with the sign-in link only at the very end of
      // them, is not a sign-in flow.
      expect(signInButton(), findsOneWidget);

      // And the back button works, because Welcome is underneath — a root
      // Login would pop into a blank screen.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await settle(tester);
      expect(find.text('Get started'), findsOneWidget);
    });

    testWidgets('an abandoned signup resumes the questionnaire',
        (tester) async {
      await seed(
        tester,
        () => resetAuthWorld(
          hasSeenWelcome: true,
          onboardingDraft: completeOnboarding,
        ),
      );
      await launch(tester);

      expect(signInButton(), findsNothing);
      expect(find.text('Get started'), findsNothing);
      expect(find.text(shell), findsNothing);
    });
  });

  group('sign in', () {
    Future<FakeBackend> openLogin(
      WidgetTester tester,
      Future<FakeBackend> Function() setup,
    ) async {
      final FakeBackend backend = await seed(tester, setup);
      await launch(tester);
      await tester.tap(find.text('I already have an account'));
      await settle(tester);
      expect(signInButton(), findsOneWidget);
      return backend;
    }

    Future<void> submit(
      WidgetTester tester, {
      required String identifier,
      required String password,
    }) async {
      final Finder fields = find.byType(TextFormField);
      await tester.enterText(fields.first, identifier);
      await tester.enterText(fields.last, password);
      await tester.pump();
      await tester.tap(signInButton());
      await settle(tester);
    }

    testWidgets('an empty form is caught before anything is sent',
        (tester) async {
      final FakeBackend backend = await openLogin(tester, resetAuthWorld);

      await tester.tap(signInButton());
      await settle(tester);

      expect(find.text('Required'), findsNWidgets(2));
      expect(backend.callsTo(ApiEndpoints.login), 0);
    });

    testWidgets('a rejected password explains itself and lets you retry',
        (tester) async {
      final FakeBackend backend = await openLogin(tester, resetAuthWorld);
      backend.onSequence(ApiEndpoints.login, <Reply>[
        const Reply(
          401,
          <String, dynamic>{'message': 'Those details did not match.'},
        ),
        Reply(200, sessionBody(accessToken: 'A9', refreshToken: 'R9')),
      ]);
      backend.on(ApiEndpoints.me, Reply(200, userBody()));

      await submit(tester, identifier: 'kunal@example.com', password: 'wrong');

      expect(find.text('Those details did not match.'), findsOneWidget);
      expect(find.text(shell), findsNothing);
      // A login 401 must not be mistaken for an expired token.
      expect(backend.callsTo(ApiEndpoints.refresh), 0);

      // The form has to come back to life, or one typo strands the user.
      await submit(
        tester,
        identifier: 'kunal@example.com',
        password: 'correct',
      );

      expect(find.text(shell), findsOneWidget);
      expect(secureStore[StorageKeys.accessToken], 'A9');
    });

    testWidgets('a malformed success is reported, not silently accepted',
        (tester) async {
      final FakeBackend backend = await openLogin(tester, resetAuthWorld);
      backend.on(
        ApiEndpoints.login,
        Reply(200, sessionBody(refreshToken: '')),
      );

      await submit(tester, identifier: 'kunal', password: 'pw');

      // A session with no refresh token dies at the first expiry with
      // nothing to renew it, so it is refused at the door instead.
      expect(find.text(shell), findsNothing);
      expect(signInButton(), findsOneWidget);
      expect(secureStore, isEmpty);
    });
  });

  group('sign up', () {
    /// Opens the account form with the nine answers already buffered, which
    /// is the state the onboarding flow hands it in the real app.
    Future<FakeBackend> openAccountForm(WidgetTester tester) async {
      final FakeBackend backend = await seed(
        tester,
        () => resetAuthWorld(
          hasSeenWelcome: true,
          onboardingDraft: completeOnboarding,
        ),
      );
      backend.on(
        ApiEndpoints.checkAvailability,
        const Reply(200, <String, dynamic>{
          'usernameAvailable': true,
          'emailAvailable': true,
        }),
      );
      onboardingBloc.add(const OnboardingStarted());
      await launch(tester);
      navigatorKey.currentState!.pushNamed(AppRoutes.accountDetails);
      await settle(tester);
      expect(find.text('Create your account'), findsOneWidget);
      return backend;
    }

    Future<void> fillAndSubmit(WidgetTester tester) async {
      final Finder fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'iron_kunal');
      await tester.enterText(fields.at(1), 'Kunal Bhardwaj');
      await tester.enterText(fields.at(2), 'kunal@example.com');
      await tester.enterText(fields.at(3), 'Str0ng-pass!');
      await tester.pump();
      await tester.ensureVisible(createButton());
      await tester.pump();
      await tester.tap(createButton());
      await settle(tester);
    }

    testWidgets('creates the account and opens the app', (tester) async {
      final FakeBackend backend = await openAccountForm(tester);
      backend.on(
        ApiEndpoints.signup,
        Reply(200, sessionBody(accessToken: 'NEW', refreshToken: 'NEWR')),
      );

      await fillAndSubmit(tester);

      expect(find.text(shell), findsOneWidget);
      expect(secureStore[StorageKeys.accessToken], 'NEW');
      expect(
        StorageService.instance.getBool(StorageKeys.onboardingCompleted),
        isTrue,
      );
      // The draft has served its purpose. Leaving it behind would send the
      // next cold start back into the questionnaire.
      expect(
        StorageService.instance.getJson(StorageKeys.onboardingDraft),
        isNull,
      );
    });

    testWidgets('a taken username is shown on the field that caused it',
        (tester) async {
      final FakeBackend backend = await openAccountForm(tester);
      backend.on(
        ApiEndpoints.signup,
        const Reply(409, <String, dynamic>{
          'message': 'That username is taken',
          'errors': <String, dynamic>{'username': 'Already in use'},
        }),
      );

      await fillAndSubmit(tester);

      expect(find.text('Already in use'), findsOneWidget);
      expect(find.text(shell), findsNothing);
      expect(secureStore, isEmpty);
      // Still usable: the spinner has to clear even on a rejection.
      expect(createButton(), findsOneWidget);
    });
  });

  group('session expiry', () {
    testWidgets('an expiry moves the user out of the signed-in shell',
        (tester) async {
      final FakeBackend backend = await seed(tester, resetSignedIn);
      backend.on(ApiEndpoints.me, Reply(200, userBody()));

      await launch(tester);
      expect(find.text(shell), findsOneWidget);

      // What a failed refresh deep inside some request triggers.
      authBloc.add(const AuthSessionExpired());
      await settle(tester);

      // Nothing on screen initiated this, so nothing on screen would have
      // navigated: the user would have sat on the shell while every call
      // 401'd, with only a restart to get out.
      expect(find.text(shell), findsNothing);
      expect(signInButton(), findsOneWidget);
      // And they are told why, rather than being bounced without a word.
      expect(find.textContaining('session expired'), findsOneWidget);
      expect(secureStore, isEmpty);
    });
  });
}
