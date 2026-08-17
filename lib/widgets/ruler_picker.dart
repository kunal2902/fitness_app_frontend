import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Horizontal ruler used by the height and weight questions.
///
/// Behaves like a physical dial: you fling it, it decelerates, then snaps to
/// the nearest tick with a light haptic tick on every value change.
///
/// Two callbacks on purpose, mirroring [Slider]:
///  * [onChanged] fires continuously while scrolling — drive the big number
///    readout with it, but do **not** persist from here.
///  * [onChangeEnd] fires once the ruler settles — that's where you dispatch
///    the BLoC event that writes to SharedPreferences.
class RulerPicker extends StatefulWidget {
  const RulerPicker({
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.step = 1,
    this.majorEvery = 5,
    this.tickSpacing = 14,
    this.height = AppSize.rulerHeight,
    this.labelBuilder,
    super.key,
  });

  /// Range in the *displayed* unit (cm, inches, kg or lbs).
  final double min;
  final double max;
  final double value;

  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  /// Distance between two ticks in the displayed unit.
  final double step;

  /// Every Nth tick is drawn tall and labelled.
  final int majorEvery;

  /// Pixel gap between ticks.
  final double tickSpacing;

  final double height;

  /// Text under a major tick. Defaults to the rounded value.
  final String Function(double value)? labelBuilder;

  @override
  State<RulerPicker> createState() => _RulerPickerState();
}

class _RulerPickerState extends State<RulerPicker> {
  late ScrollController _controller;
  late int _index;
  bool _isSettling = false;

  int get _itemCount =>
      ((widget.max - widget.min) / widget.step).round() + 1;

  double _valueAt(int index) => widget.min + (index * widget.step);

  int _indexOf(double value) {
    final int raw = ((value - widget.min) / widget.step).round();
    return raw.clamp(0, _itemCount - 1).toInt();
  }

  @override
  void initState() {
    super.initState();
    _index = _indexOf(widget.value);
    _controller = ScrollController(
      initialScrollOffset: _index * widget.tickSpacing,
    );
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant RulerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool rangeChanged = oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.step != widget.step;

    // Only jump for an externally-driven change — ignore the echo of our
    // own onChanged, which would fight the user's finger.
    final bool valueChangedExternally =
        (widget.value - _valueAt(_index)).abs() > widget.step / 2;

    if (rangeChanged || valueChangedExternally) {
      _index = _indexOf(widget.value);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpTo(_index * widget.tickSpacing);
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients || _isSettling) return;
    final int next = (_controller.offset / widget.tickSpacing)
        .round()
        .clamp(0, _itemCount - 1)
        .toInt();
    if (next == _index) return;

    setState(() => _index = next);
    HapticFeedback.selectionClick();
    widget.onChanged(_valueAt(next));
  }

  Future<void> _snap() async {
    if (!_controller.hasClients) return;
    final double target = _index * widget.tickSpacing;
    if ((_controller.offset - target).abs() < 0.5) {
      widget.onChangeEnd(_valueAt(_index));
      return;
    }

    _isSettling = true;
    await _controller.animateTo(
      target,
      duration: AppDuration.fast,
      curve: Curves.easeOut,
    );
    _isSettling = false;
    if (!mounted) return;
    widget.onChangeEnd(_valueAt(_index));
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification && !_isSettling) {
      _snap();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double sidePadding =
              (constraints.maxWidth - widget.tickSpacing) / 2;

          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              NotificationListener<ScrollNotification>(
                onNotification: _onNotification,
                child: ListView.builder(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemExtent: widget.tickSpacing,
                  itemCount: _itemCount,
                  padding: EdgeInsets.symmetric(horizontal: sidePadding),
                  itemBuilder: (BuildContext context, int i) {
                    final bool isMajor = i % widget.majorEvery == 0;
                    return _Tick(
                      isMajor: isMajor,
                      color: isMajor ? palette.textSecondary : palette.border,
                      labelColor: palette.textTertiary,
                      label: isMajor
                          ? (widget.labelBuilder?.call(_valueAt(i)) ??
                              _valueAt(i).round().toString())
                          : null,
                    );
                  },
                ),
              ),

              // Centre indicator.
              IgnorePointer(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: palette.accent,
                      size: 28,
                    ),
                    Container(
                      width: 3,
                      height: widget.height * 0.46,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({
    required this.isMajor,
    required this.color,
    required this.labelColor,
    this.label,
  });

  final bool isMajor;
  final Color color;
  final Color labelColor;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 26),
        Container(
          width: isMajor ? 2.5 : 1.5,
          height: isMajor ? 42 : 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        if (label != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          // The label is wider than the tick's item extent — let it spill
          // symmetrically instead of being squeezed.
          OverflowBox(
            maxWidth: 64,
            alignment: Alignment.topCenter,
            child: Text(
              label!,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: context.text.labelSmall?.copyWith(
                color: labelColor,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
