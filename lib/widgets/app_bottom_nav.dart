import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// One destination in the bottom bar.
class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// The app's five-tab bottom bar.
///
/// Hand-built rather than Material's [NavigationBar] so the active pill,
/// the volt accent and the near-black surface match the rest of the design
/// system exactly, and so the height stays predictable across platforms.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: List<Widget>.generate(destinations.length, (int i) {
              final NavDestination item = destinations[i];
              final bool isActive = i == currentIndex;

              return Expanded(
                child: Semantics(
                  button: true,
                  selected: isActive,
                  label: item.label,
                  child: InkResponse(
                    onTap: () {
                      if (isActive) return;
                      HapticFeedback.selectionClick();
                      onSelected(i);
                    },
                    radius: 42,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        AnimatedContainer(
                          duration: AppDuration.fast,
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xxs + 2,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? palette.accent.withValues(alpha: 0.14)
                                : Colors.transparent,
                            borderRadius: AppRadius.rPill,
                          ),
                          child: Icon(
                            isActive ? item.activeIcon : item.icon,
                            size: AppSize.iconMd,
                            color: isActive
                                ? palette.accent
                                : palette.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: AppDuration.fast,
                          style: context.text.labelSmall!.copyWith(
                            fontSize: 10,
                            letterSpacing: 0.2,
                            color:
                                isActive ? palette.accent : palette.textTertiary,
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w600,
                          ),
                          child: Text(item.label),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
