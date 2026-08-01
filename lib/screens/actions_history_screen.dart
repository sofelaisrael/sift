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
      final dateA = DateTime.parse(a['created_at'] ?? DateTime.now().toIso8601String());
      final dateB = DateTime.parse(b['created_at'] ?? DateTime.now().toIso8601String());
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Actions',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
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
          // Filter chips
          if (_actions.isNotEmpty)
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip('all', 'All', Icons.all_inclusive_rounded),
                  _buildFilterChip('calendar', 'Calendar', Icons.calendar_today_rounded),
                  _buildFilterChip('reminder', 'Reminders', Icons.notifications_rounded),
                  _buildFilterChip('shopping_list', 'Shopping', Icons.shopping_cart_rounded),
                  _buildFilterChip('task', 'Tasks', Icons.check_circle_rounded),
                ],
              ),
            ),

          // Actions list
          Expanded(
            child: _filteredActions.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredActions.length,
                    itemBuilder: (context, index) {
                      return _buildActionCard(context, _filteredActions[index], isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final isSelected = _filter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        selected: isSelected,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: AppTheme.primary.withValues(alpha: 0.12),
        checkmarkColor: AppTheme.primary,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.primary : null,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, Map<String, dynamic> action, bool isDark) {
    final type = action['type'] ?? 'unknown';
    final color = _typeColor(type);
    final icon = _typeIcon(type);
    final label = _typeLabel(type);
    final date = action['created_at'] != null
        ? DateFormat('MMM d, h:mm a').format(DateTime.parse(action['created_at']))
        : 'Unknown date';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getActionDescription(action),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
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
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_rounded,
            size: 64,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          const SizedBox(height: 16),
          Text(
            'No actions yet',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Actions will appear here after\nyou scan screenshots',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'calendar':
        return AppTheme.info;
      case 'reminder':
        return AppTheme.warning;
      case 'shopping_list':
        return AppTheme.success;
      case 'task':
        return AppTheme.primary;
      default:
        return Colors.grey;
    }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
