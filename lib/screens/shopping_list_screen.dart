import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../theme/app_theme.dart';

class ShoppingListScreen extends StatefulWidget {
  final String listId;
  final String listName;
  final List<String> items;

  const ShoppingListScreen({
    super.key,
    required this.listId,
    required this.listName,
    required this.items,
  });

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  late List<bool> _checked;
  final TextEditingController _addItemController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checked = List<bool>.filled(widget.items.length, false);
  }

  @override
  void dispose() {
    _addItemController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final completedCount = _checked.where((c) => c).length;
    final progress = widget.items.isEmpty ? 0.0 : completedCount / widget.items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.listName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _deleteList,
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress header
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.success.withValues(alpha: 0.08),
                  AppTheme.accent.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.success.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        backgroundColor: AppTheme.success.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
                      ),
                      Center(
                        child: Text(
                          '$completedCount',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppTheme.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$completedCount of ${widget.items.length} items',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        progress >= 1.0 ? 'All done!' : '${((1 - progress) * 100).toInt()}% remaining',
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

          // Items list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                return _buildItemTile(context, index, isDark);
              },
            ),
          ),

          // Add item
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.cardDark : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addItemController,
                      decoration: InputDecoration(
                        hintText: 'Add item...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _addItem(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, int index, bool isDark) {
    final item = widget.items[index];
    final checked = _checked[index];

    return Dismissible(
      key: Key('$item-$index'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeItem(index),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_rounded, color: AppTheme.error),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: CheckboxListTile(
          value: checked,
          onChanged: (value) {
            setState(() {
              _checked[index] = value ?? false;
            });
            _saveProgress();
          },
          title: Text(
            item,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              decoration: checked ? TextDecoration.lineThrough : null,
              color: checked
                  ? isDark
                      ? Colors.white24
                      : Colors.black26
                  : null,
            ),
          ),
          activeColor: AppTheme.success,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  void _addItem() {
    final text = _addItemController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      widget.items.add(text);
      _checked.add(false);
    });
    _addItemController.clear();
    _saveProgress();
  }

  void _removeItem(int index) {
    setState(() {
      widget.items.removeAt(index);
      _checked.removeAt(index);
    });
    _saveProgress();
  }

  void _deleteList() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete List?'),
        content: Text('"${widget.listName}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final box = Hive.box('actions');
              box.delete(widget.listId);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _saveProgress() {
    final box = Hive.box('actions');
    final data = box.get(widget.listId);
    if (data != null) {
      data['items'] = widget.items;
      data['checked'] = _checked;
      box.put(widget.listId, data);
    }
  }
}
