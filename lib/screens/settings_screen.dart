import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/theme_controller.dart';
import '../providers/screenshot_provider.dart';
import '../services/ingest_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import '../widgets/sift_mark.dart';
import '../widgets/about_dialog.dart';
import 'actions_history_screen.dart';

/// The More tab. A single flat ListView with zero bordered cards: Library
/// cluster, the "Get Sift ready" checklist, Appearance, Behavior, Privacy
/// and About. [checklistKey] is attached to the checklist so the onboarding
/// "Set up Sift" deep link can scroll it into view.
class SettingsScreen extends StatefulWidget {
  final GlobalKey? checklistKey;

  const SettingsScreen({super.key, this.checklistKey});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedProvider = 'Google Gemini';
  bool _hapticFeedback = true;
  bool _localOnly = false;
  bool _autoDetect = true;
  int _expandedStep = 0;

  final Map<String, TextEditingController> _keyControllers = {};
  final TextEditingController _youtubeKeyController = TextEditingController();

  final List<Map<String, dynamic>> _providers = [
    {
      'name': 'Google Gemini',
      'desc': 'Free tier, 15 requests per minute, multimodal',
      'needsKey': true,
      'keyUrl': 'https://aistudio.google.com/app/apikey',
      'recommended': true,
    },
    {
      'name': 'NVIDIA',
      'desc': 'Free tier, 40 requests per minute, multimodal',
      'needsKey': true,
      'keyUrl': 'https://build.nvidia.com',
      'recommended': false,
    },
    {
      'name': 'Groq',
      'desc': 'Free tier, 30 requests per minute, text only',
      'needsKey': true,
      'keyUrl': 'https://console.groq.com/keys',
      'recommended': false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    _youtubeKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedProvider = prefs.getString('provider') ?? 'Google Gemini';
      if (!_providers.any((p) => p['name'] == _selectedProvider)) {
        _selectedProvider = 'Google Gemini';
      }
      _hapticFeedback = prefs.getBool('hapticFeedback') ?? true;
      _localOnly = prefs.getBool('localOnly') ?? false;
      _autoDetect = prefs.getBool('autoDetect') ?? true;
    });
    MotionTokens.hapticsEnabled = _hapticFeedback;

    for (final p in _providers) {
      if (p['needsKey'] == true) {
        final key = prefs.getString('key_${p['name']}') ?? '';
        _keyControllers[p['name']] = TextEditingController(text: key);
      }
    }
    _youtubeKeyController.text = prefs.getString('key_youtube') ?? '';
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider', _selectedProvider);
    await prefs.setBool('hapticFeedback', _hapticFeedback);
    await prefs.setBool('localOnly', _localOnly);
    await prefs.setBool('autoDetect', _autoDetect);

