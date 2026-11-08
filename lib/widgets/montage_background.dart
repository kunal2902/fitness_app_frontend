import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'cinematic_montage.dart';

/// A looping, muted background clip with a still poster behind it.
///
/// Built for one place: the Exercise library card, which is the first thing a
/// signed-in user sees. A montage there earns its keep; a montage on every
/// card would not.
///
/// Four things decide whether the clip actually plays, and all four can veto:
///
///  * **Is it bundled.** [asset] must be listed in [bundledAssets]. A
///    `VideoPlayerController.asset` for a missing file throws on init, and a
///    const set is the only check that works before the file exists.
///  * **Does the platform play video.** The same check `ExerciseDemo` makes.
///  * **Does the user want motion.** `MediaQuery.disableAnimations` reflects
///    the OS reduce-motion setting. Someone who turned that on because moving
///    backgrounds make them ill should not be shown one on the home screen.
///  * **Is it on screen.** `TickerMode` is false for the tabs the shell is not
///    showing, and the app lifecycle covers backgrounding. Without both, a
///    decode loop runs while the user reads their nutrition diary — the kind
///    of thing that shows up as heat on a budget phone, not as a bug report.
///
/// Three tiers, best available first:
///
///  1. the bundled clip, when there is one and nothing vetoes it;
///  2. [stills] driven by [CinematicMontage] — a push-in-and-crossfade
///     compilation built from photographs already licensed for the app, which
///     is motion without an MP4 in the bundle;
///  3. [poster] alone.
///
/// The bottom tier is painted first and never removed, so there is no blank
/// frame at any point and a failure degrades one tier rather than to a hole.
class MontageBackground extends StatefulWidget {
  const MontageBackground({
    required this.child,
    this.asset,
    this.poster,
    this.stills = const <ImageProvider<Object>>[],
    this.overlayOpacity = 0.62,
    super.key,
  });

  /// Asset path of the clip, e.g. `assets/video/library_montage.mp4`.
  final String? asset;

  /// Still frame shown underneath, and on its own when nothing else can run.
  final ImageProvider<Object>? poster;

  /// Photographs to compile into a moving montage when no clip is bundled.
  /// Two or more animate; fewer falls through to [poster].
  final List<ImageProvider<Object>> stills;

  final Widget child;

  /// Scrim strength over the footage. The card's text sits on top, and video
  /// is far busier than a photograph, so this is heavier than the carousel's.
  final double overlayOpacity;

  /// Clips that are actually in the bundle. Add the path here when the file
  /// lands; until then this widget renders the poster and never builds a
  /// controller.
  static const Set<String> bundledAssets = <String>{};

  static bool get playbackSupported =>
      kIsWeb ||
      const <TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  @override
  State<MontageBackground> createState() => _MontageBackgroundState();
}

class _MontageBackgroundState extends State<MontageBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _player;
  bool _starting = false;
  bool _failed = false;
  bool _appResumed = true;

  bool get _wanted =>
      !_failed &&
      widget.asset != null &&
      MontageBackground.bundledAssets.contains(widget.asset) &&
      MontageBackground.playbackSupported &&
      !MediaQuery.of(context).disableAnimations;

  bool get _visible => TickerMode.of(context) && _appResumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode and the reduce-motion flag both arrive through the element
    // tree, so this is where a tab change or a settings change shows up.
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final bool resumed = state == AppLifecycleState.resumed;
    if (resumed == _appResumed) return;
    _appResumed = resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final VideoPlayerController? player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  void _sync() {
    if (!_wanted) {
      _release();
      return;
    }
    if (!_visible) {
      unawaited(_player?.pause());
      return;
    }
    final VideoPlayerController? player = _player;
    if (player == null) {
      unawaited(_start());
    } else if (!player.value.isPlaying) {
      unawaited(player.play());
    }
  }

  void _release() {
    final VideoPlayerController? player = _player;
    if (player == null) return;
    setState(() => _player = null);
    unawaited(player.dispose());
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    final VideoPlayerController player =
        VideoPlayerController.asset(widget.asset!);
    try {
      await player.initialize().timeout(const Duration(seconds: 10));
      await player.setLooping(true);
      // Silent is not optional: audio on a background loop is hostile, and on
      // iOS it would also stop whatever the user was listening to.
      await player.setVolume(0);
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() => _player = player);
      if (_visible && _wanted) {
        await player.play();
      }
    } on Object {
      await player.dispose();
      if (!mounted) return;
      // One failure is enough — retrying a bundled asset that did not
      // initialise will not start working, and the poster is a fine outcome.
      setState(() {
        _failed = true;
        _player = null;
      });
    } finally {
      _starting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = _player;
    final bool ready = player != null && player.value.isInitialized;
    // Only one moving layer at a time: compiling stills behind a playing clip
    // would decode images nobody can see.
    final bool showStills = !ready &&
        widget.stills.length > 1 &&
        !MediaQuery.of(context).disableAnimations;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: widget.poster == null
                  ? null
                  : Image(
                      image: widget.poster!,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
          ),
          if (showStills)
            Positioned.fill(child: CinematicMontage(images: widget.stills)),
          if (ready)
            Positioned.fill(
              // The clip will not match the card's aspect ratio. Cover it by
              // sizing to the video's own ratio inside a FittedBox, which
              // crops rather than letterboxing.
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: player.value.size.width,
                  height: player.value.size.height,
                  child: VideoPlayer(player),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(
                      alpha: widget.overlayOpacity * 0.55,
                    ),
                    Colors.black.withValues(alpha: widget.overlayOpacity),
                  ],
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}
