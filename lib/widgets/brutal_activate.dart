import 'package:flutter/material.dart';

/// Keyboard activation for the hand-rolled brutal controls.
///
/// A [GestureDetector] is enough for a pointer, and it is enough for TalkBack
/// too — it puts `onTap` in the semantics tree and the screen reader's
/// double-tap goes through semantics, not through pointer events. It is
/// completely silent to a keyboard and to switch access.
///
/// Material's buttons work under Enter and Space because `InkResponse.build`
/// wraps its content in
/// `Actions(actions: {ActivateIntent: ..., ButtonActivateIntent: ...})`, and
/// `WidgetsApp` binds Enter / numpadEnter / space to `ActivateIntent`. The key
/// event is then dispatched from the *focused* node's own context upwards, so
/// the action has to be an ancestor of the focus node — with no [Actions] in the
/// subtree, nothing can invoke the intent.
///
/// Without this wrapper a keyboard user tabs to a control, sees the focus ring
/// light, presses Enter or Space, and nothing happens: a WCAG 2.1 SC 2.1.1
/// (Keyboard) and SC 2.4.7 (Focus Visible) failure that is invisible to a
/// screenshot and to any assertion that only checks the ring's colour.
///
/// [onActivate] is the control's own callback. Pass null for a disabled
/// control and the intent resolves to a no-op, so Enter cannot activate
/// something that a pointer cannot press.
Widget brutalActivate({
  required VoidCallback? onActivate,
  required Widget child,
}) {
  // Both entries, because Material's [InkResponse] registers both and a caller
  // coming from Material expects both: [ActivateIntent] is what [WidgetsApp]
  // binds Enter, numpadEnter and space to, and [ButtonActivateIntent] is the
  // semantic-double-tap path switch access uses.
  //
  // The guard lives in the handler and both actions are always registered. A
  // disabled control therefore *swallows* the intent as a no-op instead of
  // letting it bubble to an ancestor, and a null [onActivate] can never be
  // registered as a handler and crash on invocation.
  Object? invoke(Intent intent) {
    onActivate?.call();
    return null;
  }

  // This wraps [child] rather than sitting inside it: the key event is
  // dispatched from the focused node's own context upwards, so an [Actions]
  // below the [Focus] could never be reached.
  return Actions(
    actions: <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: invoke),
      ButtonActivateIntent:
          CallbackAction<ButtonActivateIntent>(onInvoke: invoke),
    },
    child: child,
  );
}
