import '../models/enums.dart';

/// Conversions between the canonical metric values stored in
/// [OnboardingData] and whatever unit the user is currently viewing.
///
/// Rule of thumb: store metric, display anything.
class UnitConverter {
  const UnitConverter._();

  static const double _cmPerInch = 2.54;
  static const double _kgPerLb = 0.45359237;

  // ---------------------------------------------------------------------
  // Height
  // ---------------------------------------------------------------------

  static double cmToInches(double cm) => cm / _cmPerInch;

  static double inchesToCm(double inches) => inches * _cmPerInch;

  /// Splits total inches into whole feet + remaining inches.
  static ({int feet, int inches}) cmToFeetInches(double cm) {
    final int totalInches = cmToInches(cm).round();
    return (feet: totalInches ~/ 12, inches: totalInches % 12);
  }

  static double feetInchesToCm(int feet, int inches) =>
      inchesToCm((feet * 12) + inches.toDouble());

  /// `172 cm` or `5' 8"` depending on [unit].
  static String formatHeight(double cm, HeightUnit unit) {
    if (unit == HeightUnit.cm) return '${cm.round()} cm';
    final ({int feet, int inches}) fi = cmToFeetInches(cm);
    return "${fi.feet}' ${fi.inches}\"";
  }

  // ---------------------------------------------------------------------
  // Weight
  // ---------------------------------------------------------------------

  static double kgToLbs(double kg) => kg / _kgPerLb;

  static double lbsToKg(double lbs) => lbs * _kgPerLb;

  /// `70.5 kg` or `155 lbs` depending on [unit].
  static String formatWeight(double kg, WeightUnit unit) {
    if (unit == WeightUnit.kg) {
      final double rounded = (kg * 10).round() / 10;
      return '${_trim(rounded)} kg';
    }
    return '${kgToLbs(kg).round()} lbs';
  }

  /// The numeric part only — used by the big hero readout on the pickers.
  static String heightValue(double cm, HeightUnit unit) {
    if (unit == HeightUnit.cm) return '${cm.round()}';
    final ({int feet, int inches}) fi = cmToFeetInches(cm);
    return "${fi.feet}'${fi.inches}";
  }

  static String weightValue(double kg, WeightUnit unit) {
    if (unit == WeightUnit.kg) return _trim((kg * 10).round() / 10);
    return '${kgToLbs(kg).round()}';
  }

  static String _trim(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}
