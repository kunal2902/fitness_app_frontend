import '../config/app_config.dart';

/// Form validation shared by the account details screen.
///
/// These rules intentionally mirror the backend's Zod/mongoose validators.
/// If you change one side, change the other — the backend is the source of
/// truth and will reject anything that slips through here.
class Validators {
  const Validators._();

  /// Deliberately identical to the rule Zod applies on the backend.
  ///
  /// Keeping these in lockstep matters in both directions: a laxer client
  /// lets someone fill the whole form and only fail on submit, and a
  /// stricter client locks people out entirely — an apostrophe in the local
  /// part (o'brien@…) is legal and common.
  static final RegExp _emailRe = RegExp(
    r"^(?!\.)(?!.*\.\.)([A-Za-z0-9_'+\-\.]*)[A-Za-z0-9_+-]"
    r'@([A-Za-z0-9][A-Za-z0-9\-]*\.)+[A-Za-z]{2,}$',
  );

  /// Letters, digits, underscore and dot; must start with a letter or digit.
  static final RegExp _usernameRe = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._]*$');

  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');
  static final RegExp _hasDigit = RegExp(r'\d');

  static String? username(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Pick a username';
    if (v.length < AppConfig.usernameMinLength) {
      return 'At least ${AppConfig.usernameMinLength} characters';
    }
    if (v.length > AppConfig.usernameMaxLength) {
      return 'At most ${AppConfig.usernameMaxLength} characters';
    }
    if (!_usernameRe.hasMatch(v)) {
      return 'Letters, numbers, dot and underscore only';
    }
    if (v.endsWith('.') || v.endsWith('_')) {
      return 'Cannot end with a dot or underscore';
    }
    if (v.contains('..') || v.contains('__')) {
      return 'No repeated dots or underscores';
    }
    return null;
  }

  static String? fullName(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your full name';
    if (v.length < AppConfig.fullNameMinLength) {
      return 'That looks too short';
    }
    if (v.length > AppConfig.fullNameMaxLength) {
      return 'At most ${AppConfig.fullNameMaxLength} characters';
    }
    if (!_hasLetter.hasMatch(v)) return 'Use letters, not just symbols';
    return null;
  }

  static String? email(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your email';
    if (!_emailRe.hasMatch(v)) return 'That email does not look right';
    return null;
  }

  static String? password(String? value) {
    final String v = value ?? '';
    if (v.isEmpty) return 'Choose a password';
    if (v.length < AppConfig.passwordMinLength) {
      return 'At least ${AppConfig.passwordMinLength} characters';
    }
    if (v.length > AppConfig.passwordMaxLength) {
      return 'At most ${AppConfig.passwordMaxLength} characters';
    }
    if (!_hasLetter.hasMatch(v)) return 'Include at least one letter';
    if (!_hasDigit.hasMatch(v)) return 'Include at least one number';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Re-enter your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  /// 0.0 – 1.0, for the strength meter under the password field.
  static double passwordStrength(String value) {
    if (value.isEmpty) return 0;
    int score = 0;
    if (value.length >= AppConfig.passwordMinLength) score++;
    if (value.length >= 12) score++;
    if (_hasLetter.hasMatch(value) && _hasDigit.hasMatch(value)) score++;
    if (RegExp(r'[A-Z]').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return (score / 5).clamp(0, 1).toDouble();
  }

  static String strengthLabel(double strength) {
    if (strength <= 0) return '';
    if (strength < 0.4) return 'Weak';
    if (strength < 0.7) return 'Fair';
    if (strength < 0.9) return 'Strong';
    return 'Excellent';
  }
}
