/// Normalised error the UI can render without knowing anything about Dio.
///
/// The API client converts every failure — network, timeout, 4xx, 5xx,
/// malformed payload — into one of these.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.fieldErrors = const <String, String>{},
  });

  /// Human-readable, safe to show in a snackbar.
  final String message;

  final int? statusCode;

  /// Machine-readable code from the backend, e.g. `EMAIL_TAKEN`.
  final String? code;

  /// Per-field validation messages, keyed by field name, so a form can
  /// highlight the exact input that failed.
  final Map<String, String> fieldErrors;

  bool get isNetworkError => statusCode == null;
  bool get isUnauthorized => statusCode == 401;
  bool get isConflict => statusCode == 409;
  bool get isValidationError => statusCode == 422 || fieldErrors.isNotEmpty;

  const ApiException.network()
      : message = 'No internet connection. Check your network and try again.',
        statusCode = null,
        code = 'NETWORK',
        fieldErrors = const <String, String>{};

  const ApiException.timeout()
      : message = 'The server took too long to respond. Please try again.',
        statusCode = null,
        code = 'TIMEOUT',
        fieldErrors = const <String, String>{};

  const ApiException.unknown()
      : message = 'Something went wrong. Please try again.',
        statusCode = null,
        code = 'UNKNOWN',
        fieldErrors = const <String, String>{};

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
