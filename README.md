# Fitness App — Flutter client (Phase 1)

Onboarding questionnaire + end-to-end signup. Everything else (workouts,
weekly plans, tracking, video consults, community, Strava/Healthify) plugs
into this skeleton in later phases.

Requires **Flutter 3.27+ / Dart 3.6+**.

---

## First run

The `lib/` tree is complete but the native host projects are not — those
have to be generated on your machine, because Gradle and Xcode need local
paths.

```bash
cd C:\fitness-app\app_frontend

# Generates android/ and ios/ around the existing lib/.
# --project-name must match `name:` in pubspec.yaml.
flutter create . --org com.fitnessapp --project-name fitness_app

flutter pub get
flutter run
```

> `flutter create` regenerates `lib/main.dart` from its template. If it
> overwrites yours, restore it with `git checkout lib/main.dart` — the app
> will not boot without our version, which initialises storage before
> `runApp`.

### Pointing at the backend

`AppConfig.apiBaseUrl` defaults to `http://10.0.2.2:3000/api/v1`, which is
how the **Android emulator** reaches your host machine's `localhost`.

| Target | Base URL |
| --- | --- |
| Android emulator | `http://10.0.2.2:3000/api/v1` (default) |
| iOS simulator | `http://localhost:3000/api/v1` |
| Physical device | `http://<your-LAN-IP>:3000/api/v1` |

Override without editing code:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:3000/api/v1
flutter run --dart-define=APP_ENV=staging
```

---

## Layout

```
lib/
├── main.dart                  Bootstrap: storage → store → runApp
├── app.dart                   Providers, theme, MaterialApp
│
├── config/                    Nothing hard-coded anywhere else
│   ├── app_config.dart        Env/flavour, base URL, validation bounds
│   ├── api_endpoints.dart     Every backend path
│   └── storage_keys.dart      Every SharedPreferences / keychain key
│
├── theme/                     Design system — no raw hex in any widget
│   ├── app_colors.dart        Palette + AppPalette theme extension
│   ├── app_dimens.dart        Spacing, radii, durations, sizes
│   ├── app_typography.dart    Type scale
│   └── app_theme.dart         Light + dark ThemeData, context.palette
│
├── models/                    Pure data
│   ├── enums.dart             All 9 questions' option sets
│   ├── onboarding_data.dart   The answers + completion + serialisation
│   ├── user_model.dart
│   ├── auth_models.dart       Request/response DTOs
│   └── api_exception.dart     One normalised error type
│
├── store/
│   └── app_store.dart         Global entities: token, refresh token, user,
│                              onboarding draft, theme, first-launch flags
│
├── services/                  I/O only, no state
│   ├── api_client.dart        Dio + bearer injection + token refresh
│   ├── auth_service.dart
│   └── storage_service.dart   SharedPreferences + secure storage
│
├── blocs/                     State machines; persist through the store
│   ├── onboarding/
│   └── auth/
│
├── widgets/                   Generic, reusable
├── cards/                     Selectable surfaces (option, gender, goal)
├── screens/                   One folder per area
│   ├── splash/  welcome/  home/
│   ├── onboarding/            Flow container + steps/ (9 questions)
│   └── auth/                  Account details (signup), login
├── routes/                    Named routes + transitions
└── utils/                     Unit conversion, validators
```

---

## How the signup flow works

1. **Splash** reads the session off disk and routes: home if signed in, the
   onboarding flow if a draft exists, otherwise welcome.
2. **Onboarding** is one screen with a swipeable `PageView` of 9 questions.
   `OnboardingBloc` is the single source of truth for the visible page —
   the `PageController`, the progress bar, the Continue button and the
   Android back gesture all follow it, so none of them can disagree.
3. **Every answer is written to SharedPreferences immediately.** Kill the
   app on question 7 and it reopens on question 7 with all seven answers.
4. **Account details** collects username / full name / email / password,
   checks username and email availability as you type (debounced 550 ms),
   and submits everything — credentials *and* all nine answers — in one
   `POST /auth/signup`. No half-created users.
5. On success the tokens go to the keychain, the user to the store, the
   draft is cleared, and the stack is replaced with **Home**.

### Units

Height and weight are stored **only in metric** (`heightCm`, `weightKg`).
The cm/in and kg/lbs toggles change the ruler and the readout, never the
stored value — so flipping units repeatedly cannot drift the measurement.

### The ruler

`RulerPicker` mirrors `Slider`'s two-callback contract:

- `onChanged` fires continuously while scrolling → drives the big number.
- `onChangeEnd` fires once it settles → dispatches the BLoC event.

Persisting on `onChanged` would write to disk on every frame.

---

## Conventions

- **Never hard-code a colour, gap or radius.** Add a token to `theme/`.
  Read them with `context.palette`, `context.text`, `context.scheme`.
- **Screens never touch `ApiClient`.** They go through a service.
- **Widgets read the store, BLoCs write it.**
- New screen → add it to `routes/app_routes.dart` *and* `app_router.dart`.
- New question → extend `OnboardingData`, add a step widget, register it in
  `OnboardingFlowScreen._steps`, and bump `OnboardingData.totalSteps`.

---

## Adding a custom font

Drop the files in `assets/fonts/`, declare them under `fonts:` in
`pubspec.yaml`, then set `AppTypography.fontFamily`. Every style inherits
from it — nothing else changes.
