/// Defensive coercion for JSON that crosses the auth boundary.
///
/// Every other layer can afford to assume the backend sends what it
/// promised. Auth cannot: a payload that does not parse the way the model
/// expects throws a `TypeError`, which is not an `ApiException`, so it
/// escapes the `on ApiException` handlers in `AuthBloc` and kills the bloc
/// mid-transition — leaving the sign-in button spinning with no way out but
/// restarting the app.
///
/// These helpers turn "unexpected shape" into "empty value", which the
/// validation in `AuthService` then reports as an ordinary, retryable
/// failure.
library;

/// A string map from anything map-shaped, including the `Map<dynamic, dynamic>`
/// that `jsonDecode` hands back for a nested object in some code paths.
Map<String, dynamic>? asStringMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry<String, dynamic>(
        key.toString(),
        item,
      ),
    );
  }
  return null;
}

/// A string from anything, and `''` from null. Never throws, so a server
/// that sends a number where a string belongs costs us a validation error
/// rather than a crash.
String asString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}
