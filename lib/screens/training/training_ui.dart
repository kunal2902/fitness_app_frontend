import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/training_models.dart';
import '../../theme/app_theme.dart';

String trainingLabel(String id) {
  if (id == 'newbie') return 'New to training';
  return id.split('_').where((word) => word.isNotEmpty).map((word) {
    return '${word[0].toUpperCase()}${word.substring(1)}';
  }).join(' ');
}

String trainingErrorText(Object error) {
  if (error is ApiException) {
    if (error.code == 'TRAINING_CATALOGUE_UNAVAILABLE') {
      return 'The exercise library is awaiting a reviewed catalogue. Check back after it is published.';
    }
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}

List<String> requiredEquipmentLabels(
  TrainingExercise exercise,
  Map<String, String> equipment,
) =>
    exercise.equipmentRequirementGroups.map((requirement) {
      return requirement.anyOf
          .map((id) => equipment[id] ?? trainingLabel(id))
          .join(' or ');
    }).toList();

class TrainingNotice extends StatelessWidget {
  const TrainingNotice({
    required this.message,
    this.action,
    this.label = 'Retry',
    super.key,
  });

  final String message;
  final VoidCallback? action;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              style: context.text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              TextButton(onPressed: action, child: Text(label)),
            ],
          ],
        ),
      );
}
