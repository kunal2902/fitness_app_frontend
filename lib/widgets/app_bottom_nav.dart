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

/// The shared tab bar. A short marker and filled icon identify the active tab.
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
    final double labelExtra = (MediaQuery.textScalerOf(context).scale(11) - 11)
        .clamp(0.0, 16.0)
        .toDouble();

    return Material(
      color: palette.bg,
      shape: Border(top: BorderSide(color: palette.border)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height + labelExtra,
          child: Row(
            children: List<Widget>.generate(destinations.length, (int i) {
              final NavDestination item = destinations[i];
              final bool isActive = i == currentIndex;

              return Expanded(
                child: Semantics(
                  button: true,
                  selected: isActive,
                  label: item.label,
                  child: InkWell(
                    onTap: () {
                      if (isActive) return;
                      HapticFeedback.selectionClick();
                      onSelected(i);
                    },
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          AnimatedContainer(
                            duration: AppDuration.fast,
                            curve: Curves.easeOut,
                            width: isActive ? 14 : 0,
                            height: 2,
                            decoration: BoxDecoration(
                              color: palette.accent,
                              borderRadius: AppRadius.rPill,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Icon(
                            isActive ? item.activeIcon : item.icon,
                            size: AppSize.iconMd,
                            color: isActive
                                ? palette.accent
                                : palette.textSecondary,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          AnimatedDefaultTextStyle(
                            duration: AppDuration.fast,
                            style: context.text.labelSmall!.copyWith(
                              letterSpacing: 0.1,
                              color: isActive
                                  ? palette.accent
                                  : palette.textSecondary,
                              fontWeight:
                                  isActive ? FontWeight.w800 : FontWeight.w500,
                            ),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