    for (final p in _providers) {
      if (p['needsKey'] == true && _keyControllers.containsKey(p['name'])) {
        await prefs.setString(
          'key_${p['name']}',
          _keyControllers[p['name']]!.text,
        );
      }
    }
    await prefs.setString('key_youtube', _youtubeKeyController.text);
  }

  bool get _hasKey {
    final controller = _keyControllers[_selectedProvider];
    return controller != null && controller.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'More',
              style: SiftType.serifTitle.copyWith(color: s.ink),
            ),
          ),
          _sectionTitle(context, 'Library'),
          _flatRow(
            context,
            icon: Icons.history_rounded,
            title: 'Actions history',
            subtitle: 'Everything Sift has done for you',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ActionsHistoryScreen()),
            ),
          ),
          Builder(
            builder: (context) {
              final ingest = context.watch<IngestService>();
              final running = ingest.isIngesting;
              final subtitle = running
                  ? 'Indexing on-device… ${ingest.processedCount} so far'
                  : 'Remember screenshots already in your library. Runs entirely on your device.';
              return _flatRow(
                context,
                icon: Icons.photo_library_rounded,
                title: 'Index my library',
                subtitle: subtitle,
                iconColor: running ? s.accentDeep : null,
                titleColor: running ? s.accentDeep : null,
                onTap: () => _onLibraryIndexTap(context),
                trailing: running
                    ? IconButton(
                        tooltip: ingest.paused ? 'Resume' : 'Pause',
                        onPressed: () {
                          if (ingest.paused) {
                            ingest.resume();
                          } else {
                            ingest.pause();
                          }
                        },
                        icon: Icon(
                          ingest.paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          size: 20,
                          color: s.ink,
                        ),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 40, minHeight: 40),
                      )
                    : null,
              );
            },
          ),
          const _SectionGap(),
          _sectionTitle(context, 'Get Sift ready'),
          if (widget.checklistKey != null) Container(key: widget.checklistKey),
          _checklistStep(
            context,
            number: 1,
            title: 'Choose a provider',
            caption: 'Pick the AI you trust',
            done: true,
            expanded: _expandedStep == 0,
            onTap: () =>
                setState(() => _expandedStep = _expandedStep == 0 ? -1 : 0),
            child: Column(
              children:
                  _providers.map((p) => _providerRow(context, p)).toList(),
            ),
          ),
          _checklistStep(
            context,
            number: 2,
            title: 'Add your API key',
            caption: _hasKey ? 'Saved' : 'Needed for $_selectedProvider',
            done: _hasKey,
            expanded: _expandedStep == 1,
            onTap: () =>
                setState(() => _expandedStep = _expandedStep == 1 ? -1 : 1),
            child: _buildKeySection(context),
          ),
          _checklistStep(
            context,
            number: 3,
            title: 'Enable auto-detect',
            caption: 'Watch for new screenshots',
            done: _autoDetect,
            expanded: _expandedStep == 2,
            trailing: _flatSwitch(
              value: _autoDetect,
              onChanged: (v) {
                setState(() => _autoDetect = v);
                _saveSettings();
              },
            ),
            onTap: () =>
                setState(() => _expandedStep = _expandedStep == 2 ? -1 : 2),
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                'When a new screenshot appears in your gallery, Sift can analyze it without being asked.',
                style: SiftType.bodySansMd.copyWith(
                  fontSize: 14,
                  height: 1.45,
                  color: s.graphite,
                ),
              ),
            ),
          ),
          const _SectionGap(),
          _sectionTitle(context, 'Appearance'),
          _ThemeSegmented(
            value: context.watch<ThemeController>().themeMode,
            onChanged: (mode) => context.read<ThemeController>().setMode(mode),
          ),
          const _SectionGap(),
          _sectionTitle(context, 'Behavior'),
          _flatRow(
            context,
            icon: Icons.vibration_rounded,
            title: 'Haptic feedback',
            subtitle: 'Vibrate on actions',
            trailing: _flatSwitch(
              value: _hapticFeedback,
              onChanged: (v) {
                setState(() => _hapticFeedback = v);
                MotionTokens.hapticsEnabled = v;
                _saveSettings();
              },
            ),
          ),
          const _SectionGap(),
          _sectionTitle(context, 'Privacy'),
          _flatRow(
            context,
            icon: Icons.offline_bolt_rounded,
            title: 'Local-only mode',
            subtitle:
                'Analyze on-device with OCR. Nothing is sent to AI providers; AI chat and web lookups are disabled.',
            trailing: _flatSwitch(
              value: _localOnly,
              onChanged: (v) {
                setState(() => _localOnly = v);
                context.read<ScreenshotProvider>().setLocalOnly(v);
                _saveSettings();
              },
            ),
          ),
          _infoRow(
            context,
            icon: Icons.lock_outline_rounded,
            title: 'What leaves your device',
            subtitle:
                'Screenshots go to your chosen AI provider for analysis; optional link lookups query DuckDuckGo and YouTube.',
          ),
          _infoRow(
            context,
            icon: Icons.storage_rounded,
            title: 'Stored locally',
            subtitle:
                'Your screenshots, analysis, and chat history are stored on this phone.',
          ),
          _infoRow(
            context,
            icon: Icons.verified_user_outlined,
            title: 'You stay in control',
            subtitle: 'Delete anything, anytime',
          ),
          const SizedBox(height: 8),
          _buildDeleteEverythingTile(context),
          const _SectionGap(),
          _sectionTitle(context, 'About'),
          _aboutRow(context),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final s = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: SiftType.chromeTitle.copyWith(
          color: s.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _checklistStep(
    BuildContext context, {
    required int number,
    required String title,
    required String caption,
    required bool done,
    required bool expanded,
    required VoidCallback onTap,
    required Widget child,
    Widget? trailing,
  }) {
    final s = AppTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SiftRadii.rField),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                AnimatedScale(
                  scale: done ? 0.9 : 1.0,
                  duration: MotionTokens.standard,
                  curve: MotionTokens.easeOutCubic,
                  child: AnimatedContainer(
                    duration: MotionTokens.standard,
                    curve: MotionTokens.easeOutCubic,
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: done ? s.accentSoft : s.surfaceWarm2,
                      shape: BoxShape.circle,
                    ),
                    child: done
                        ? Icon(Icons.check_rounded, size: 16, color: s.accent)
                        : Center(
                            child: Text(
                              '$number',
                              style: SiftType.chipLabel.copyWith(
                                color: s.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: SiftType.bodySans.copyWith(
                          fontWeight: FontWeight.w600,
                          color: s.ink,
                        ),
                      ),
                      Text(
                        caption,
                        style: SiftType.bodySansMd.copyWith(
                          fontSize: 13,
                          color: s.stone,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: s.stone,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: MotionTokens.emphasis,
          curve: MotionTokens.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: child,
                )
              : const SizedBox(width: double.infinity),
        ),
        Divider(color: s.divider, height: 1, thickness: 1),
      ],
    );
  }

  Widget _providerRow(BuildContext context, Map<String, dynamic> provider) {
    final s = AppTheme.of(context);
    final isSelected = _selectedProvider == provider['name'];

    return InkWell(
      onTap: () {
        if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
        setState(() => _selectedProvider = provider['name']);
        _saveSettings();
      },
      borderRadius: BorderRadius.circular(SiftRadii.rField),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: MotionTokens.standard,
              curve: MotionTokens.easeOutCubic,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected ? s.accentSoft : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? s.accentDeep : s.divider,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check_rounded, size: 14, color: s.accentDeep)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          provider['name'],
                          style: SiftType.bodySans.copyWith(
                            fontWeight: FontWeight.w600,
                            color: s.ink,
                          ),
                        ),
                      ),
                      if (provider['recommended'] == true) ...[
                        const SizedBox(width: 6),
                        _quietTag(context, 'Recommended'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    provider['desc'],
                    style: SiftType.bodySansMd.copyWith(
                      fontSize: 13,
                      color: s.graphite,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quietTag(BuildContext context, String label) {
    final s = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: s.badgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: SiftType.microLabel.copyWith(
          fontWeight: FontWeight.w600,
          color: s.badgeText,
        ),
      ),
    );
  }

  Widget _buildKeySection(BuildContext context) {
    final s = AppTheme.of(context);
    final controller = _keyControllers[_selectedProvider];
    final provider =
        _providers.firstWhere((p) => p['name'] == _selectedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _keyField(
          context,
          controller: controller,
          hint: 'Paste your API key…',
          onChanged: (_) => _saveSettings(),
        ),
        if (provider['keyUrl'] != null) ...[
          const SizedBox(height: 8),
          _linkRow(context, 'Get a free key', provider['keyUrl'] as String),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.play_circle_outline_rounded,
                size: 20, color: s.graphite),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'YouTube Data API key (optional)',
                style: SiftType.bodySansMd.copyWith(
                  fontWeight: FontWeight.w600,
                  color: s.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Used for better video lookups; Sift works without it.',
          style: SiftType.bodySansMd.copyWith(
            fontSize: 13,
            color: s.stone,
          ),
        ),
        const SizedBox(height: 8),
        _keyField(
          context,
          controller: _youtubeKeyController,
          hint: 'Paste your YouTube API key…',
          onChanged: (_) => _saveSettings(),
        ),
        const SizedBox(height: 4),
        _linkRow(
          context,
          'Get a free key',
          'https://console.cloud.google.com/apis/credentials',
        ),
      ],
    );
  }

  Widget _keyField(
    BuildContext context, {
    required TextEditingController? controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: s.paper,
        borderRadius: BorderRadius.circular(SiftRadii.rField),
        border: Border.all(
          color: s.divider,
          width: AppTheme.hairline(isDark),
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: true,
        style: SiftType.bodySans.copyWith(color: s.ink),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: SiftType.bodySans.copyWith(
            fontSize: 15,
            color: s.stone,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _linkRow(BuildContext context, String label, String url) {
    final s = AppTheme.of(context);

    return InkWell(
      onTap: () => _openUrl(url),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: SiftType.bodySansMd.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: s.accent,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.open_in_new_rounded, size: 14, color: s.accent),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open URL: $e');
    }
  }

  Widget _flatRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    final s = AppTheme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SiftRadii.rField),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? s.graphite),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SiftType.bodySans.copyWith(
                      fontWeight: FontWeight.w600,
                      color: titleColor ?? s.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: SiftType.bodySansMd.copyWith(
                      fontSize: 13,
                      height: 1.4,
                      color: s.graphite,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 20, color: s.stone),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final s = AppTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: s.stone),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SiftType.bodySans.copyWith(
                    fontWeight: FontWeight.w600,
                    color: s.ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: SiftType.bodySansMd.copyWith(
                    fontSize: 13,
                    height: 1.4,
                    color: s.stone,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flatSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Switch(value: value, onChanged: onChanged);
  }

  Widget _buildDeleteEverythingTile(BuildContext context) {
    final s = AppTheme.of(context);

    return InkWell(
      onTap: () => _confirmDeleteEverything(context),
      borderRadius: BorderRadius.circular(SiftRadii.rField),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.delete_forever_rounded, size: 20, color: s.error),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete everything',
                    style: SiftType.bodySans.copyWith(
                      fontWeight: FontWeight.w600,
                      color: s.error,
                    ),
                  ),
                  Text(
                    'Wipe all saved screenshots, chat, actions, and settings',
                    style: SiftType.bodySansMd.copyWith(
                      fontSize: 13,
                      color: s.stone,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteEverything(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = context.read<ScreenshotProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete everything?'),
        content: const Text(
          'This permanently deletes everything Sift owns: saved screenshots and their analysis, chat history, actions, settings, saved API keys, and search history. Your gallery photos are untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
    await provider.deleteEverything();
    if (!mounted) return;

    setState(() {
      _selectedProvider = 'Google Gemini';
      _localOnly = false;
      _autoDetect = true;
      _hapticFeedback = true;
    });
    MotionTokens.hapticsEnabled = true;
    for (final c in _keyControllers.values) {
      c.clear();
    }
    _youtubeKeyController.clear();

    messenger.showSnackBar(
      const SnackBar(content: Text('Everything deleted')),
    );
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _onLibraryIndexTap(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ingest = context.read<IngestService>();

    if (ingest.isIngesting) {
      if (ingest.paused) {
        ingest.resume();
      } else {
        ingest.pause();
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Index my library?'),
        content: const Text(
          'Sift will read every screenshot already in your screenshot folders '
          'and remember it with on-device OCR. It runs entirely on this '
          'device: nothing is uploaded, and no photo is ever modified or '
          'deleted. You can pause or stop it anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Index library'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final granted = await _ensurePhotoAccess();
    if (!mounted) return;

    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Sift needs photo access to read your screenshot folders',
          ),
        ),
      );
      return;
    }

    if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
    // Fire-and-forget: a full pass can take a while; progress is surfaced
    // through the banner and this row's live subtitle.
    ingest.start().catchError((Object e) {
      debugPrint('Library index failed: $e');
    });
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Indexing your library…')),
    );
  }

  Future<bool> _ensurePhotoAccess() async {
    if (!kIsWeb && Platform.isAndroid) {
      if (await Permission.photos.isGranted) return true;
      return await Permission.photos.request() == PermissionStatus.granted;
    }
    return true;
  }

  Widget _aboutRow(BuildContext context) {
    final s = AppTheme.of(context);

    return InkWell(
      onTap: () => PremiumAboutDialog.show(context),
      borderRadius: BorderRadius.circular(SiftRadii.rField),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            const SiftMark(size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sift',
                    style: SiftType.serifSubhead.copyWith(
                      fontWeight: FontWeight.w600,
                      color: s.ink,
                    ),
                  ),
                  Text(
                    'Version 1.0.0',
                    style: SiftType.metaLabel.copyWith(color: s.stone),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: s.stone),
          ],
        ),
      ),
    );
  }
}

