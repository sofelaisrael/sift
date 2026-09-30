import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brutal_tokens.dart';
import '../theme/motion_tokens.dart';

/// The app's one text-input treatment.
///
/// All five inputs in the app are the same shape: a decorated box around a
/// [TextField] whose own [InputBorder] is `none`, so the border lives on the
/// container, not on the field (DESIGN-BRUTALIST.md §2.2). This widget owns
/// that box; the [TextField] itself is passed straight through as [child] and
/// is never touched, which is what §2.2 requires — no [InputDecoration] and no
/// [TextField] property changes at any call site.
///
/// Three states, and only the border colour moves between rest and focus
/// (§4.5):
///
/// | State | Fill | Border | Shadow |
/// |---|---|---|---|
/// | rest | `paper` | `stone` @ 2 | hard |
/// | focused | `paper` | `SiftBrutal.focus` @ 2 | hard, unchanged |
/// | disabled | `surfaceWarm2` | `stone` @ 2 | none |
///
/// The shadow deliberately does NOT collapse on focus, unlike [BrutalButton]:
/// a button sinks, a field does not. Dropping the shadow on focus would read
/// as a deflated control rather than an engaged one.
class BrutalField extends StatefulWidget {
  /// The box contents — normally a [TextField], or a row of leading icon plus
  /// field for the search bar.
  final Widget child;

  /// Total height INCLUDING the 2pt border, so the 48/52dp pointer targets the
  /// three fixed-height sites already had are not eaten by the decoration.
  /// Null keeps the box intrinsically sized, as the search and tag fields are.
  final double? height;

  /// False paints the disabled row and stops the child receiving pointers, so
  /// the field cannot be typed into. No call site disables a field today; the
  /// state exists because §4.5 specifies it.
  final bool enabled;

  /// The node whose focus drives the ring. Supply it where the field already has
  /// one, so the ring keeps tracking exactly what it tracked before (the search
  /// bar's clear button is a sibling focus target inside the same box and must
  /// NOT light the ring). When null, the box watches which widget holds primary
  /// focus and rings only while its OWN text field holds it — which is how the
  /// three sites with no node of their own gain a focus state they never had,
  /// without adding a node to their [TextField] plumbing (§4.5).
  ///
  /// Pass the [TextField]'s own LEAF node, not a scope. The external path has
  /// the same subtree-wide `FocusNode.hasFocus` limitation the internal path
  /// does — it is correct today only because both call sites hand over a leaf
  /// node, so passing a scope would silently reintroduce the bug this widget
  /// was just fixed for.
  final FocusNode? focusNode;

  const BrutalField({
    super.key,
    required this.child,
    this.height,
    this.enabled = true,
    this.focusNode,
  });

  @override
  State<BrutalField> createState() => _BrutalFieldState();
}

class _BrutalFieldState extends State<BrutalField> {
  /// The caller's own node, or null in the node-less path — there the ring is
  /// driven by [_onFocusMoved] instead, because there is no node to listen to.
  FocusNode? _observed;

  late bool _observesScope;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _bind();
    // The node-less path has no node of its own to listen to, so it watches the
    // one thing that always moves: which widget currently holds primary focus.
    FocusManager.instance.addListener(_onFocusMoved);
  }

  void _bind() {
    _observesScope = widget.focusNode == null;
    _observed?.removeListener(_onNodeFocus);
    _observed = widget.focusNode;
    _observed?.addListener(_onNodeFocus);
    _focused = _sourceHasFocus;
  }

  @override
  void didUpdateWidget(BrutalField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.focusNode, widget.focusNode)) return;
    _bind();
  }

  @override
  void dispose() {
    _observed?.removeListener(_onNodeFocus);
    FocusManager.instance.removeListener(_onFocusMoved);
    super.dispose();
  }

  /// What the ring currently follows: the caller's node where there is one,
  /// otherwise this box's own text input.
  bool get _sourceHasFocus {
    final node = _observed;
    if (!_observesScope) return node?.hasFocus ?? false;
    return _editableHasFocus;
  }

  void _onNodeFocus() => _setFocused(_sourceHasFocus);

  void _onFocusMoved() {
    if (_observesScope) _setFocused(_editableHasFocus);
  }

  /// True while THIS field's own text input holds primary focus.
  ///
  /// A [Focus] scope cannot answer this by itself. `hasFocus` is true for the
  /// entire subtree, so moving focus from the text field to a sibling control
  /// inside the same box never flips it and `onFocusChange` stays silent — the
  /// ring stayed lit for a control that is not the field. Walking up from
  /// primary focus asks the question the ring actually cares about, and stops
  /// at the nearest [BrutalField] so nested boxes cannot answer for each other.
  bool get _editableHasFocus {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.findAncestorWidgetOfExactType<EditableText>() == null) return false;
    return identical(ctx.findAncestorWidgetOfExactType<BrutalField>(), widget);
  }

  void _setFocused(bool value) {
    if (value == _focused) return;
    setState(() => _focused = value);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // A disabled field is not an engaged control, so it never takes the ring.
    final focused = widget.enabled && _focused;

    return Focus(
      // The box is a focus SCOPE, not a focus stop: it is the boundary the
      // traversal walks within, and `canRequestFocus: false` plus
      // `skipTraversal: true` keep it out of that order, so the only focusable
      // thing inside is still the [TextField]. It deliberately carries no
      // `onFocusChange` — see [_editableHasFocus] for why a scope cannot
      // observe the ring.
      canRequestFocus: false,
      skipTraversal: true,
      child: AnimatedContainer(
        // Chat already animated its focus border on MotionTokens.standard, so
        // this is that call site unchanged; the three static sites gain the same
        // short cross-fade, and under reduced motion MotionTokens collapses it
        // to an instant swap rather than the 180ms the search bar hard-coded.
        duration: MotionTokens.standard,
        curve: MotionTokens.easeOutCubic,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.enabled ? s.paper : s.surfaceWarm2,
          borderRadius: BorderRadius.circular(SiftRadii.rControl),
          border: Border.all(
            color: focused ? SiftBrutal.focus(isDark) : s.stone,
            width: SiftBrutal.borderW,
          ),
          boxShadow: widget.enabled ? SiftBrutal.hard(isDark) : SiftBrutal.none,
        ),
        child:
            widget.enabled ? widget.child : IgnorePointer(child: widget.child),
      ),
    );
  }
}
