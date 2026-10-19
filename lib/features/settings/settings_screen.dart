import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final s = ref.watch(settingsProvider).value ?? const AppSettings();
    final n = ref.read(settingsProvider.notifier);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AetherTokens.s4,
        AetherTokens.s6,
        AetherTokens.s4,
        AetherTokens.s2,
      ),
      child: Text(title, style: text.label.copyWith(color: t.inkMuted)),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: AetherIcon(AetherIcons.back, color: t.ink),
        ),
        title: Text('Settings', style: text.panelTitle),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            children: [
              section('Appearance'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherTokens.s4,
                ),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => n.setThemeMode(v.first),
                ),
              ),
              section('Input'),
              SwitchListTile(
                value: s.fingerDraws,
                onChanged: n.setFingerDraws,
                title: Text('Finger draws', style: text.title),
                subtitle: Text(
                  'Off: a finger pans and zooms, and only a pen or mouse marks. '
                  'Turn on to mark with a finger, for example on a phone without a stylus.',
                  style: text.caption.copyWith(color: t.inkMuted),
                ),
              ),
              SwitchListTile(
                value: s.leftHanded,
                onChanged: n.setLeftHanded,
                title: Text('Left-handed layout', style: text.title),
                subtitle: Text(
                  'Moves the tools and Extract to the opposite sides.',
                  style: text.caption.copyWith(color: t.inkMuted),
                ),
              ),
              section('Diagnostics'),
              SwitchListTile(
                value: s.perfHud,
                onChanged: n.setPerfHud,
                title: Text('Performance overlay', style: text.title),
                subtitle: Text(
                  'Shows frame times and the display refresh rate over the canvas. '
                  'Use a profile build for honest numbers.',
                  style: text.caption.copyWith(color: t.inkMuted),
                ),
              ),
              section('About'),
              ListTile(
                title: Text('Licenses', style: text.title),
                subtitle: Text(
                  'Figtree and Source Serif 4 (SIL OFL), pdfium, SQLite and more.',
                  style: text.caption.copyWith(color: t.inkMuted),
                ),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Aether',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
