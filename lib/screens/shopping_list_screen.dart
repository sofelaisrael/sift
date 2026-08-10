import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import '../widgets/sift_mark.dart';

/// Quiet shopping list: back + title header, one sentence of progress
/// ("2 of 5 items" — no percent, no bar), flat checkbox rows with
/// line-through, a paper add bar with an accentDeep circle, and swipe to
/// delete.
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

  int get _completedCount => _checked.where((c) => c).length;

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.items.length;

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
                        widget.listName,
                        style: SiftType.serifTitle.copyWith(color: s.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete list',
                      onPressed: _deleteList,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: s.stone,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$_completedCount of $total '
                    '${total == 1 ? 'item' : 'items'}',
                    style: SiftType.tabular(
                      SiftType.bodySansMd.copyWith(
                        fontWeight: FontWeight.w500,
                        color: s.graphite,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: total == 0
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      itemCount: total,
                      itemBuilder: (context, index) {
                        return _buildItemTile(context, index);
                      },
                    ),
            ),
            _buildAddBar(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildAddBar(BuildContext context, bool isDark) {
    final s = AppTheme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(
        color: s.canvas,
        border: Border(
          top: BorderSide(
            color: s.divider,
            width: AppTheme.hairline(isDark),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: s.paper,
                  borderRadius: BorderRadius.circular(SiftRadii.rField),
                  border: Border.all(
                    color: s.divider,
                    width: AppTheme.hairline(isDark),
                  ),
                ),
                child: TextField(
                  controller: _addItemController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addItem(),
                  style: SiftType.bodySans.copyWith(color: s.ink),
                  decoration: InputDecoration(
                    hintText: 'Add an item…',
                    hintStyle: SiftType.bodySans.copyWith(
                      fontSize: 15,
                      color: s.stone,
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
            const SizedBox(width: 8),
            _AddItemCircle(onPressed: _addItem),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, int index) {
    final s = AppTheme.of(context);
    final item = widget.items[index];
    final checked = _checked[index];

    return Dismissible(
      key: Key('$item-$index'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeItem(index),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: s.surfaceWarm1,
        child: Icon(Icons.delete_rounded, size: 20, color: s.error),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: checked,
            onChanged: (value) {
              if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
              setState(() {
                _checked[index] = value ?? false;
              });
              _saveProgress();
            },
            activeColor: s.accentDeep,
            checkColor: s.onAccent,
            title: Text(
              item,
              style: SiftType.bodySans.copyWith(
                fontWeight: FontWeight.w500,
                decoration: checked ? TextDecoration.lineThrough : null,
                color: checked ? s.stone : s.ink,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Divider(color: s.divider, height: 1, thickness: 1),
        ],
      ),
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
              'Nothing to buy yet',
              textAlign: TextAlign.center,
              style: SiftType.serifDisplay.copyWith(color: s.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Add items below and Sift will keep them for you.',
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
        title: const Text('Delete this list?'),
        content: Text('"${widget.listName}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
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

/// 40pt accentDeep circle for adding a shopping item.
class _AddItemCircle extends StatefulWidget {
  final VoidCallback onPressed;

  const _AddItemCircle({required this.onPressed});

  @override
  State<_AddItemCircle> createState() => _AddItemCircleState();
}

class _AddItemCircleState extends State<_AddItemCircle> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (MotionTokens.enabled) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
        widget.onPressed();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: MotionTokens.press,
        curve: MotionTokens.easeOutCubic,
        child: Container(
          width: SiftSpacing.sendBtn,
          height: SiftSpacing.sendBtn,
          decoration: BoxDecoration(
            color: s.accentDeep,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.add_rounded, size: 20, color: s.onAccent),
        ),
      ),
    );
  }
}
