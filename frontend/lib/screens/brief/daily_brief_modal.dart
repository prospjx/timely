import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/providers/brief_provider.dart';
import 'package:kairos/services/audio_service.dart';
import 'package:kairos/services/haptic_service.dart';
import 'package:kairos/widgets/assistant_bubble.dart';
import 'package:kairos/widgets/zen_card.dart';

class DailyBriefModal extends ConsumerStatefulWidget {
  const DailyBriefModal({super.key});

  @override
  ConsumerState<DailyBriefModal> createState() => _DailyBriefModalState();
}

class _DailyBriefModalState extends ConsumerState<DailyBriefModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final briefState = ref.watch(briefControllerProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: briefState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(_friendlyBriefError(error))),
          data: (brief) {
            if (brief == null) {
              return Center(
                child: Text(
                  'No brief available right now.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.timelyColors.onSurfaceMuted,
                  ),
                ),
              );
            }

            return FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Brief • ${DateFormat.yMMMd().format(DateTime.now())}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AssistantBubble(message: brief.text),
                  const SizedBox(height: AppSpacing.lg - 4),
                  if (brief.audioUrl != null)
                    ZenCard(
                      tint: context.timelyColors.surfaceElevated,
                      child: _AudioControls(url: brief.audioUrl!),
                    ),
                  if (brief.audioUrl == null)
                    ZenCard(
                      tint: context.timelyColors.surfaceElevated,
                      child: _LocalTtsControls(text: brief.text),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _friendlyBriefError(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 500) {
        return 'Brief is temporarily unavailable. Please try again in a few seconds.';
      }
      if (code == 409) {
        return 'Could not generate the brief due to a schedule conflict. Please try again.';
      }
      if (code == 404) {
        return 'Brief service route was not found. Confirm backend is running on port 8000.';
      }
      if (code == null) {
        return 'Cannot reach the backend. Start the API and ensure emulator can access 10.0.2.2:8000.';
      }
    }
    return 'Failed to load brief. Please try again.';
  }
}

class _LocalTtsControls extends ConsumerStatefulWidget {
  const _LocalTtsControls({required this.text});

  final String text;

  @override
  ConsumerState<_LocalTtsControls> createState() => _LocalTtsControlsState();
}

class _LocalTtsControlsState extends ConsumerState<_LocalTtsControls> {
  bool _speaking = false;

  @override
  Widget build(BuildContext context) {
    final audioService = ref.read(audioServiceProvider);
    final timely = context.timelyColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Live audio unavailable. Using device voice.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: timely.onSurfaceMuted),
        ),
        const SizedBox(height: AppSpacing.sm + 4),
        FilledButton.icon(
          onPressed: () async {
            if (_speaking) {
              await audioService.stopSpeaking();
              if (mounted) {
                setState(() => _speaking = false);
              }
              return;
            }

            await HapticService.lightImpact();
            await audioService.speakBriefText(widget.text);
            if (mounted) {
              setState(() => _speaking = true);
            }
          },
          icon: Icon(_speaking ? Icons.stop : Icons.record_voice_over),
          label: Text(_speaking ? 'Stop Voice Brief' : 'Play Voice Brief'),
        ),
      ],
    );
  }
}

class _AudioControls extends ConsumerWidget {
  const _AudioControls({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioService = ref.watch(audioServiceProvider);

    return Column(
      children: [
        StreamBuilder<Duration?>(
          stream: audioService.durationStream,
          builder: (context, durationSnapshot) {
            final total = durationSnapshot.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: audioService.positionStream,
              builder: (context, positionSnapshot) {
                final position = positionSnapshot.data ?? Duration.zero;
                final maxMs = total.inMilliseconds <= 0 ? 1 : total.inMilliseconds;
                final value = position.inMilliseconds.clamp(0, maxMs);

                return Column(
                  children: [
                    LinearProgressIndicator(
                      value: value / maxMs,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(position)),
                        Text(_fmt(total)),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm + 4),
        StreamBuilder<PlayerState>(
          stream: audioService.playerStateStream,
          builder: (context, snapshot) {
            final isPlaying = audioService.isPlaying;
            return FilledButton.icon(
              onPressed: () async {
                if (isPlaying) {
                  await audioService.pause();
                } else {
                  await HapticService.lightImpact();
                  await audioService.playBrief(url);
                }
              },
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(isPlaying ? 'Pause Brief' : 'Play Brief'),
            );
          },
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
