import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'section_card.dart';

/// An original, schematic map of exercise targets, with the same information
/// available by name for assistive technology and for muscles added later.
class ExerciseMuscleMap extends StatefulWidget {
  const ExerciseMuscleMap({
    required this.primary,
    required this.secondary,
    this.onMuscleTap,
    super.key,
  });

  final Map<String, String> primary;
  final Map<String, String> secondary;
  final ValueChanged<String>? onMuscleTap;

  @override
  State<ExerciseMuscleMap> createState() => _ExerciseMuscleMapState();
}

class _ExerciseMuscleMapState extends State<ExerciseMuscleMap> {
  late bool _back = _MusclePainter.startOnBack(widget.primary.keys);
  String? _selectedId;

  void _browseMuscle(String id) {
    setState(() {
      _selectedId = id;
      _back = _MusclePainter.viewFor(id, _back);
    });
    widget.onMuscleTap?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final primaryColor = palette.accent;
    final secondaryColor = palette.textTertiary;
    return SectionCard(
      title: 'Muscles worked',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Front')),
                ButtonSegment<bool>(value: true, label: Text('Back')),
              ],
              selected: <bool>{_back},
              onSelectionChanged: (value) =>
                  setState(() => _back = value.single),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                border: Border.all(color: palette.border),
                borderRadius: AppRadius.rSm,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Semantics(
                  image: true,
                  label: _back
                      ? 'Back view of exercise targets'
                      : 'Front view of exercise targets',
                  child: CustomPaint(
                    size: const Size(190, 290),
                    painter: _MusclePainter(
                      back: _back,
                      selectedId: _selectedId,
                      primary: widget.primary.keys.toSet(),
                      secondary: widget.secondary.keys.toSet(),
                      primaryColor: primaryColor,
                      secondaryColor: secondaryColor,
                      figureColor: palette.surfaceHigh,
                      outlineColor: palette.borderStrong,
                      selectionColor: palette.onAccent,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _MuscleLegend(
            title: 'Primary targets',
            color: primaryColor,
            muscles: widget.primary,
            onMuscleTap: widget.onMuscleTap == null ? null : _browseMuscle,
          ),
          const SizedBox(height: AppSpacing.sm),
          _MuscleLegend(
            title: 'Secondary targets',
            color: secondaryColor,
            muscles: widget.secondary,
            onMuscleTap: widget.onMuscleTap == null ? null : _browseMuscle,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The illustration shows exercise targets.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MuscleLegend extends StatelessWidget {
  const _MuscleLegend({
    required this.title,
    required this.color,
    required this.muscles,
    this.onMuscleTap,
  });

  final String title;
  final Color color;
  final Map<String, String> muscles;
  final ValueChanged<String>? onMuscleTap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(Icons.circle, size: 12, color: color),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(title, style: context.text.titleSmall)),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (muscles.isEmpty)
            const Text('None listed')
          else if (onMuscleTap == null)
            Text(muscles.values.join(', '), style: context.text.bodyMedium)
          else
            Wrap(
              spacing: AppSpacing.xs,
              children: <Widget>[
                for (final muscle in muscles.entries)
                  ActionChip(
                    label: Text(muscle.value),
                    tooltip: 'Browse exercises for ${muscle.value}',
                    onPressed: () => onMuscleTap!(muscle.key),
                  ),
              ],
            ),
        ],
      );
}

class _MusclePainter extends CustomPainter {
  const _MusclePainter({
    required this.back,
    required this.selectedId,
    required this.primary,
    required this.secondary,
    required this.primaryColor,
    required this.secondaryColor,
    required this.figureColor,
    required this.outlineColor,
    required this.selectionColor,
  });

  final bool back;
  final String? selectedId;
  final Set<String> primary;
  final Set<String> secondary;
  final Color primaryColor;
  final Color secondaryColor;
  final Color figureColor;
  final Color outlineColor;
  final Color selectionColor;

  // Coordinates are the left side of the illustration; symmetric shapes
  // mirror around x=100. Separate front/back polygons avoid merging targets.
  static const _frontRegions = <String, List<int>>{
    'pectorals': [61, 73, 84, 66, 98, 70, 98, 96, 81, 103, 64, 98],
    'anterior_deltoids': [58, 73, 68, 71, 64, 93, 52, 106, 49, 92],
    'biceps': [53, 110, 62, 106, 58, 126, 47, 149, 40, 149, 44, 128],
    'abdominals': [88, 109, 98, 108, 98, 158, 87, 149, 84, 127],
    'obliques': [72, 123, 82, 126, 87, 151, 83, 165, 73, 155],
    'serratus_anterior': [65, 101, 82, 106, 82, 122, 71, 121],
    'hip_adductors': [87, 185, 98, 181, 94, 208, 84, 234, 83, 206],
    'quadriceps': [
      67,
      190,
      82,
      185,
      81,
      219,
      83,
      239,
      76,
      247,
      68,
      235,
      63,
      211,
    ],
    'tibialis_anterior': [76, 257, 83, 254, 84, 273, 79, 302, 74, 304, 73, 282],
  };

  static const _backRegions = <String, List<int>>{
    'trapezius': [88, 54, 98, 53, 98, 102, 90, 93, 80, 77, 69, 72],
    'mid_back': [69, 79, 80, 81, 90, 99, 92, 113, 82, 112, 70, 101],
    'spinal_erectors': [92, 102, 98, 107, 98, 159, 90, 152, 88, 130],
    'lats': [62, 99, 81, 115, 87, 117, 84, 140, 79, 155, 74, 143, 72, 124],
    'posterior_deltoids': [55, 75, 66, 72, 69, 90, 65, 101, 51, 107, 48, 93],
    'triceps': [52, 111, 61, 106, 59, 128, 46, 151, 40, 148, 44, 129],
    'glutes': [71, 160, 85, 154, 98, 161, 98, 183, 85, 190, 71, 188, 65, 178],
    'hamstrings': [
      68,
      193,
      83,
      194,
      96,
      188,
      91,
      213,
      83,
      236,
      77,
      247,
      70,
      237,
      64,
      210,
    ],
    'calves': [
      67,
      250,
      77,
      251,
      84,
      256,
      85,
      269,
      79,
      286,
      73,
      297,
      68,
      279,
      64,
      267,
    ],
  };

  static const _bothRegions = <String, List<int>>{
    'lateral_deltoids': [53, 76, 48, 86, 46, 99, 49, 107, 52, 96, 55, 85],
    'forearms': [39, 153, 46, 153, 42, 173, 34, 192, 27, 194, 30, 175],
    'hip_abductors': [
      74,
      154,
      70,
      166,
      65,
      184,
      63,
      198,
      61,
      187,
      63,
      169,
      68,
      158,
    ],
  };

  static bool startOnBack(Iterable<String> primary) =>
      primary.any(_backRegions.containsKey) &&
      !primary.any(
        (id) => _frontRegions.containsKey(id) || _bothRegions.containsKey(id),
      );

  static bool viewFor(String id, bool current) {
    if (_frontRegions.containsKey(id)) return false;
    if (_backRegions.containsKey(id)) return true;
    return current;
  }

  Path _polygon(List<int> points) {
    final path = Path()..moveTo(points[0].toDouble(), points[1].toDouble());
    for (var i = 2; i < points.length; i += 2) {
      path.lineTo(points[i].toDouble(), points[i + 1].toDouble());
    }
    return path..close();
  }

  void _drawBody(Canvas canvas, Paint fill, Paint outline) {
    final torso = Path()
      ..moveTo(88, 48)
      ..quadraticBezierTo(88, 61, 71, 65)
      ..quadraticBezierTo(49, 65, 46, 87)
      ..lineTo(43, 113)
      ..quadraticBezierTo(41, 138, 35, 151)
      ..quadraticBezierTo(29, 166, 25, 191)
      ..lineTo(18, 207)
      ..quadraticBezierTo(14, 221, 21, 223)
      ..quadraticBezierTo(26, 225, 30, 215)
      ..lineTo(35, 202)
      ..quadraticBezierTo(40, 191, 46, 173)
      ..lineTo(54, 153)
      ..lineTo(62, 123)
      ..quadraticBezierTo(77, 135, 71, 150)
      ..quadraticBezierTo(60, 167, 60, 192)
      ..quadraticBezierTo(58, 214, 66, 239)
      ..quadraticBezierTo(70, 248, 65, 259)
      ..quadraticBezierTo(60, 269, 68, 293)
      ..lineTo(72, 312)
      ..quadraticBezierTo(63, 319, 66, 324)
      ..quadraticBezierTo(75, 328, 83, 323)
      ..lineTo(85, 302)
      ..quadraticBezierTo(94, 270, 87, 251)
      ..quadraticBezierTo(94, 228, 96, 205)
      ..lineTo(100, 190);
    final body = Path.from(torso)
      ..lineTo(100, 48)
      ..close();
    const neck = Rect.fromLTRB(87, 47, 113, 82);
    const head = Rect.fromLTRB(83, 9, 117, 56);
    canvas.drawRect(neck, fill);
    canvas.drawPath(body, fill);
    canvas.drawPath(torso, outline);
    canvas.save();
    canvas.translate(200, 0);
    canvas.scale(-1, 1);
    canvas.drawPath(body, fill);
    canvas.drawPath(torso, outline);
    canvas.restore();
    canvas.drawOval(head, fill);
    canvas.drawOval(head, outline);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const figureWidth = 200.0;
    const figureHeight = 336.0;
    final scale = math.min(
      size.width / figureWidth,
      size.height / figureHeight,
    );
    canvas.save();
    canvas.translate((size.width - figureWidth * scale) / 2, 0);
    canvas.scale(scale);
    final fill = Paint()..color = figureColor;
    final outline = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeJoin = StrokeJoin.round;
    _drawBody(canvas, fill, outline);
    final regions = {...(back ? _backRegions : _frontRegions), ..._bothRegions};
    for (final region in regions.entries) {
      final path = _polygon(region.value);
      fill.color = switch (region.key) {
        final id when primary.contains(id) => primaryColor,
        final id when secondary.contains(id) => secondaryColor,
        _ => figureColor,
      };
      canvas.drawPath(path, fill);
      canvas.drawPath(path, outline);
      canvas.save();
      canvas.translate(200, 0);
      canvas.scale(-1, 1);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, outline);
      canvas.restore();
    }
    final selected = regions[selectedId];
    if (selected != null) {
      final path = _polygon(selected);
      final selection = Paint()
        ..color = selectionColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, selection);
      canvas.translate(200, 0);
      canvas.scale(-1, 1);
      canvas.drawPath(path, selection);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MusclePainter old) =>
      old.back != back ||
      old.selectedId != selectedId ||
      !setEquals(old.primary, primary) ||
      !setEquals(old.secondary, secondary) ||
      old.primaryColor != primaryColor ||
      old.secondaryColor != secondaryColor ||
      old.figureColor != figureColor ||
      old.outlineColor != outlineColor ||
      old.selectionColor != selectionColor;
}
