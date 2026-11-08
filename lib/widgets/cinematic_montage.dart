import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A compilation built from stills: each frame pushes in slowly and drifts
/// while the next one fades up underneath it.
///
/// This exists because a montage does not actually require a video file. Six
/// licensed photographs, a slow scale and a crossfade read as cinematic, and
/// compared with an MP4 it costs no bundle size, no decoder, and no licensing
/// question beyond the stills already shipped.
///
/// Three details that matter more than the effect:
///
///  * **Memory.** Every image is decoded through [ResizeImage] at roughly the
///    size it will be painted. Full-resolution portrait JPEGs held for six
///    slides would be tens of megabytes of bitmap on a device that has little
///    to spare, for pixels nobody can see behind a scrim.
///  * **Idle cost.** The drive is an [AnimationController] with a ticker from
///    this state, so Flutter stops it automatically whenever an ancestor
///    [TickerMode] goes false — which the tab shell sets for tabs nobody is
///    looking at. No lifecycle wiring needed.
///  * **Motion sensitivity.** With reduce-motion on, this paints the first
///    still and never animates.
///
/// It plays through the sequence [cycles] times and then rests on the last
/// frame, rather than looping for as long as the screen is open. That is a
/// deliberate choice on three counts: a first impression is made in the first
/// pass, frames scheduled forever on a tab someone is reading cost battery for
/// nothing, and an animation that never ends makes `pumpAndSettle` hang in
/// every test that renders this screen. Returning to the tab starts it over,
/// so the motion is there each time you arrive.
class CinematicMontage extends StatefulWidget {
  const CinematicMontage({
    required this.images,
    this.slideDuration = const Duration(seconds: 6),
    this.crossfade = const Duration(milliseconds: 1400),
    this.cycles = 1,
    super.key,
  });

  /// Shown in order and looped. Two or more to animate; one paints as a still.
  final List<ImageProvider<Object>> images;

  /// How long each still holds, including its crossfade out.
  final Duration slideDuration;

  final Duration crossfade;

  /// Passes through the whole sequence before coming to rest. Reset when the
  /// widget becomes visible again.
  final int cycles;

  @override
  State<CinematicMontage> createState() => _CinematicMontageState();
}

class _CinematicMontageState extends State<CinematicMontage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.slideDuration,
  );

  int _index = 0;
  bool _precachedNext = false;
  int _slidesShown = 0;
  bool _wasVisible = false;

  int get _totalSlides => widget.images.length * widget.cycles;
  bool get _finished => _slidesShown >= _totalSlides - 1;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool visible = TickerMode.of(context);
    final bool animate =
        widget.images.length > 1 && !MediaQuery.of(context).disableAnimations;

    // Arriving back on the tab restarts the montage, which is why one pass is
    // enough: there is a fresh one every time the screen is opened.
    if (visible && !_wasVisible) {
      _slidesShown = 0;
      _index = 0;
      _precachedNext = false;
      if (animate) _controller.forward(from: 0);
    } else if (animate && !_finished && !_controller.isAnimating) {
      _controller.forward(from: _controller.value);
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
    _wasVisible = visible;
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_finished) {
      // Rest here. The controller stops scheduling frames, so the screen goes
      // idle and `pumpAndSettle` can return.
      return;
    }
    setState(() {
      _slidesShown += 1;
      _index = (_index + 1) % widget.images.length;
      _precachedNext = false;
    });
    _controller.forward(from: 0);
  }

  ImageProvider<Object> _sized(ImageProvider<Object> image, double width) {
    // Decode near the painted size. The card is a few hundred logical pixels
    // wide; decoding a 1080-wide portrait JPEG for it wastes several megabytes
    // per slide.
    final double pixels = width * MediaQuery.devicePixelRatioOf(context);
    return ResizeImage(
      image,
      width: math.max(320, pixels).round(),
      policy: ResizeImagePolicy.fit,
    );
  }

  int get _nextIndex => (_index + 1) % widget.images.length;

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        // Fetched a frame ahead so a slide never fades up into a blank.
        if (!_precachedNext && widget.images.length > 1) {
          _precachedNext = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _precache(context, _sized(widget.images[_nextIndex], width));
          });
        }

        return AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? _) {
            final double t = _controller.value;
            final double fadeStart = 1 -
                (widget.crossfade.inMilliseconds /
                        math.max(1, widget.slideDuration.inMilliseconds))
                    .clamp(0.0, 0.9);
            // Outgoing slide's opacity over the tail of its own run.
            final double outgoing = t <= fadeStart
                ? 1
                : 1 - ((t - fadeStart) / (1 - fadeStart)).clamp(0.0, 1.0);

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (widget.images.length > 1)
                  _Slide(
                    image: _sized(widget.images[_nextIndex], width),
                    // The incoming frame starts its push-in already underway,
                    // so the cut never looks like a jump.
                    progress: 0,
                  ),
                Opacity(
                  opacity: outgoing,
                  child: _Slide(
                    image: _sized(widget.images[_index], width),
                    progress: t,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// One still, pushed in and drifted by [progress] from 0 to 1.
class _Slide extends StatelessWidget {
  const _Slide({required this.image, required this.progress});

  final ImageProvider<Object> image;
  final double progress;

  @override
  Widget build(BuildContext context) {
    // Subtle on purpose: a background that visibly zooms is distracting, and
    // at this size anything stronger also shows compression artefacts.
    final double scale = 1.04 + 0.10 * progress;
    final double drift = -0.06 * progress;

    return Transform.scale(
      scale: scale,
      alignment: Alignment(drift, drift * 0.5),
      child: Image(
        image: image,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

/// `precacheImage` returns a future nobody needs here; a failed prefetch just
/// means the slide decodes a frame later instead.
void _precache(BuildContext context, ImageProvider<Object> image) {
  precacheImage(image, context, onError: (Object _, StackTrace? __) {});
}