class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 32);
  }
}

/// Custom segmented theme control: surfaceWarm1 container (r16), selected
/// segment gets a paper thumb (r13) with a 200ms lerp.
class _ThemeSegmented extends StatelessWidget {
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeSegmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final options = <(ThemeMode, String)>[
      (ThemeMode.light, 'Light'),
      (ThemeMode.dark, 'Dark'),
      (ThemeMode.system, 'System'),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? s.surfaceWarm2 : s.surfaceWarm1,
        borderRadius: BorderRadius.circular(SiftRadii.rField),
      ),
      child: Row(
        children: [
          for (final (mode, label) in options)
            Expanded(
              child: InkWell(
                onTap: () {
                  if (MotionTokens.canHaptic) HapticFeedback.selectionClick();
                  onChanged(mode);
                },
                borderRadius: BorderRadius.circular(SiftRadii.rThumb),
                child: AnimatedContainer(
                  duration: MotionTokens.standard,
                  curve: MotionTokens.easeOutCubic,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: mode == value ? s.paper : Colors.transparent,
                    borderRadius: BorderRadius.circular(SiftRadii.rThumb),
                  ),
                  child: Text(
                    label,
                    style: SiftType.chipLabel.copyWith(
                      fontWeight:
                          mode == value ? FontWeight.w600 : FontWeight.w500,
                      color: mode == value ? s.ink : s.stone,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
