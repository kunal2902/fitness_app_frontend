import 'package:flutter/widgets.dart';

/// Bundled stock artwork for discovery categories. The catalogue still owns
/// which equipment appears and how it is labelled.
abstract final class DiscoveryArtwork {
  static const String creditsAsset = 'assets/discovery_photo_credits.txt';

  static const Set<String> _muscles = <String>{
    'chest',
    'back',
    'shoulders',
    'arms',
    'core',
    'hips',
    'thighs',
    'lower_legs',
  };

  static const Set<String> _equipment = <String>{
    'wall',
    'elevated_support',
    'pull_up_bar',
    'low_row_bar',
    'resistance_band',
    'dumbbell_pair',
    'dumbbell',
    'kettlebell',
    'flat_bench',
    'adjustable_bench',
    'band_anchor',
    'exercise_mat',
    'barbell',
    'plyo_box',
    'dip_bar',
    'parallettes',
    'gymnastic_rings',
    'jump_rope',
    'weighted_vest',
  };

  /// Per-exercise artwork, for the few movements worth their own photograph.
  ///
  /// Empty on purpose. An [AssetImage] for a file that is not bundled fails on
  /// every build, so an id only belongs here once `assets/exercises/<id>.jpg`
  /// actually exists. Everything else is served by [exercise]'s fallbacks,
  /// which is why 78 exercises do not need 78 photographs.
  static const Set<String> _exercises = <String>{};

  static AssetImage? muscle(String id) =>
      _muscles.contains(id) ? AssetImage('assets/muscles/$id.jpg') : null;

  static AssetImage? equipment(String id) =>
      _equipment.contains(id) ? AssetImage('assets/equipment/$id.jpg') : null;

  /// Artwork for one exercise, most specific first.
  ///
  /// 1. its own photograph, when one is bundled;
  /// 2. the kit it needs — a dumbbell curl over the dumbbell photo;
  /// 3. the muscle group it trains, which is what bodyweight movements fall
  ///    back to since they have no equipment to show.
  ///
  /// Null when none of those resolve, and the card then draws its gradient.
  ///
  /// This is **category** artwork, not instruction: a photograph of a barbell
  /// is not a demonstration of a barbell row. It belongs on a card the user
  /// taps, and deliberately not in `ExerciseDemo`, where a stock photo
  /// standing in for a demonstration would teach the movement wrong.
  ///
  /// An approved poster from the catalogue outranks all of this; callers check
  /// that first, because it is the only image that actually shows the
  /// movement.
  static AssetImage? exercise({
    required String exerciseId,
    Iterable<String> equipmentIds = const <String>[],
    String? muscleGroup,
  }) {
    if (_exercises.contains(exerciseId)) {
      return AssetImage('assets/exercises/$exerciseId.jpg');
    }
    for (final String id in equipmentIds) {
      final AssetImage? art = equipment(id);
      if (art != null) return art;
    }
    return muscleGroup == null ? null : muscle(muscleGroup);
  }
}
