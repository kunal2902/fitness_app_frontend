import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Stand-in for a tab that has not been built yet.
///
/// Deliberately just the page name — these four screens are placeholders
/// for phase 2, and dressing them up with fake content would make it
/// harder to tell what is real and what is not.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Text(title, style: context.text.displaySmall),
        ),
      ),
    );
  }
}
