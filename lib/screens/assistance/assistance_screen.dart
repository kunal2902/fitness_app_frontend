import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/professionals/professionals_bloc.dart';
import '../../cards/professional_card.dart';
import '../../models/professional.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glow_background.dart';
import 'professional_detail_screen.dart';

/// Assistance tab — connect with our professionals.
class AssistanceScreen extends StatelessWidget {
  const AssistanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProfessionalsBloc>(
      create: (_) => ProfessionalsBloc()..add(const ProfessionalsRequested()),
      child: const _AssistanceView(),
    );
  }
}

class _AssistanceView extends StatelessWidget {
  const _AssistanceView();

  void _openDetail(BuildContext context, Professional professional) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfessionalDetailScreen(
          professionalId: professional.id,
          // Passed through so the header renders instantly instead of
          // flashing a spinner over data we already have.
          preview: professional,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Scaffold(
      body: GlowBackground(
        alignment: const Alignment(0, -0.95),
        child: SafeArea(
          child: BlocBuilder<ProfessionalsBloc, ProfessionalsState>(
            builder: (BuildContext context, ProfessionalsState state) {
              return RefreshIndicator(
                color: palette.accent,
                backgroundColor: palette.surfaceHigh,
                onRefresh: () async {
                  final ProfessionalsBloc bloc =
                      context.read<ProfessionalsBloc>();
                  bloc.add(const ProfessionalsRequested());
                  // firstWhere on a bloc's stream never completes if the
                  // bloc closes first — it throws StateError, or hangs the
                  // spinner forever if nothing else emits. Leaving the tab
                  // mid-refresh does exactly that, so fall back to the last
                  // known state instead of letting it escape.
                  await bloc.stream
                      .firstWhere((ProfessionalsState s) => !s.isLoading)
                      .catchError((Object _) => bloc.state)
                      .timeout(
                        const Duration(seconds: 20),
                        onTimeout: () => bloc.state,
                      );
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: <Widget>[
                    Text(
                      'CONNECT WITH OUR',
                      style: context.text.labelSmall
                          ?.copyWith(color: palette.accent),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text('Professionals', style: context.text.displaySmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Message a coach, or start a voice or video call when '
                      'they are online.',
                      style: context.text.bodyMedium
                          ?.copyWith(color: palette.textSecondary),
                    ),

                    const SizedBox(height: AppSpacing.md),
                    const _ConnectionBanner(),
                    const SizedBox(height: AppSpacing.md),

                    if (state.isLoading && state.professionals.isEmpty)
                      const _LoadingList()
                    else if (state.errorMessage != null &&
                        state.professionals.isEmpty)
                      _ErrorState(message: state.errorMessage!)
                    else if (state.isEmpty)
                      const _EmptyState()
                    else
                      ...state.professionals.map(
                        (Professional p) => ProfessionalCard(
                          professional: p,
                          onTap: () => _openDetail(context, p),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Warns when the realtime connection is down, because that is exactly
/// when messages appear to send but calls cannot start.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SocketStatus>(
      stream: SocketService.instance.statusStream,
      initialData: SocketService.instance.status,
      builder: (BuildContext context, AsyncSnapshot<SocketStatus> snapshot) {
        final SocketStatus status = snapshot.data ?? SocketStatus.disconnected;
        if (status == SocketStatus.connected) return const SizedBox.shrink();

        final AppPalette palette = context.palette;
        final bool isConnecting = status == SocketStatus.connecting;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: AppRadius.rSm,
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                height: 16,
                width: 16,
                child: isConnecting
                    ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.warning),
                      )
                    : const Icon(
                        Icons.cloud_off_rounded,
                        size: 16,
                        color: AppColors.warning,
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isConnecting
                      ? 'Connecting to live chat…'
                      : 'Offline — messages will send when you reconnect, and '
                          'calls are unavailable.',
                  style: context.text.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      children: List<Widget>.generate(
        2,
        (int i) => Container(
          height: 190,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppRadius.rLg,
            border: Border.all(color: palette.border),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.support_agent_rounded,
            size: 48,
            color: palette.textTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('No coaches yet', style: context.text.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Run the seed script on the backend to add the team.',
            textAlign: TextAlign.center,
            style:
                context.text.bodySmall?.copyWith(color: palette.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: AppColors.danger,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style:
                context.text.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: () => context
                .read<ProfessionalsBloc>()
                .add(const ProfessionalsRequested()),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
