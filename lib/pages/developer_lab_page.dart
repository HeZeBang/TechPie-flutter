import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ecard_bind_hijack.dart';
import '../services/ecard_bind_service.dart';
import '../services/service_provider.dart';
import '../utils/haptics.dart';
import '../utils/platform.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

/// A place to exercise the device APIs the app depends on, reached from the
/// developer section of the settings page: every waveform the app can play, every
/// sound it ships, and — as more of them arrive — whatever else is worth judging
/// on a real device rather than at a desk.
///
/// The lists are built from [AppHaptics.all], so a waveform added to the
/// dictionary appears here without touching this file. A new kind of probe
/// belongs in its own section at the end.
final class DeveloperLabPage extends StatelessWidget {
  const DeveloperLabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topPad = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;
    final waveforms = AppHaptics.all.values.toList(growable: false);
    final sounds = <String, AppHapticWaveform>{};
    for (final waveform in waveforms) {
      final asset = waveform.soundAsset;
      if (asset != null) sounds.putIfAbsent(asset, () => waveform);
    }
    final designed = waveforms
        .where((waveform) => waveform.soundAsset != null)
        .toList(growable: false);

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: 'Developer Lab',
              trailingItems: const [],
              onItemPressed: (_) {},
            )
          : const BlurredAppBar(title: Text('Developer Lab')),
      body: ListView(
        padding: EdgeInsets.only(top: topPad, bottom: 32),
        children: [
          if (!AppHaptics.hasPlayer) const _NoPlayerNotice(),
          _Section(
            key: const Key('lab-haptics'),
            header: 'Haptics',
            footer: 'Vibration only — the waveform the app plays for this id.',
            children: [
              for (final waveform in waveforms)
                _LabTile(
                  title: waveform.id,
                  subtitle: _summary(waveform),
                  icon: Icons.vibration,
                  onTap: () => unawaited(AppHaptics.play(waveform)),
                ),
            ],
          ),
          _Section(
            key: const Key('lab-sounds'),
            header: 'Sounds',
            footer: 'Sound only — the assets the app ships.',
            children: [
              for (final entry in sounds.entries)
                _LabTile(
                  title: _fileName(entry.key),
                  subtitle: '${entry.value.soundDurationMs ?? entry.value.durationMs} ms'
                      ' · ${entry.value.id}',
                  icon: Icons.volume_up_outlined,
                  onTap: () => unawaited(
                      AppHaptics.play(entry.value, sound: true, vibration: false),
                    ),
                ),
            ],
          ),
          _Section(
            key: const Key('lab-together'),
            header: 'Together',
            footer: 'What the app plays for these two moments: waveform and sound.',
            children: [
              for (final waveform in designed)
                _LabTile(
                  title: waveform.id,
                  subtitle: _summary(waveform),
                  icon: Icons.play_circle_outline,
                  onTap: () => unawaited(AppHaptics.play(waveform, sound: true)),
                ),
            ],
          ),
          const _EcardBindProbe(),
        ],
      ),
    );
  }

  /// What the row says about a waveform: how many pulses, how long, and whether
  /// it also carries a sound.
  static String _summary(AppHapticWaveform waveform) {
    final pulses = waveform.pulses.length == 1 ? '1 pulse' : '${waveform.pulses.length} pulses';
    final sound = waveform.soundAsset == null ? '' : ' · sound';
    return '$pulses · ${waveform.durationMs} ms$sound';
  }

  static String _fileName(String asset) => asset.split('/').last;
}

final class _NoPlayerNotice extends StatelessWidget {
  const _NoPlayerNotice();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'This platform has no player, so nothing here will play. '
            'The developer lab is meant for a phone.',
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
        ),
      );
}

final class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.header,
    required this.footer,
    required this.children,
  });

  final String header;
  final String footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              header,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...children,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              footer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
}

final class _LabTile extends StatelessWidget {
  const _LabTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.play_arrow),
        onTap: onTap,
      );
}

/// The eCard bind-code tunnel's diagnosis, moved here from the user-facing
/// account page: the technical readout belongs in a lab, not in front of a user
/// who only needs to agree to the VPN prompt.
final class _EcardBindProbe extends StatefulWidget {
  const _EcardBindProbe();

  @override
  State<_EcardBindProbe> createState() => _EcardBindProbeState();
}

final class _EcardBindProbeState extends State<_EcardBindProbe> {
  bool _busy = false;
  EcardBindDiagnosis? _diagnosis;

  Future<void> _check() async {
    final bind = ServiceProvider.of(context).ecardBindService;
    setState(() => _busy = true);
    final diagnosis = await bind.diagnose();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _diagnosis = diagnosis;
    });
  }

  static String _lines(EcardBindDiagnosis diagnosis) {
    final addresses = diagnosis.lookupError != null
        ? '解析失败（${diagnosis.lookupError}）'
        : '${diagnosis.addresses.join(', ')}'
            '${diagnosis.routesToBindService ? '（已指向绑定服务）' : '（未劫持）'}';
    return '状态：${diagnosis.status.name}\n'
        '解析 ${EcardBindHijackService.host}：$addresses\n'
        '健康检查：${diagnosis.healthLine}';
  }

  @override
  Widget build(BuildContext context) {
    final diagnosis = _diagnosis;
    return _Section(
      key: const Key('lab-ecard-bind'),
      header: 'eCard bind',
      footer: 'The bind-code tunnel: its status, what the host resolves to, and '
          'whether the bind service answers.',
      children: [
        ListTile(
          leading: const Icon(Icons.travel_explore_outlined),
          title: Text(_busy ? '正在自检…' : '自检'),
          subtitle: diagnosis == null ? null : Text(_lines(diagnosis)),
          trailing: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          onTap: _busy ? null : () => unawaited(_check()),
        ),
      ],
    );
  }
}
