import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import '../assistance/assistance_screen.dart';
import '../home/home_screen.dart';
import '../nutrition/nutrition_screen.dart';
import '../profile/profile_screen.dart';
import '../tracking/tracking_screen.dart';

/// The signed-in shell: five tabs behind one persistent bottom bar.
///
/// Uses [IndexedStack] rather than swapping the body, so each tab keeps its
/// scroll position, its BLoC state and its in-flight requests when you move
/// away and come back. The cost is that all five build once up front —
/// cheap here, since four of them are a single Text.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({this.initialIndex = 0, super.key});

  final int initialIndex;

  /// Index of the profile tab, for deep links and post-signup routing.
  static const int profileTabIndex = 4;

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late int _index =
      widget.initialIndex.clamp(0, _destinations.length - 1).toInt();

  static const List<NavDestination> _destinations = <NavDestination>[
    NavDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    NavDestination(
      label: 'Tracking',
      icon: Icons.show_chart_outlined,
      activeIcon: Icons.show_chart_rounded,
    ),
    NavDestination(
      label: 'Nutrition',
      icon: Icons.restaurant_outlined,
      activeIcon: Icons.restaurant_rounded,
    ),
    NavDestination(
      label: 'Assistance',
      icon: Icons.support_agent_outlined,
      activeIcon: Icons.support_agent_rounded,
    ),
    NavDestination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  static const List<Widget> _tabs = <Widget>[
    HomeScreen(),
    TrackingScreen(),
    NutritionScreen(),
    AssistanceScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Android back on any tab other than Home returns to Home rather than
      // dropping the user out of the app.
      canPop: _index == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        setState(() => _index = 0);
      },
      child: Scaffold(
        backgroundColor: context.palette.bg,
        body: IndexedStack(index: _index, children: _tabs),
        bottomNavigationBar: AppBottomNav(
          destinations: _destinations,
          currentIndex: _index,
          onSelected: (int i) => setState(() => _index = i),
        ),
      ),
    );
  }
}
