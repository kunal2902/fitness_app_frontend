import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A discovery category with optional bundled photography.
class DiscoveryCarouselItem {
  const DiscoveryCarouselItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.image,
    this.imageAlignment = Alignment.center,
  });

  final String id;
  final String label;
  final String? subtitle;

  /// Used on the fallback when artwork is unavailable.
  final IconData icon;

  final ImageProvider<Object>? image;
  final Alignment imageAlignment;
  final VoidCallback onTap;
}

/// A horizontally swipeable row of large cards.
///
/// A [PageView] rather than a [ListView] so slides snap and the neighbour
/// peeks in at the edge — without that peek nothing signals there is more to
/// swipe, which is the whole point of choosing a carousel over a grid.
class DiscoveryCarousel extends StatefulWidget {
  const DiscoveryCarousel({
    required this.items,
    this.height = 184,
    super.key,
  });

  final List<DiscoveryCarouselItem> items;
  final double height;

  @override
  State<DiscoveryCarousel> createState() => _DiscoveryCarouselState();
}

class _DiscoveryCarouselState extends State<DiscoveryCarousel> {
  late final PageController _controller;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: _viewportFraction);
    _controller.addListener(_onScroll);
  }

  /// Narrower on a phone so the next card peeks; nearly full width once the
  /// layout is wide enough that a peek would leave a card stranded.
  static const double _viewportFraction = 0.82;

  void _onScroll() {
    final double page = _controller.page ?? 0;
    // Only the integer-ish neighbourhood changes what is painted, but the
    // indicator tracks the fraction, so rebuild on movement.
    if ((page - _page).abs() > 0.001) {
      setState(() => _page = page);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    // Tall text needs a taller card or the label clips. The app clamps
    // scaling to 1.3, so this cannot run away.
    final double scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final double height = widget.height * math.min(scale, 1.3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            itemCount: widget.items.length,
            itemBuilder: (BuildContext context, int index) {
              final double distance = (index - _page).abs().clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _CarouselCard(
                  item: widget.items[index],
                  // The off-centre card sits back slightly, which reads as
                  // depth and makes the focused slide obvious.
                  restingAmount: distance,
                ),
              );
            },
          ),
        ),
        if (widget.items.length > 1) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _PageDots(count: widget.items.length, page: _page),
        ],
      ],
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({required this.item, required this.restingAmount});

  final DiscoveryCarouselItem item;
  final double restingAmount;

  static const ColorFilter _monochrome = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool hasImage = item.image != null;

    return Transform.scale(
      scale: 1 - restingAmount * 0.04,
      child: Opacity(
        opacity: 1 - restingAmount * 0.25,
        child: Semantics(
          button: true,
          onTap: item.onTap,
          excludeSemantics: true,
          label: item.subtitle == null
              ? item.label
              : '${item.label}. ${item.subtitle}',
          child: Material(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.rMd,
              side: BorderSide(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (hasImage)
                  ColorFiltered(
                    colorFilter: _monochrome,
                    child: Image(
                      image: item.image!,
                      fit: BoxFit.cover,
                      alignment: item.imageAlignment,
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) =>
                          _Fallback(item: item, dark: true),
                      frameBuilder: (context, child, frame, loaded) =>
                          loaded || frame != null
                              ? child
                              : _Fallback(item: item, dark: true),
                    ),
                  )
                else
                  _Fallback(item: item),

                // Keep detail in the photo's upper half and hold contrast
                // behind the text at larger system text sizes.
                if (hasImage)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Color(0x12000000),
                          Color(0x35000000),
                          Color(0xBD000000),
                          Color(0xEA000000),
                        ],
                        stops: <double>[0, 0.40, 0.68, 1],
                      ),
                    ),
                  ),

                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: item.onTap,
                    overlayColor: WidgetStatePropertyAll(
                      (hasImage ? Colors.white : palette.textPrimary)
                          .withValues(alpha: 0.14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Align(
                            alignment: AlignmentDirectional.topEnd,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color:
                                    hasImage ? Colors.black87 : palette.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.xs),
                                child: Icon(
                                  Icons.arrow_outward_rounded,
                                  size: AppSize.iconSm,
                                  color: hasImage
                                      ? Colors.white
                                      : palette.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            item.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleLarge?.copyWith(
                              color: hasImage ? Colors.white : null,
                            ),
                          ),
                          if (item.subtitle != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              item.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: hasImage
                                    ? const Color(0xFFEAEAEA)
                                    : palette.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Text stays legible while a photo decodes, including in light mode.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.item, this.dark = false});

  final DiscoveryCarouselItem item;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return ColoredBox(
      color: dark ? const Color(0xFF252525) : palette.surfaceAlt,
      child: Align(
        alignment: const Alignment(0.75, -0.2),
        child: Icon(
          item.icon,
          size: 104,
          color: (dark ? Colors.white : palette.textPrimary)
              .withValues(alpha: 0.10),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.page});

  final int count;
  final double page;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Row(
      children: <Widget>[
        for (int i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xxs),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 4,
              width: (page.round() == i) ? 18 : 6,
              decoration: BoxDecoration(
                color:
                    (page.round() == i) ? palette.textPrimary : palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}
