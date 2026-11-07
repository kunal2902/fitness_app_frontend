import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/api_exception.dart';
import '../../models/health_models.dart';
import '../../store/app_store.dart';
import '../../services/health_background_scheduler.dart';
import '../../services/health_sync_repository.dart';

class HealthSyncState extends Equatable {
  const HealthSyncState({
    this.availability = HealthProviderAvailability.checking,
    this.access = HealthAccessStatus.unknown,
    this.busy = false,
    this.result,
    this.bmi,
    this.error,
    this.notice,
    this.revision = 0,
  });

  final HealthProviderAvailability availability;
  final HealthAccessStatus access;
  final bool busy;
  final HealthSyncResult? result;
  final double? bmi;
  final String? error;
  final String? notice;
  final int revision;

  HealthSyncState copyWith({
    HealthProviderAvailability? availability,
    HealthAccessStatus? access,
    bool? busy,
    HealthSyncResult? result,
    bool clearResult = false,
    double? bmi,
    String? error,
    String? notice,
    bool clearFeedback = false,
    int? revision,
  }) {
    return HealthSyncState(
      availability: availability ?? this.availability,
      access: access ?? this.access,
      busy: busy ?? this.busy,
      result: clearResult ? null : (result ?? this.result),
      bmi: bmi ?? this.bmi,
      error: clearFeedback ? null : (error ?? this.error),
      notice: clearFeedback ? null : (notice ?? this.notice),
      revision: revision ?? this.revision,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        availability,
        access,
        busy,
        result,
        bmi,
        error,
        notice,
        revision,
      ];
}

class HealthSyncCubit extends Cubit<HealthSyncState> {
  HealthSyncCubit({
    HealthSyncRepository? repository,
    HealthSyncScheduler? scheduler,
    AppStore? appStore,
  })  : _repository = repository ?? DeviceHealthSyncRepository(),
        _scheduler = scheduler ?? HealthBackgroundScheduler.instance,
        _appStore = appStore ?? AppStore.instance,
        super(const HealthSyncState());

  final HealthSyncRepository _repository;
  final HealthSyncScheduler _scheduler;
  final AppStore _appStore;

  double? get _profileBmi {
    final profile = _appStore.user?.fitnessProfile ?? _appStore.onboardingDraft;
    return calculateProfileBmi(
      heightCm: profile.heightCm,
      weightKg: profile.weightKg,
    );
  }

  Future<void> initialize() async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, bmi: _profileBmi, clearFeedback: true));
    try {
      final HealthProviderAvailability provider =
          await _repository.availability();
      if (provider != HealthProviderAvailability.available) {
        emit(
          state.copyWith(
            availability: provider,
            access: HealthAccessStatus.unknown,
            busy: false,
          ),
        );
        return;
      }
      final HealthAccessStatus access = await _repository.accessStatus();
      final HealthSyncResult? cached = await _repository.cachedResult();
      emit(
        state.copyWith(
          availability: provider,
          access: access,
          result: cached,
          busy: false,
        ),
      );
      if (access == HealthAccessStatus.authorized) {
        await refresh();
      }
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> connect() async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearFeedback: true));
    try {
      final bool granted = await _repository.requestAccess();
      if (!granted) {
        emit(
          state.copyWith(
            access: HealthAccessStatus.denied,
            busy: false,
            notice: 'Health access was not granted. You can try again anytime.',
            revision: state.revision + 1,
          ),
        );
        return;
      }
      final HealthSyncResult synced =
          await _repository.synchronize(forceFull: true);
      final _ScheduledHealthResult scheduled = await _applySchedule(synced);
      emit(
        state.copyWith(
          access: HealthAccessStatus.authorized,
          busy: false,
          result: scheduled.result,
          notice: scheduled.warning ?? 'Health data connected and synced.',
          revision: state.revision + 1,
        ),
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> installProvider() async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearFeedback: true));
    try {
      await _repository.installProvider();
      emit(
        state.copyWith(
          busy: false,
          notice:
              'Finish installing Health Connect, then return to Fitness App.',
          revision: state.revision + 1,
        ),
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> openSettings() async {
    try {
      await _repository.openSettings();
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> refresh() async {
    if (state.busy || state.access != HealthAccessStatus.authorized) return;
    emit(state.copyWith(busy: true, clearFeedback: true));
    try {
      final HealthSyncResult synced = await _repository.synchronize();
      final _ScheduledHealthResult scheduled = await _applySchedule(synced);
      emit(
        state.copyWith(
          busy: false,
          result: scheduled.result,
          notice: scheduled.warning,
          revision:
              scheduled.warning == null ? state.revision : state.revision + 1,
        ),
      );
    } catch (error) {
      if (error is ApiException && error.code == 'HEALTH_PERMISSION_REMOVED') {
        emit(
          state.copyWith(
            access: HealthAccessStatus.denied,
            busy: false,
            error: error.message,
            revision: state.revision + 1,
          ),
        );
      } else {
        _fail(error);
      }
    }
  }

  Future<_ScheduledHealthResult> _applySchedule(
    HealthSyncResult result,
  ) async {
    try {
      if (result.backgroundEnabled) {
        await _scheduler.enable();
      } else {
        await _scheduler.disable();
      }
      return _ScheduledHealthResult(result: result);
    } catch (_) {
      return _ScheduledHealthResult(
        result: HealthSyncResult(
          today: result.today,
          checkedAt: result.checkedAt,
          uploadedDays: result.uploadedDays,
          backgroundEnabled: false,
        ),
        warning:
            'Health data synced. Background scheduling is unavailable, so sync while the app is open.',
      );
    }
  }

  void _fail(Object error) {
    final String message = error is ApiException
        ? error.message
        : 'Health data could not be synced. Please try again.';
    emit(
      state.copyWith(
        availability: state.availability == HealthProviderAvailability.checking
            ? HealthProviderAvailability.unsupported
            : state.availability,
        busy: false,
        error: message,
        revision: state.revision + 1,
      ),
    );
  }
}

class _ScheduledHealthResult {
  const _ScheduledHealthResult({required this.result, this.warning});

  final HealthSyncResult result;
  final String? warning;
}
