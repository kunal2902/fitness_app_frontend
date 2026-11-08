import 'package:fitness_app/widgets/cinematic_montage.dart';
import 'package:fitness_app/widgets/montage_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

/// The montage has four independent vetoes, and the expensive failure is a
/// decode loop running where nobody can see it. These pin the vetoes and the
/// poster fallback; the `video_player` plugin has no test harness in a widget
/// test, so "no controller was ever built" is the strongest available signal
/// that nothing is decoding.
void main() {
  Widget host({
    String? asset,
    bool reduceMotion = false,
    bool visible = true,
    ImageProvider<Object>? poster,
    List<ImageProvider<Object>> stills = const <ImageProvider<Object>>[],
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: visible,
            child: MontageBackground(
              asset: asset,
              poster: poster,
              stills: stills,
              child: const Text('CARD BODY'),
            ),
          ),
        ),
      ),
    );
  }

  /// A built controller is the only observable sign the widget tried to play.
  bool hasPlayer(WidgetTester tester) =>
      tester.widgetList<VideoPlayer>(find.byType(VideoPlayer)).isNotEmpty;

  testWidgets('an unbundled clip never builds a player', (tester) async {
    // Nothing is in MontageBackground.bundledAssets, so this is the shipping
    // state: the card must look finished with no clip at all.
    await tester.pumpWidget(host(asset: 'assets/video/library_montage.mp4'));
    await tester.pump();

    expect(hasPlayer(tester), isFalse);
    expect(find.text('CARD BODY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a null asset is fine and renders the child', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(hasPlayer(tester), isFalse);
    expect(find.text('CARD BODY'), findsOneWidget);
  });

  testWidgets('reduce motion suppresses playback', (tester) async {
    await tester.pumpWidget(
      host(asset: 'assets/video/library_montage.mp4', reduceMotion: true),
    );
    await tester.pump();

    // Someone who turned reduce-motion on because moving backgrounds make
    // them ill must not be shown one on the first screen.
    expect(hasPlayer(tester), isFalse);
    expect(find.text('CARD BODY'), findsOneWidget);
  });

  testWidgets('an off-screen tab suppresses playback', (tester) async {
    await tester.pumpWidget(
      host(asset: 'assets/video/library_montage.mp4', visible: false),
    );
    await tester.pump();

    expect(hasPlayer(tester), isFalse);
  });

  testWidgets('the poster is painted and marked decorative', (tester) async {
    await tester.pumpWidget(
      host(poster: const AssetImage('assets/muscles/chest.jpg')),
    );
    await tester.pump();

    final Finder image = find.byType(Image);
    expect(image, findsOneWidget);
    // The card's own text names the destination; a duplicate announcement of
    // the photograph would just be noise to a screen reader.
    expect(tester.widget<Image>(image).excludeFromSemantics, isTrue);
  });

  testWidgets('a scrim is always present so text stays readable',
      (tester) async {
    await tester.pumpWidget(
      host(poster: const AssetImage('assets/muscles/chest.jpg')),
    );
    await tester.pump();

    // Video is far busier than a photograph; without a scrim the label is
    // unreadable over a bright frame.
    final Iterable<DecoratedBox> boxes =
        tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    expect(
      boxes.any((DecoratedBox box) {
        final Decoration decoration = box.decoration;
        return decoration is BoxDecoration && decoration.gradient != null;
      }),
      isTrue,
    );
  });

  testWidgets('switching away and back does not leave an exception',
      (tester) async {
    await tester.pumpWidget(
      host(asset: 'assets/video/library_montage.mp4'),
    );
    await tester.pump();
    await tester.pumpWidget(
      host(asset: 'assets/video/library_montage.mp4', visible: false),
    );
    await tester.pump();
    await tester.pumpWidget(
      host(asset: 'assets/video/library_montage.mp4'),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('CARD BODY'), findsOneWidget);
  });

  group('the stills compilation', () {
    const List<ImageProvider<Object>> sequence = <ImageProvider<Object>>[
      AssetImage('assets/muscles/chest.jpg'),
      AssetImage('assets/muscles/back.jpg'),
      AssetImage('assets/muscles/thighs.jpg'),
    ];

    testWidgets('runs when no clip is bundled, so the card still moves',
        (tester) async {
      await tester.pumpWidget(
        host(asset: 'assets/video/library_montage.mp4', stills: sequence),
      );
      await tester.pump();

      expect(find.byType(CinematicMontage), findsOneWidget);
      expect(hasPlayer(tester), isFalse);
      expect(find.text('CARD BODY'), findsOneWidget);
    });

    testWidgets('advances through the sequence over time', (tester) async {
      await tester.pumpWidget(host(stills: sequence));
      await tester.pump();

      // Two Transform.scale layers: the incoming slide and the outgoing one
      // fading over it. A single still would only ever paint one.
      expect(
        tester.widgetList<Transform>(find.byType(Transform)).length,
        greaterThanOrEqualTo(2),
      );

      // getMaxScaleOnAxis rather than a raw matrix cell: Transform.scale with
      // a non-centre alignment bakes a translation in, so the cells are not
      // the scale.
      double slideScale() => tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(CinematicMontage),
              matching: find.byType(Transform),
            ),
          )
          .last
          .transform
          .getMaxScaleOnAxis();

      final double before = slideScale();
      await tester.pump(const Duration(seconds: 3));
      final double after = slideScale();

      // The push-in is what makes it read as footage rather than a slideshow.
      expect(after, greaterThan(before));
    });

    testWidgets('decodes at painted size rather than full resolution',
        (tester) async {
      await tester.pumpWidget(host(stills: sequence));
      await tester.pump();

      // Six full-resolution portrait JPEGs held as bitmaps would be tens of
      // megabytes for pixels sitting behind a scrim.
      final Iterable<Image> images = tester.widgetList<Image>(
        find.byType(Image),
      );
      expect(images, isNotEmpty);
      expect(
        images.every((Image image) => image.image is ResizeImage),
        isTrue,
      );
    });

    testWidgets('reduce motion falls through to a single still',
        (tester) async {
      await tester.pumpWidget(host(stills: sequence, reduceMotion: true));
      await tester.pump();

      expect(find.byType(CinematicMontage), findsNothing);
      expect(find.text('CARD BODY'), findsOneWidget);
    });

    testWidgets('one still is not a compilation', (tester) async {
      await tester.pumpWidget(
        host(
          stills: const <ImageProvider<Object>>[
            AssetImage('assets/muscles/chest.jpg'),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(CinematicMontage), findsNothing);
    });

    testWidgets('an off-screen tab stops the compilation too', (tester) async {
      await tester.pumpWidget(host(stills: sequence, visible: false));
      await tester.pump(const Duration(seconds: 1));

      // TickerMode false stops the AnimationController, so the slides hold
      // instead of cycling behind a tab nobody is looking at.
      final CinematicMontage? montage = tester
          .widgetList<CinematicMontage>(find.byType(CinematicMontage))
          .firstOrNull;
      if (montage != null) {
        expect(tester.hasRunningAnimations, isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  });

  test('no clip is declared bundled until its file exists', () {
    // The guard that stops a VideoPlayerController.asset throwing on a file
    // that is not in the bundle. Adding a path here without the file is the
    // mistake this records.
    expect(MontageBackground.bundledAssets, isEmpty);
  });
}
