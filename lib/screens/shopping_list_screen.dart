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
    final scheme = Theme.of(context).colorScheme;
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;
    final successColor = isDark ? AppTheme.successDark : AppTheme.successLight;
    final completedCount = _checked.where((c) => c).length;
    final progress = widget.items.isEmpty ? 0.0 : completedCount / widget.items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.listName, style: const TextStyle(fontWeight: FontWeight.w700)),
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
              color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$completedCount of ${widget.items.length} items',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${((progress) * 100).round()}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: successColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainer,
                    valueColor: AlwaysStoppedAnimation<Color>(successColor),
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
          _buildAddBar(context, isDark, scheme),
        ],
      ),
    );
  }

  Widget _buildAddBar(
    BuildContext context,
    bool isDark,
    ColorScheme scheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        border: Border(
          top: BorderSide(color: isDark ? AppTheme.hairDark : AppTheme.hairLight),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: TextField(
                  controller: _addItemController,
                  style: Theme.of(context).textTheme.bodyMedium,
                  onSubmitted: (_) => _addItem(),
                  decoration: InputDecoration(
                    hintText: 'Add item…',
                    hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                        ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Material(
              color: AppTheme.emberMain,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _addItem,
                child: const SizedBox(
                  width: AppTheme.sendBtn,
                  height: AppTheme.sendBtn,
                  child: Icon(Icons.add_rounded, color: AppTheme.emberInk, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, int index, bool isDark) {
    final isDarkMode = isDark;
    final scheme = Theme.of(context).colorScheme;
    final item = widget.items[index];
    final checked = _checked[index];
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;

    return Dismissible(
      key: Key('$item-$index'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeItem(index),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(
          Icons.delete_rounded,
          color: isDark ? AppTheme.errorDark : AppTheme.errorLight,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: scheme.outlineVariant),
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  decoration: checked ? TextDecoration.lineThrough : null,
                  color: checked
                      ? (isDarkMode ? AppTheme.ashDark : AppTheme.ashLight)
                      : ink,
                ),
          ),
          activeColor: AppTheme.emberMain,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.r2xl),
        ),
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