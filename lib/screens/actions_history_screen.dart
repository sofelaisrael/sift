import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

class ActionsHistoryScreen extends StatefulWidget {
  const ActionsHistoryScreen({super.key});

  @override
  State<ActionsHistoryScreen> createState() => _ActionsHistoryScreenState();
}

class _ActionsHistoryScreenState extends State<ActionsHistoryScreen> {
  List<Map<String, dynamic>> _actions = [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadActions();
  }

  void _loadActions() {
    final box = Hive.box('actions');
    final actions = box.keys.map((key) {
      final value = box.get(key);
      final data = Map<String, dynamic>.from(value);
      data['id'] = key;
      return data;
    }).toList();

    actions.sort((a, b) {
      final dateA =
          DateTime.parse(a['created_at'] ?? DateTime.now().toIso8601String());
      final dateB =
          DateTime.parse(b['created_at'] ?? DateTime.now().toIso8601String());
      return dateB.compareTo(dateA);
    });

    setState(() => _actions = actions);
  }

  List<Map<String, dynamic>> get _filteredActions {
    if (_filter == 'all') return _actions;
    return _actions.where((a) => a['type'] == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Actions', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_actions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_actions.isNotEmpty)
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip('all', 'All'),
                  _buildFilterChip('calendar', 'Calendar'),
                  _buildFilterChip('reminder', 'Reminders'),
                  _buildFilterChip('shopping_list', 'Shopping'),
                  _buildFilterChip('task', 'Tasks'),
                ],
              ),
            ),
          Expanded(
            child: _filteredActions.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredActions.length,
                    itemBuilder: (context, index) {
                      return _buildActionCard(context, _filteredActions[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _filter == value;
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _filter = value),
        showCheckmark: false,
        backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        selectedColor: isDark ? AppTheme.raisedDark : AppTheme.raisedLight,
        side: BorderSide(
          color: isSelected ? AppTheme.emberMain : scheme.outlineVariant,
          width: isSelected ? 1.5 : 1,
        ),
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.emberMain : ink,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.chipH / 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, Map<String, dynamic> action) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;
    final type = action['type'] ?? 'unknown';
    final icon = _typeIcon(type);
    final label = _typeLabel(type);
    final date = action['created_at'] != null
        ? DateFormat('MMM d, h:mm a').format(DateTime.parse(action['created_at']))
        : 'Unknown date';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ink),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getActionDescription(action),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            date,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_rounded,
            size: 56,
            color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
          ),
          const SizedBox(height: 16),
          Text(
            'No actions yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Actions will appear here after\nyou scan screenshots',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'calendar':
        return Icons.calendar_today_rounded;
      case 'reminder':
        return Icons.notifications_rounded;
      case 'shopping_list':
        return Icons.shopping_cart_rounded;
      case 'task':
        return Icons.check_circle_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'calendar':
        return 'Calendar Event';
      case 'reminder':
        return 'Reminder';
      case 'shopping_list':
        return 'Shopping List';
      case 'task':
        return 'Task';
      default:
        return 'Unknown';
    }
  }

  String _getActionDescription(Map<String, dynamic> action) {
    final data = action['data'];
    if (data == null) return 'No details';

    if (data is Map) {
      return data['title'] ?? data['name'] ?? data['list_name'] ?? 'No details';
    }

    return 'No details';
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.r2xl),
        ),
        title: const Text('Clear All Actions?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final box = Hive.box('actions');
              box.clear();
              setState(() => _actions = []);
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}