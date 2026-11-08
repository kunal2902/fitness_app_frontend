import 'package:flutter/material.dart';

import '../models/nutrition_models.dart';

/// The three macronutrient series colours.
///
/// Protein, carbs and fat are **identities**, not magnitudes, so they get a
/// fixed categorical order that is never cycled or reassigned — the colour
/// follows the nutrient, never its size or its rank in a sorted list.
///
/// Fixed data colors keep each nutrient recognizable across both interface
/// appearances. The meter also shows a label and grams for every nutrient.
///
/// The specific steps were not chosen by eye. The triad was run through the
/// palette validator against both surfaces and passes every check:
///
/// ```
/// #6E9B0A, #3A63D6, #FF4D2E
///   lightness band     inside L 0.48–0.67 dark / 0.43–0.77 light
///   chroma floor       all >= 0.10
///   CVD separation     worst adjacent ΔE 27.1 protan, 11.5 tritan
///   normal vision      worst adjacent ΔE 33.6
///   contrast           all >= 3:1 on both surfaces
/// ```
///
/// Keep the lightness band when updating these values so equal lengths
/// have similar visual weight.
class MacroPalette {
  const MacroPalette._();

  static const Color protein = Color(0xFF6E9B0A);
  static const Color carbs = Color(0xFF3A63D6);
  static const Color fat = Color(0xFFFF4D2E);

  /// Fixed order. Iterate this, never `Map.values` on an unordered map.
  static const List<MacroKind> order = <MacroKind>[
    MacroKind.protein,
    MacroKind.carbs,
    MacroKind.fat,
  ];

  static Color of(MacroKind kind) => switch (kind) {
        MacroKind.protein => protein,
        MacroKind.carbs => carbs,
        MacroKind.fat => fat,
      };
}

/// One macronutrient, with everything a meter needs to render itself.
///
/// Exists so the summary card can loop over three identical rows instead of
/// repeating the same widget three times with different field accessors —
/// which is how the labels and the values drift apart.
enum MacroKind {
  protein('Protein'),
  carbs('Carbs'),
  fat('Fat');

  const MacroKind(this.label);

  final String label;

  double gramsIn(Macros macros) => switch (this) {
        MacroKind.protein => macros.proteinG,
        MacroKind.carbs => macros.carbsG,
        MacroKind.fat => macros.fatG,
      };
}
