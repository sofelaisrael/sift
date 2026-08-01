import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = false;
  String _selectedModel = 'openrouter/free';
  bool _hapticFeedback = true;
  bool _autoAction = false;

  final List<Map<String, String>> _models = [
    {'id': 'openrouter/free', 'name': 'Auto (Recommended)', 'desc': 'Best free model selected automatically'},
    {'id': 'google/gemma-4-31b-it:free', 'name': 'Gemma 4 31B', 'desc': 'Google multimodal, 262K context'},
    {'id': 'nvidia/nemotron-nano-12b-v2-vl:free', 'name': 'Nemotron Vision', 'desc': 'NVIDIA vision-language model'},
    {'id': 'openai/gpt-oss-20b:free', 'name': 'GPT-OSS 20B', 'desc': 'OpenAI open source model'},
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // AI Model section
          _buildSectionHeader(context, 'AI Model', Icons.smart_toy_rounded),
          const SizedBox(height: 12),
          ..._models.map((model) => _buildModelOption(context, model, isDark)),

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
            onChanged: (v) => setState(() => _darkMode = v),
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
            onChanged: (v) => setState(() => _hapticFeedback = v),
          ),
          _buildSwitchTile(
            context,
            icon: Icons.bolt_rounded,
            title: 'Auto-Execute Actions',
            subtitle: 'Execute actions without confirmation',
            value: _autoAction,
            color: AppTheme.warning,
            onChanged: (v) => setState(() => _autoAction = v),
          ),

          const SizedBox(height: 32),

          // About section
          _buildSectionHeader(context, 'About', Icons.info_outline_rounded),
          const SizedBox(height: 12),
          _buildInfoTile(
            context,
            icon: Icons.auto_awesome_rounded,
            title: 'ScreenSort',
            subtitle: 'Version 1.0.0',
            color: AppTheme.primary,
          ),
          _buildInfoTile(
            context,
            icon: Icons.code_rounded,
            title: 'Open Source',
            subtitle: 'Built with Flutter',
            color: AppTheme.accent,
          ),

          const SizedBox(height: 40),
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

  Widget _buildModelOption(BuildContext context, Map<String, String> model, bool isDark) {
    final isSelected = _selectedModel == model['id'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedModel = model['id']!),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary.withValues(alpha: 0.08)
                  : isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primary.withValues(alpha: 0.3)
                    : isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.shade100,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model['name']!,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isSelected ? AppTheme.primary : null,
                        ),
                      ),
                      Text(
                        model['desc']!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
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
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
