import 'dart:math' as math;

import 'package:fitness_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final double first = a.computeLuminance();
  final double second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

bool _isNeutral(Color color) => color.r == color.g && color.g == color.b;

void main() {
  for (final ThemeData theme in <ThemeData>[AppTheme.dark, AppTheme.light]) {
    final AppPalette palette = theme.extension<AppPalette>()!;
    final String mode = theme.brightness.name;

    test('$mode surfaces and actions are monochrome with readable contrast',
        () {
      for (final Color color in <Color>[
        palette.bg,
        palette.surface,
        palette.surfaceAlt,
        palette.surfaceHigh,
        palette.textPrimary,
        palette.accent,
        palette.onAccent,
        theme.colorScheme.secondary,
      ]) {
        expect(_isNeutral(color), isTrue, reason: '$color is a chrome color');
      }

      final ButtonStyle action = theme.filledButtonTheme.style!;
      final Color fill = action.backgroundColor!.resolve({})!;
      final Color label = action.foregroundColor!.resolve({})!;
      expect(_contrast(fill, label), greaterThanOrEqualTo(7));
      expect(
        _contrast(palette.textSecondary, palette.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.textTertiary, palette.surfaceAlt),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.borderStrong, palette.surfaceAlt),
        greaterThanOrEqualTo(3),
      );
    });

    testWidgets('$mode dialog and sheet use the shared surface style',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: <Widget>[
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          const AlertDialog(title: Text('Test dialog')),
                    ),
                    child: const Text('Open dialog'),
                  ),
                  TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => const SizedBox(
                        height: 120,
                        child: Text('Test sheet'),
                      ),
                    ),
                    child: const Text('Open sheet'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      final Finder dialogMaterial = find.descendant(
        of: find.byType(Dialog),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material &&
              widget.color == theme.dialogTheme.backgroundColor,
        ),
      );
      expect(dialogMaterial, findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      final Finder sheetMaterial = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material &&
              widget.color == theme.bottomSheetTheme.modalBackgroundColor,
        ),
      );
      expect(sheetMaterial, findsOneWidget);
    });
  }
}
