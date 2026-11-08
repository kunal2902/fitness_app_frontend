import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/training_models.dart';
import '../../services/training_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'training_ui.dart';

class TrainingEquipmentScreen extends StatefulWidget {
  const TrainingEquipmentScreen({required this.repository, super.key});

  final TrainingRepository repository;

  @override
  State<TrainingEquipmentScreen> createState() =>
      _TrainingEquipmentScreenState();
}

class _TrainingEquipmentScreenState extends State<TrainingEquipmentScreen> {
  TrainingPreferences? _preferences;
  TrainingTaxonomy? _taxonomy;
  List<TrainingEquipmentProfile> _profiles = <TrainingEquipmentProfile>[];
  String? _activeId;
  Object? _error;
  Object? _taxonomyError;
  CancelToken? _preferencesRequest;
  CancelToken? _taxonomyRequest;
  bool _loadingPreferences = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
    unawaited(_loadTaxonomy());
  }

  @override
  void dispose() {
    _preferencesRequest?.cancel();
    _taxonomyRequest?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    _preferencesRequest?.cancel();
    final token = CancelToken();
    _preferencesRequest = token;
    setState(() => _loadingPreferences = true);
    try {
      final preferences = await widget.repository.loadPreferences(
        cancelToken: token,
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _preferences = preferences;
        _profiles = <TrainingEquipmentProfile>[
          ...preferences.equipmentProfiles,
        ];
        _activeId = preferences.activeEquipmentProfileId;
        _dirty = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || token.isCancelled) return;
      setState(() => _error = error);
    } finally {
      if (mounted && !token.isCancelled) {
        setState(() => _loadingPreferences = false);
      }
    }
  }

  Future<void> _loadTaxonomy() async {
    _taxonomyRequest?.cancel();
    final token = CancelToken();
    _taxonomyRequest = token;
    setState(() => _taxonomyError = null);
    try {
      final taxonomy = await widget.repository.loadTaxonomy(cancelToken: token);
      if (!mounted || token.isCancelled) return;
      setState(() => _taxonomy = taxonomy);
    } on Object catch (error) {
      if (!mounted || token.isCancelled) return;
      setState(() => _taxonomyError = error);
    }
  }

  Future<void> _save() async {
    final preferences = _preferences;
    if (preferences == null || !_dirty || _saving || _loadingPreferences) {
      return;
    }
    final token = CancelToken();
    _preferencesRequest = token;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveEquipmentPreferences(
        revision: preferences.revision,
        equipmentProfiles: _profiles,
        activeEquipmentProfileId: _activeId,
        cancelToken: token,
      );
      if (!mounted || token.isCancelled) return;
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted || token.isCancelled) return;
      setState(() => _error = error);
    } finally {
      if (mounted && !token.isCancelled) setState(() => _saving = false);
    }
  }

  Future<void> _edit(TrainingEquipmentProfile? profile) async {
    final result = await showDialog<TrainingEquipmentProfile>(
      context: context,
      builder: (context) => _EquipmentProfileDialog(
        profile: profile,
        choices: _taxonomy?.equipment ?? const <TrainingEquipment>[],
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (profile == null) {
        _profiles.add(result);
        if (_profiles.length == 1) _activeId = result.id;
      } else {
        final index = _profiles.indexWhere((entry) => entry.id == result.id);
        _profiles[index] = result;
      }
      _dirty = true;
    });
  }

  void _delete(TrainingEquipmentProfile profile) => setState(() {
        _profiles.removeWhere((entry) => entry.id == profile.id);
        if (_activeId == profile.id) _activeId = null;
        _dirty = true;
      });

  void _setActive(String? id) => setState(() {
        _activeId = id;
        _dirty = true;
      });

  Future<void> _reloadAfterConflict() async {
    final reload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reload equipment profiles?'),
        content: const Text(
          'Reloading replaces your unsaved edits with the latest profiles.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reload'),
          ),
        ],
      ),
    );
    if (mounted && reload == true) await _loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final busy = _saving || _loadingPreferences;
    final conflict = error is ApiException &&
        (error.code == 'TRAINING_PREFERENCES_CONFLICT' || error.isConflict);
    final labels = <String, String>{
      for (final item in _taxonomy?.equipment ?? const <TrainingEquipment>[])
        item.id: item.name,
    };
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('My equipment')),
        body: SafeArea(
          top: false,
          child: _preferences == null
              ? Center(
                  child: _loadingPreferences
                      ? const CircularProgressIndicator(
                          semanticsLabel: 'Loading equipment profiles',
                        )
                      : Padding(
                          padding: AppSpacing.page,
                          child: TrainingNotice(
                            message: trainingErrorText(
                              error ?? const ApiException.unknown(),
                            ),
                            action: _loadPreferences,
                          ),
                        ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: <Widget>[
                    Text(
                      'Equipment profiles',
                      style: context.text.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Save the equipment you have at places like home or the gym. The exercise library uses your active profile to find a match.',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_taxonomyError != null)
                      TrainingNotice(
                        message:
                            'Equipment choices could not load. You can still manage profile names and your active profile.',
                        action: _loadTaxonomy,
                        label: 'Reload choices',
                      ),
                    if (_profiles.isEmpty)
                      const Text(
                        'You have no equipment profiles. Add a profile with an empty equipment list if you train without equipment.',
                      ),
                    for (final profile in _profiles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _EquipmentProfileCard(
                          profile: profile,
                          labels: labels,
                          active: _activeId == profile.id,
                          onEdit: busy ? null : () => _edit(profile),
                          onDelete: busy ? null : () => _delete(profile),
                          onActivate: busy
                              ? null
                              : () => _setActive(
                                    _activeId == profile.id ? null : profile.id,
                                  ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: busy || _profiles.length >= 10
                          ? null
                          : () => _edit(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add equipment profile'),
                    ),
                    if (_profiles.length >= 10)
                      const Text('You can save up to 10 equipment profiles.'),
                    if (error != null)
                      TrainingNotice(
                        message: conflict
                            ? 'Your profiles changed elsewhere. Reload the latest profiles before saving.'
                            : trainingErrorText(error),
                        action: conflict && !busy ? _reloadAfterConflict : null,
                        label: 'Reload profiles',
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton(
                      onPressed: busy || !_dirty || conflict ? null : _save,
                      child:
                          Text(_saving ? 'Saving profiles…' : 'Save profiles'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _EquipmentProfileCard extends StatelessWidget {
  const _EquipmentProfileCard({
    required this.profile,
    required this.labels,
    required this.active,
    this.onEdit,
    this.onDelete,
    this.onActivate,
  });

  final TrainingEquipmentProfile profile;
  final Map<String, String> labels;
  final bool active;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) => SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(profile.name, style: context.text.titleMedium),
                ),
                if (active)
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: context.palette.textPrimary,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              profile.equipmentIds.isEmpty
                  ? 'No equipment'
                  : profile.equipmentIds
                      .map((id) => labels[id] ?? trainingLabel(id))
                      .join(', '),
            ),
            if (active) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Active profile',
                style: context.text.labelMedium?.copyWith(
                  color: context.palette.accent,
                ),
              ),
            ],
            Wrap(
              spacing: AppSpacing.xs,
              children: <Widget>[
                TextButton(
                  onPressed: onActivate,
                  child: Text(active ? 'Clear active' : 'Use profile'),
                ),
                TextButton(onPressed: onEdit, child: const Text('Edit')),
                TextButton(onPressed: onDelete, child: const Text('Remove')),
              ],
            ),
          ],
        ),
      );
}

class _EquipmentProfileDialog extends StatefulWidget {
  const _EquipmentProfileDialog({required this.profile, required this.choices});

  final TrainingEquipmentProfile? profile;
  final List<TrainingEquipment> choices;

  @override
  State<_EquipmentProfileDialog> createState() =>
      _EquipmentProfileDialogState();
}

class _EquipmentProfileDialogState extends State<_EquipmentProfileDialog> {
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  late final _selected = <String>{...?widget.profile?.equipmentIds};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final id =
        widget.profile?.id ?? 'kit_${DateTime.now().microsecondsSinceEpoch}';
    Navigator.of(context).pop(
      TrainingEquipmentProfile(
        id: id,
        name: name,
        equipmentIds: _selected.toList()..sort(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final choices = <String, String>{
      for (final item in widget.choices) item.id: item.name,
    };
    final unlisted = (widget.profile?.equipmentIds ?? const <String>[]).where(
      (id) => !choices.containsKey(id),
    );
    return AlertDialog(
      title: Text(
        widget.profile == null
            ? 'Add equipment profile'
            : 'Edit equipment profile',
      ),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _name,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Profile name',
                hintText: 'Home, Park or Gym',
              ),
              onChanged: (_) => setState(() {}),
            ),
            Text('Equipment you have', style: context.text.titleSmall),
            const SizedBox(height: AppSpacing.xxs),
            const Text(
              'Leave all options unchecked for a no-equipment profile.',
            ),
            for (final item in choices.entries) _check(item.key, item.value),
            for (final id in unlisted) _check(id, trainingLabel(id)),
            if (_selected.length >= 100)
              const Text('You can select up to 100 equipment items.'),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _done,
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _check(String id, String label) => CheckboxListTile(
        value: _selected.contains(id),
        title: Text(label),
        contentPadding: EdgeInsets.zero,
        onChanged: !_selected.contains(id) && _selected.length >= 100
            ? null
            : (checked) => setState(() {
                  if (checked == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                }),
      );
}
