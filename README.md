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

### Reusable meals

Any non-empty breakfast, lunch, dinner, or snack in the Nutrition diary can be
saved with its bookmark action. **Saved meals** in food search lists the
member's private templates and adds one to the currently selected diary day.
When food search was opened from the general **Log food** button, the member is
asked which meal slot to use. Reuse keeps one client id across retries, so a
lost response cannot add the same meal twice; deleting a template never changes
existing diary entries.

### Outdoor workout recorder

The Tracking tab now contains the Android Step 1 recorder: an explicit
permission rationale, precise-location and notification flow, acquiring GPS,
and start/pause/resume/finish/discard controls. A native location foreground
service updates the ongoing duration/distance notification and commits every
raw GPS fix to local SQLite as it arrives. It does not request
`ACCESS_BACKGROUND_LOCATION`, upload routes, or calculate final pace/splits;
those remain later tracking steps. See [TRACKING_STEP1.md](TRACKING_STEP1.md).

### Authentication

`AuthBloc` owns the session, `ApiClient` keeps it alive (attaching the token,
refreshing on 401 and replaying the request), and `AuthService` decides
whether a response is a session at all — a 200 without a usable token pair is
refused rather than accepted into a half-signed-in state. Tokens live only in
the keystore; `AppStore`'s copy can lag a rotation, so anything the server
acts on reads through `AppStore.currentRefreshToken()`. Only a 401 or 403
from the refresh endpoint ends a session: offline, timeouts, 5xx and 429 keep
it. An involuntary expiry is navigated by `AuthSessionGate`, since no screen
knows it happened. See [AUTH.md](AUTH.md).

### Route processor

`RouteProcessor.process` in [lib/utils/route_processor.dart](lib/utils/route_processor.dart)
turns the recorder's raw fixes into distance, moving and recorded time, pace,
per-kilometre splits, smoothed elevation and an encoded polyline. It is pure
Dart — no I/O, no channels, no clock — so all 32 of its tests run without a
device. It filters aggressively (accuracy, mock provider, impossible speed) and
never bridges a pause or a signal gap with a straight line, so its distance,
not the notification's, is the authority. See
[TRACKING_STEP2.md](TRACKING_STEP2.md).

### Route maps

`ActivityRouteMap` renders an activity's encoded route over a dark MapLibre
style with the volt line, start/end markers, optional split markers and
automatic bounds. `ActivityRouteThumbnail` uses the backend's one-time PNG on
history/share surfaces and falls back to a local route drawing when offline.
The style is configurable with `MAP_STYLE_URL`; see
[TRACKING_STEP4.md](TRACKING_STEP4.md) for provider, web and verification setup.

### Device health sync

The Tracking tab can connect read-only Health Connect or Apple Health data for
steps, active calories, resting heart rate, SpO₂ and weight. It creates daily
summaries on-device, uses per-record-type change tokens on Android, keeps iOS
timestamp cursors, and schedules an optional connectivity-aware background
refresh. BMI comes only from the member's profile measurements. Permission,
provider-installation and phone/wearable empty states are built into the card;
see [TRACKING_STEP5.md](TRACKING_STEP5.md) for platform setup, the VO₂ package
limitation and the physical-device release checklist.

### Tracking experience

The Tracking tab now combines daily steps/active-energy rings, wearable-aware
metric cards and recent activities with static route thumbnails. An active
workout shows its live map, duration, distance and pace; Finish processes and
idempotently saves the route before clearing its local session. Activity detail
adds the interactive map, splits, elevation and heart-rate sections with honest
aggregate or empty fallbacks when sampled chart data was not stored. See
[TRACKING_STEP6.md](TRACKING_STEP6.md) for the complete UI and retry behavior.

---

## Adding a custom font

Drop the files in `assets/fonts/`, declare them under `fonts:` in
`pubspec.yaml`, then set `AppTypography.fontFamily`. Every style inherits
from it — nothing else changes.
