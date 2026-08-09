import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_controller.dart';
import '../providers/screenshot_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/sift_mark.dart';
import '../widgets/about_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedProvider = 'Google Gemini';
  bool _hapticFeedback = true;
  bool _localOnly = false;
  bool _autoDetect = true;

  final Map<String, TextEditingController> _keyControllers = {};
  final TextEditingController _youtubeKeyController = TextEditingController();

  final List<Map<String, dynamic>> _providers = [
    {
      'name': 'Google Gemini',
      'desc': 'Free tier · 15 RPM · Best multimodal',
      'icon': Icons.language_rounded,
      'needsKey': true,
      'keyUrl': 'https://aistudio.google.com/app/apikey',
      'recommended': true,
    },
    {
      'name': 'NVIDIA',
      'desc': 'Free tier · 40 RPM · Multimodal (Llama vision)',
      'icon': Icons.developer_board_rounded,
      'needsKey': true,
      'keyUrl': 'https://build.nvidia.com',
      'recommended': false,
    },
    {
      'name': 'Groq',
      'desc': 'Free tier · 30 RPM · Text only',
      'icon': Icons.bolt_rounded,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'More',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ),
        ),
        _sectionTitle(context, 'Get Sift ready'),
        _checklistTile(
          context,
          done: true,
          title: 'Choose provider',
          caption: 'Pick the AI you trust',
        ),
        ..._providers.map((p) => _buildProviderCard(context, p, isDark)),
        if (_providers.firstWhere((p) => p['name'] == _selectedProvider)['needsKey'])
          _buildApiKeyInput(context, isDark),
        _buildYouTubeKeyCard(context, isDark),
        _checklistTile(
          context,
          done: _autoDetect,
          title: 'Enable auto-detect',
          caption: 'Watch for new screenshots',
          trailing: Switch(
            value: _autoDetect,
            onChanged: (v) {
              setState(() => _autoDetect = v);
              _saveSettings();
            },
          ),
        ),
        const SizedBox(height: 32),
        _sectionTitle(context, 'Appearance'),
        _buildAppearanceSection(context),
        const SizedBox(height: 32),
        _sectionTitle(context, 'Behavior'),
        _switchTile(
          context,
          icon: Icons.vibration_rounded,
          title: 'Haptic Feedback',
          subtitle: 'Vibrate on actions',
          value: _hapticFeedback,
          onChanged: (v) {
            setState(() => _hapticFeedback = v);
            _saveSettings();
          },
        ),
        const SizedBox(height: 32),
        _sectionTitle(context, 'Privacy'),
        _switchTile(
          context,
          icon: Icons.offline_bolt_rounded,
          title: 'Local-only mode',
          subtitle: 'Analyze on-device with OCR. Nothing is sent to AI providers; AI chat and web lookups are disabled.',
          value: _localOnly,
          onChanged: (v) {
            setState(() => _localOnly = v);
            context.read<ScreenshotProvider>().setLocalOnly(v);
            _saveSettings();
          },
        ),
        _infoRow(
          context,
          icon: Icons.lock_outline_rounded,
          title: 'What leaves your device',
          subtitle: 'Screenshots go to your chosen AI provider for analysis; optional link lookups query DuckDuckGo/YouTube.',
        ),
        _infoRow(
          context,
          icon: Icons.storage_rounded,
          title: 'Stored locally',
          subtitle: 'Your screenshots, analysis, and chat history are stored on this phone.',
        ),
        _infoRow(
          context,
          icon: Icons.verified_user_outlined,
          title: 'You stay in control',
          subtitle: 'Delete anything, anytime',
        ),
        const SizedBox(height: 8),
        _buildDeleteEverythingTile(context),
        const SizedBox(height: 32),
        _sectionTitle(context, 'About'),
        _aboutTile(context, isDark, ink),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
      ),
    );
  }

  Widget _checklistTile(
    BuildContext context, {
    required bool done,
    required String title,
    required String caption,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;
    final ash = isDark ? AppTheme.ashDark : AppTheme.ashLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(
          color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: done ? AppTheme.emberMain : Colors.transparent,
              shape: BoxShape.circle,
              border: done
                  ? null
                  : Border.all(
                      color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                    ),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 14, color: AppTheme.emberInk)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                ),
                Text(
                  caption,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ash,
                      ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildProviderCard(
    BuildContext context,
    Map<String, dynamic> provider,
    bool isDark,
  ) {
    final isSelected = _selectedProvider == provider['name'];
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() => _selectedProvider = provider['name']);
            _saveSettings();
          },
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              border: Border.all(
                color: isSelected ? AppTheme.emberMain : (isDark ? AppTheme.hairDark : AppTheme.hairLight),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  provider['icon'],
                  size: 20,
                  color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: ink,
                              ),
                            ),
                          ),
                          if (provider['recommended'] == true) ...[
                            const SizedBox(width: 6),
                            _neutralTag(context, 'Recommended'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider['desc'],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                            ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.emberMain,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _neutralTag(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.tagFillDark : AppTheme.tagFillLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.tagTextDark : AppTheme.tagTextLight,
        ),
      ),
    );
  }

  Widget _buildApiKeyInput(BuildContext context, bool isDark) {
    final controller = _keyControllers[_selectedProvider];
    final provider = _providers.firstWhere((p) => p['name'] == _selectedProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(
          color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            obscureText: true,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Paste your API key…',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                  ),
              filled: true,
              fillColor: isDark ? AppTheme.raisedDark : AppTheme.raisedLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                borderSide: BorderSide(
                  color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                borderSide: BorderSide(
                  color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                borderSide: const BorderSide(color: AppTheme.emberMain, width: 1.5),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (_) => _saveSettings(),
          ),
          if (provider['keyUrl'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Get a free key → ${provider['keyUrl']}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.emberMain,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildYouTubeKeyCard(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(
          color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.play_circle_outline_rounded,
                size: 20,
                color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YouTube Data API key',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppTheme.inkDark : AppTheme.inkLight,
                          ),
                    ),
                    Text(
                      'Optional — for better video lookups, works without it',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _youtubeKeyController,
            obscureText: true,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Paste your YouTube API key…',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                  ),
              filled: true,
              fillColor: isDark ? AppTheme.raisedDark : AppTheme.raisedLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                borderSide: BorderSide(
                  color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                borderSide: BorderSide(
                  color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                borderSide: const BorderSide(color: AppTheme.emberMain, width: 1.5),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (_) => _saveSettings(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Get a free key → https://console.cloud.google.com/apis/credentials',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.emberMain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context) {
    final themeController = context.watch<ThemeController>();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            label: Text('Light'),
            icon: Icon(Icons.light_mode_outlined, size: 18),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text('Dark'),
            icon: Icon(Icons.dark_mode_outlined, size: 18),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            label: Text('System'),
            icon: Icon(Icons.brightness_auto_outlined, size: 18),
          ),
        ],
        selected: {themeController.themeMode},
        onSelectionChanged: (selection) {
          themeController.setMode(selection.first);
        },
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity(horizontal: 0, vertical: 0),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 10)),
        ),
      ),
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(
          color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(
          color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteEverythingTile(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errorColor = isDark ? AppTheme.errorDark : AppTheme.errorLight;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _confirmDeleteEverything(context),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: errorColor.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.delete_forever_rounded, size: 20, color: errorColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete everything',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: errorColor,
                          ),
                    ),
                    Text(
                      'Wipe all saved screenshots, chat, actions, and settings',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppTheme.slateDark
                                : AppTheme.slateLight,
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

  Future<void> _confirmDeleteEverything(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.r2xl),
        ),
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
    if (confirmed != true || !mounted) return;

    await context.read<ScreenshotProvider>().deleteEverything();
    if (!mounted) return;

    setState(() {
      _selectedProvider = 'Google Gemini';
      _localOnly = false;
      _autoDetect = true;
      _hapticFeedback = true;
    });
    for (final c in _keyControllers.values) {
      c.clear();
    }
    _youtubeKeyController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Everything deleted')),
    );
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Widget _aboutTile(BuildContext context, bool isDark, Color ink) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => PremiumAboutDialog.show(context),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
            ),
          ),
          child: Row(
            children: [
              const SiftMark(size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sift',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                    ),
                    Text(
                      'Version 1.0.0',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
