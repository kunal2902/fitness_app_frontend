import 'dart:io';

import 'package:fitness_app/screens/home/discovery_artwork.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fallback chain behind every exercise card's background.
///
/// It exists so 78 exercises do not need 78 photographs: a card borrows the
/// artwork for the kit it needs, or failing that the region it trains.
void main() {
  String? pathOf(AssetImage? image) => image?.assetName;

  group('category artwork', () {
    test('a known muscle group and equipment item resolve to a bundled file',
        () {
      expect(pathOf(DiscoveryArtwork.muscle('chest')), 'assets/muscles/chest.jpg');
      expect(
        pathOf(DiscoveryArtwork.equipment('gymnastic_rings')),
        'assets/equipment/gymnastic_rings.jpg',
      );
    });

    test('an unknown id resolves to nothing rather than a missing file', () {
      // An AssetImage for a file that is not bundled fails on every build, so
      // the sets are the guard: only ids with real files may resolve.
      expect(DiscoveryArtwork.muscle('tentacles'), isNull);
      expect(DiscoveryArtwork.equipment('kayak'), isNull);
    });
  });

  group('bundled files match the declared ids', () {
    // The failure this catches: an id added to a set without its file, which
    // the analyzer cannot see and which only shows up as a broken image on a
    // device. And the reverse — a paid-for photo nobody wired up.
    const List<String> groups = <String>[
      'chest', 'back', 'shoulders', 'arms',
      'core', 'hips', 'thighs', 'lower_legs',
    ];

    test('every muscle group resolves to a file that exists', () {
      for (final String id in groups) {
        final AssetImage? art = DiscoveryArtwork.muscle(id);
        expect(art, isNotNull, reason: '$id is not declared');
        expect(
          File(art!.assetName).existsSync(),
          isTrue,
          reason: '${art.assetName} is declared but not on disk',
        );
      }
    });

    test('every equipment photo on disk is declared, and vice versa', () {
      final Directory dir = Directory('assets/equipment');
      expect(dir.existsSync(), isTrue);

      final List<String> onDisk = <String>[
        for (final FileSystemEntity file in dir.listSync())
          if (file.path.endsWith('.jpg'))
            file.uri.pathSegments.last.replaceAll('.jpg', ''),
      ]..sort();

      for (final String id in onDisk) {
        expect(
          DiscoveryArtwork.equipment(id),
          isNotNull,
          reason: '$id.jpg is bundled but no card will ever show it',
        );
      }
      for (final String id in onDisk) {
        final AssetImage art = DiscoveryArtwork.equipment(id)!;
        expect(File(art.assetName).existsSync(), isTrue);
      }
    });

    test('the photo credits name every bundled image', () {
      // The Pexels licence does not require attribution, but the credits file
      // is how the licence trail survives someone asking later.
      final String credits = File(DiscoveryArtwork.creditsAsset)
          .readAsStringSync();
      for (final String id in groups) {
        expect(
          credits,
          contains('muscles/$id.jpg'),
          reason: 'muscles/$id.jpg is bundled but uncredited',
        );
      }
      for (final FileSystemEntity file
          in Directory('assets/equipment').listSync()) {
        if (!file.path.endsWith('.jpg')) continue;
        final String name = file.uri.pathSegments.last;
        expect(
          credits,
          contains('equipment/$name'),
          reason: 'equipment/$name is bundled but uncredited',
        );
      }
    });
  });

  group('exercise artwork precedence', () {
    test('required equipment is preferred over the muscle group', () {
      // A dumbbell curl is more recognisable as the dumbbell photo than as a
      // generic arms photo.
      expect(
        pathOf(
          DiscoveryArtwork.exercise(
            exerciseId: 'dumbbell_curl',
            equipmentIds: const <String>['dumbbell_pair'],
            muscleGroup: 'arms',
          ),
        ),
        'assets/equipment/dumbbell_pair.jpg',
      );
    });

    test('the first equipment id with artwork wins', () {
      expect(
        pathOf(
          DiscoveryArtwork.exercise(
            exerciseId: 'weighted_dip',
            // An "any of" group can name items with no photo; the resolver
            // keeps looking instead of giving up on the first miss.
            equipmentIds: const <String>['no_such_kit', 'dip_bar'],
            muscleGroup: 'chest',
          ),
        ),
        'assets/equipment/dip_bar.jpg',
      );
    });

    test('a bodyweight movement falls back to its muscle group', () {
      // push_up has no required equipment at all, which is exactly the case
      // the group fallback exists for.
      expect(
        pathOf(
          DiscoveryArtwork.exercise(
            exerciseId: 'push_up',
            muscleGroup: 'chest',
          ),
        ),
        'assets/muscles/chest.jpg',
      );
    });

    test('nothing resolvable yields null so the card draws its gradient', () {
      expect(
        DiscoveryArtwork.exercise(
          exerciseId: 'unknown_move',
          equipmentIds: const <String>['no_such_kit'],
        ),
        isNull,
      );
      expect(
        DiscoveryArtwork.exercise(
          exerciseId: 'unknown_move',
          muscleGroup: 'not_a_group',
        ),
        isNull,
      );
    });

    test('every exercise in the catalogue can resolve some artwork', () {
      // The point of the chain: no card is left without an image. Each entry
      // is (equipment ids, primary muscle group) as the library would pass
      // them, covering the new equipment families and the bodyweight ones.
      const Map<String, (List<String>, String)> cases =
          <String, (List<String>, String)>{
        'barbell_back_squat': (<String>['barbell'], 'thighs'),
        'box_jump': (<String>['plyo_box'], 'thighs'),
        'parallel_bar_dip': (<String>['dip_bar', 'parallettes'], 'chest'),
        'parallette_l_sit': (<String>['parallettes'], 'core'),
        'ring_row': (<String>['gymnastic_rings'], 'back'),
        'jump_rope_double_under': (<String>['jump_rope'], 'lower_legs'),
        'weighted_plank': (<String>['weighted_vest'], 'core'),
        'push_up': (<String>[], 'chest'),
        'hollow_body_hold': (<String>[], 'core'),
        'standing_calf_raise': (<String>[], 'lower_legs'),
      };

      for (final MapEntry<String, (List<String>, String)> entry
          in cases.entries) {
        final (List<String> equipment, String group) = entry.value;
        expect(
          DiscoveryArtwork.exercise(
            exerciseId: entry.key,
            equipmentIds: equipment,
            muscleGroup: group,
          ),
          isNotNull,
          reason: '${entry.key} has no artwork to fall back on',
        );
      }
    });
  });
}
