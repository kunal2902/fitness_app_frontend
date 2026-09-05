import 'package:flutter/material.dart';

import '../models/nutrition_models.dart';
import 'app_colors.dart';

/// The three macronutrient series colours.
///
/// Protein, carbs and fat are **identities**, not magnitudes, so they get a
/// fixed categorical order that is never cycled or reassigned — the colour
/// follows the nutrient, never its size or its rank in a sorted list.
///
/// These are deliberately NOT the interface accent. `palette.accent` is
/// volt, and reusing it for a data series would make "the brand colour" and
/// "protein" the same thing — so a protein bar next to a primary button
/// would read as related when it is not. Same reasoning that keeps
/// `AppColors.success`/`warning`/`danger` reserved for state.
///
/// The specific steps were not chosen by eye. The triad was run through the
/// palette validator against both surfaces and passes every check:
///
/// ```
/// #6E9B0A, #3A63D6, #FF4D2E   (voltDeep, electricDim, emberDim)
///   lightness band     inside L 0.48–0.67 dark / 0.43–0.77 light
///   chroma floor       all >= 0.10
///   CVD separation     worst adjacent ΔE 27.1 protan, 11.5 tritan
///   normal vision      worst adjacent ΔE 33.6
///   contrast           all >= 3:1 on both surfaces
/// ```
///
/// The brighter `volt` / `electric` / `ember` steps fail the lightness
/// band — volt sits at L 0.93, so a protein bar would visually dominate a
/// carbs bar of the same length. If you restyle these, re-run the
/// validator rather than picking by taste; the band is what stops one
/// nutrient shouting over the others.
class MacroPalette {
  const MacroPalette._();

  static const Color protein = AppColors.voltDeep;
  static const Color carbs = AppColors.electricDim;
  static const Color fat = AppColors.emberDim;

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
