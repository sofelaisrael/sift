import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/lam_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedProvider = 'OVHcloud';
  bool _darkMode = false;
  bool _hapticFeedback = true;
  bool _autoAction = false;

  final Map<String, TextEditingController> _keyControllers = {};

  final List<Map<String, dynamic>> _providers = [
    {
      'name': 'OVHcloud',
      'desc': 'Free, no key needed (2 RPM)',
      'color': AppTheme.success,
      'icon': Icons.cloud_rounded,
      'needsKey': false,
      'supportsImage': false,
    },
    {
      'name': 'Google Gemini',
      'desc': 'Best free multimodal (15 RPM)',
      'color': AppTheme.info,
      'icon': Icons.auto_awesome_rounded,
      'needsKey': true,
      'supportsImage': true,
      'keyUrl': 'https://aistudio.google.com/app/apikey',
    },
    {
      'name': 'Groq',
      'desc': 'Ultra-fast inference (30 RPM)',
      'color': AppTheme.primary,
      'icon': Icons.bolt_rounded,
      'needsKey': true,
      'supportsImage': false,
      'keyUrl': 'https://console.groq.com/keys',
    },
    {
      'name': 'Cerebras',
      'desc': 'Fast + multimodal (15 RPM)',
      'color': AppTheme.accent,
      'icon': Icons.memory_rounded,
      'needsKey': true,
      'supportsImage': true,
      'keyUrl': 'https://cloud.cerebras.ai/',
    },
    {
      'name': 'OpenRouter',
      'desc': 'Many free models (20 RPM)',
      'color': AppTheme.warning,
      'icon': Icons.route_rounded,
      'needsKey': true,
      'supportsImage': true,
      'keyUrl': 'https://openrouter.ai/keys',
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
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedProvider = prefs.getString('provider') ?? 'OVHcloud';
      _darkMode = prefs.getBool('darkMode') ?? false;
      _hapticFeedback = prefs.getBool('hapticFeedback') ?? true;
      _autoAction = prefs.getBool('autoAction') ?? false;
    });

    // Load saved API keys
    for (final p in _providers) {
      if (p['needsKey']) {
        final key = prefs.getString('key_${p['name']}') ?? '';
        _keyControllers[p['name']] = TextEditingController(text: key);
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider', _selectedProvider);
    await prefs.setBool('darkMode', _darkMode);
    await prefs.setBool('hapticFeedback', _hapticFeedback);
    await prefs.setBool('autoAction', _autoAction);

    // Save API keys
    for (final p in _providers) {
      if (p['needsKey'] && _keyControllers.containsKey(p['name'])) {
        await prefs.setString('key_${p['name']}', _keyControllers[p['name']]!.text);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: () async {
              await _saveSettings();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings saved')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // AI Provider section
          _buildSectionHeader(context, 'AI Provider', Icons.smart_toy_rounded),
          const SizedBox(height: 4),
          Text(
            'Choose which free AI service to use',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 12),

          // Provider cards
          ..._providers.map((p) => _buildProviderCard(context, p, isDark)),

          // API key input for selected provider
          if (_providers.firstWhere((p) => p['name'] == _selectedProvider)['needsKey'])
            _buildApiKeyInput(context, isDark),

          const SizedBox(height: 32),

          // Appearance section
          _buildSectionHeader(context, 'Appearance', Icons.palette_rounded),
          const SizedBox(height: 12),
          _buildSwitchTile(
            context,
            icon: Icons.dark_mode_rounded,
            title: 'Dark Mode',
            subtitle: 'Follow system theme',
            value: _darkMode,
            color: AppTheme.primary,
            onChanged: (v) {
              setState(() => _darkMode = v);
              _saveSettings();
            },
          ),

          const SizedBox(height: 32),

          // Behavior section
          _buildSectionHeader(context, 'Behavior', Icons.tune_rounded),
          const SizedBox(height: 12),
          _buildSwitchTile(
            context,
            icon: Icons.vibration_rounded,
            title: 'Haptic Feedback',
            subtitle: 'Vibrate on actions',
            value: _hapticFeedback,
            color: AppTheme.accent,
            onChanged: (v) {
              setState(() => _hapticFeedback = v);
              _saveSettings();
            },
          ),
          _buildSwitchTile(
            context,
            icon: Icons.bolt_rounded,
            title: 'Auto-Execute Actions',
            subtitle: 'Execute actions without confirmation',
            value: _autoAction,
            color: AppTheme.warning,
            onChanged: (v) {
              setState(() => _autoAction = v);
              _saveSettings();
            },
          ),

          const SizedBox(height: 32),

          // Info section
          _buildSectionHeader(context, 'About', Icons.info_outline_rounded),
          const SizedBox(height: 12),
          _buildInfoTile(
            context,
            icon: Icons.auto_awesome_rounded,
            title: 'ScreenSort',
            subtitle: 'Version 1.0.0',
            color: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
        ),
      ],
    );
  }

  Widget _buildProviderCard(BuildContext context, Map<String, dynamic> provider, bool isDark) {
    final isSelected = _selectedProvider == provider['name'];
    final color = provider['color'] as Color;
    final needsKey = provider['needsKey'] as bool;
    final keyController = _keyControllers[provider['name']];
    final hasKey = keyController != null && keyController.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() => _selectedProvider = provider['name']);
            _saveSettings();
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.08)
                  : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? color.withValues(alpha: 0.3)
                    : isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.shade100,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(provider['icon'], color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            provider['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isSelected ? color : null,
                            ),
                          ),
                          if (!needsKey) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'FREE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.success,
                                ),
                              ),
                            ),
                          ],
                          if (needsKey && !hasKey) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'NEEDS KEY',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.warning,
                                ),
                              ),
                            ),
                          ],
                          if (provider['supportsImage']) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.info.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'VISION',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.info,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider['desc'],
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildApiKeyInput(BuildContext context, bool isDark) {
    final controller = _keyControllers[_selectedProvider];
    final provider = _providers.firstWhere((p) => p['name'] == _selectedProvider);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, size: 16, color: AppTheme.warning),
              const SizedBox(width: 8),
              Text(
                'API Key for $_selectedProvider',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Paste your API key...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white24 : Colors.black26,
                fontSize: 13,
              ),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              suffixIcon: IconButton(
                icon: const Icon(Icons.visibility_off_rounded, size: 18),
                onPressed: () {},
              ),
            ),
            onChanged: (_) => _saveSettings(),
          ),
          if (provider['keyUrl'] != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                // Would launch URL in production
              },
              child: Text(
                'Get free key → ${provider['keyUrl']}',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
