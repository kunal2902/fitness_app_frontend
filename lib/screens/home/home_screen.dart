import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../routes/app_routes.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// Training discovery entry point in the signed-in tab shell.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const Map<String, String> _muscleGroups = {
    'chest': 'Chest',
    'back': 'Back',
    'shoulders': 'Shoulders',
    'arms': 'Arms',
    'core': 'Core',
    'hips': 'Hips',
    'thighs': 'Thighs',
    'lower_legs': 'Lower legs',
  };

  @override
  Widget build(BuildContext context) {
    final String? firstName = context.select<AppStore, String?>(
      (AppStore store) => store.user?.firstName,
    );
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              Text(
                firstName == null || firstName.isEmpty
                    ? 'Home'
                    : 'Hi, $firstName',
                style: context.text.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Find an exercise for your next session.',
                style: context.text.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                gradient: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Icon(
                      Icons.fitness_center_rounded,
                      size: 32,
                      color: context.palette.accent,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Exercise library',
                      style: context.text.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Search movements, see which muscles they target, and learn the setup.',
                      style: context.text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context)
                          .pushNamed(AppRoutes.exerciseLibrary),
                      icon: const Icon(Icons.search),
                      label: const Text('Find exercises'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Browse by muscle', style: context.text.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                children: <Widget>[
                  for (final MapEntry<String, String> group
                      in _muscleGroups.entries)
                    ActionChip(
                      label: Text(group.value),
                      onPressed: () => Navigator.of(context).pushNamed(
                        AppRoutes.exerciseLibrary,
                        arguments: ExerciseLibraryArguments(
                          initialMuscleGroup: group.key,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Equipment',
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Column(
                  children: <Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.tune_rounded),
                      title: const Text('My equipment'),
                      subtitle:
                          const Text('Manage the equipment you have access to'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context)
                          .pushNamed(AppRoutes.trainingEquipment),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.filter_alt_outlined),
                      title: const Text('Train with my equipment'),
                      subtitle:
                          const Text('Find exercises you can do with your kit'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pushNamed(
                        AppRoutes.exerciseLibrary,
                        arguments: const ExerciseLibraryArguments(
                          initialAvailableEquipment: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
