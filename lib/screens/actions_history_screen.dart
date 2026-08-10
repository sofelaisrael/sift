import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import '../widgets/sift_mark.dart';
import 'shopping_list_screen.dart';

/// Quiet actions history: back + title header with a hairline bottom,
/// de-containerized hairline rows, sentence-case filter chips, and a serif
/// empty state.
class ActionsHistoryScreen extends StatefulWidget {
  const ActionsHistoryScreen({super.key});

  @override
  State<ActionsHistoryScreen> createState() => _ActionsHistoryScreenState();
}

class _ActionsHistoryScreenState extends State<ActionsHistoryScreen> {
  List<Map<String, dynamic>> _actions = [];
  String _filter = 'all';

  static const List<(String, String)> _filters = [
    ('all', 'All'),
    ('calendar', 'Calendar'),
    ('reminder', 'Reminders'),
    ('shopping_list', 'Shopping'),
    ('task', 'Tasks'),
  ];

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

  /// Most recent shopping-list action, if any. _actions is sorted newest
  /// first, so the first match is the latest list.
  Map<String, dynamic>? get _latestShoppingListAction {
    for (final action in _actions) {
      if (action['type'] == 'shopping_list') return action;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: s.canvas,
                border: Border(
                  bottom: BorderSide(
                    color: s.divider,
                    width: AppTheme.hairline(isDark),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: s.ink,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Actions history',
                        style: SiftType.serifTitle.copyWith(color: s.ink),
                      ),
                    ),
                    if (_actions.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear all',
                        onPressed: _clearAll,
                        icon: Icon(
                          Icons.delete_sweep_rounded,
                          color: s.stone,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_actions.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (value, label) in _filters) ...[
                        if (value != _filters.first.$1) const SizedBox(width: 8),
                        _FilterChip(
                          label: label,
                          selected: _filter == value,
                          onTap: () => setState(() => _filter = value),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (_latestShoppingListAction != null)
              _buildShoppingListEntry(context, _latestShoppingListAction!),
            Expanded(
              child: _filteredActions.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      itemCount: _filteredActions.length,
                      itemBuilder: (context, index) {
                        return _buildActionRow(context, _filteredActions[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, Map<String, dynamic> action) {
    final s = AppTheme.of(context);
    final type = action['type'] ?? 'unknown';
    final icon = _typeIcon(type);
    final label = _typeLabel(type);
    final date = action['created_at'] != null
        ? DateFormat('MMM d, h:mm a').format(DateTime.parse(action['created_at']))
        : 'Unknown date';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: s.graphite),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: SiftType.bodySans.copyWith(
                        fontWeight: FontWeight.w600,
                        color: s.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getActionDescription(action),
                      style: SiftType.bodySansMd.copyWith(
                        fontSize: 13,
                        color: s.graphite,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                date,
                style: SiftType.microLabel.copyWith(
                  fontWeight: FontWeight.w500,
                  color: s.stone,
                ),
              ),
            ],
          ),
        ),
        Divider(color: s.divider, height: 1, thickness: 1),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final s = AppTheme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SiftMark(size: 40),
            const SizedBox(height: 28),
            Text(
              'No actions yet',
              textAlign: TextAlign.center,
              style: SiftType.serifDisplay.copyWith(color: s.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Actions will appear here after Sift handles a screenshot.',
              textAlign: TextAlign.center,
              style: SiftType.bodySans.copyWith(
                color: s.graphite,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShoppingListEntry(
    BuildContext context,
    Map<String, dynamic> action,
  ) {
    final s = AppTheme.of(context);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
              _openShoppingList(action);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.shopping_cart_rounded,
                      size: 20, color: s.graphite),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'View shopping list',
                      style: SiftType.bodySans.copyWith(
                        fontWeight: FontWeight.w600,
                        color: s.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: s.stone),
                ],
              ),
            ),
          ),
        ),
        Divider(color: s.divider, height: 1, thickness: 1),
      ],
    );
  }

  void _openShoppingList(Map<String, dynamic> action) {
    final listId = action['id'];
    if (listId == null) return;

    final rawItems = action['items'];
    final items = rawItems is List
        ? List<String>.from(rawItems.whereType<String>())
        : <String>[];

    var listName = 'Shopping list';
    final rawName = action['name'];
    if (rawName is String && rawName.trim().isNotEmpty) {
      listName = rawName;
    }

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ShoppingListScreen(
          listId: listId.toString(),
          listName: listName,
          items: items,
        ),
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
        return Icons.task_alt_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'calendar':
        return 'Calendar event';
      case 'reminder':
        return 'Reminder';
      case 'shopping_list':
        return 'Shopping list';
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
        title: const Text('Clear all actions?'),
        content: const Text('This removes every action from your history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
              final box = Hive.box('actions');
              box.clear();
              setState(() => _actions = []);
              Navigator.pop(context);
            },
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: MotionTokens.standard,
          curve: MotionTokens.easeOutCubic,
          height: SiftSpacing.chipH,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? s.accentSoft : s.surfaceWarm1,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: SiftType.chipLabel.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? s.accentDeep : s.ink,
            ),
          ),
        ),
      ),
    );
  }
}
