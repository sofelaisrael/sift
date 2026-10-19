import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the OS classes this device as short on memory.
///
/// The on-device model is a 614 MB bundle that the LiteRT-LM engine reads in
/// full before it emits a token, so on a phone Android classes as low-RAM the
/// transfer succeeds and the first question then fails with the weights still
/// loading — and the load latches, so every later question falls back silently
/// too. Asking before the download is the cheap half of that fix. The latch is
/// the expensive half and is left exactly as it was.
///
/// This is the second half of the model gate and follows the first one, which
/// asks the ABI from `dart:ffi` (`LiteRtLocalChatModel.isSupportedDevice`). It
/// lives beside the model in `lib/services/` rather than in the screen that
/// shows it, because the device question and the sentence that answers it have
/// to come from one place or they will drift.
///
/// Two things this deliberately is not:
///
/// **Not synchronous.** A `MethodChannel` call is an async platform message, so
/// it cannot be answered from a widget `build`. [isLowRam] is the warmed cache
/// and exists for exactly that one caller: the Settings row and dialog read it
/// while building, and neither ever awaits anything to decide what to draw.
/// **Not per question.** The read is made at most once and cached, because a
/// platform message on the chat path would put a channel round trip in front of
/// every local question. A caller that arrives while a read is in flight joins
/// that read rather than sending a second message.
///
/// ## Why it fails open, every time, without exception
///
/// A false positive locks a capable user out of a feature they were just
/// offered. A false negative is today's behaviour: a download that ends in the
/// honest "could not be loaded" the load path already reports. So every failure
/// below lands on the same answer — not low-RAM — and none of them is
/// special-cased:
///
/// * a non-Android host, which cannot answer the question at all;
/// * `MissingPluginException`, meaning no handler is registered on this host and
///   the read was never made;
/// * `PlatformException`, carrying a host error SIFT neither reads nor shows;
/// * a `null`, or a value the codec could not decode as a `bool`, which
///   surfaces as a throw and lands in the same catch;
/// * a value that is not `true`.
///
/// An unregistered channel is the one case with two possible answers — some
/// embedders return `null`, others throw — so both are read as the same "the
/// platform did not answer" and neither is allowed to become a block.
///
/// The cache is written only by a read that came back. A failed read leaves it
/// empty so a later caller can try again, but nothing about the failure is kept:
/// there is no way to hand a widget `build` an "unverified low-RAM", and a
/// guess SIFT cannot retract is worse than no answer at all.
class DeviceMemory {
  const DeviceMemory._();

  /// Android's own question, asked through the host in `MainActivity`. SIFT
  /// never computes a low-RAM verdict of its own.
  static const MethodChannel _channel =
      MethodChannel('screensort_lam/device_memory');

  /// The last answer the platform actually gave, and null until one does.
  /// Null and `false` are kept apart on purpose: null is "never read", and only
  /// a read may replace it, so [isLowRam] can answer before startup has finished.
  static bool? _cached;

  /// The read in flight, or null. Held while the cache is empty, so it doubles
  /// as the "a read is already under way" marker that keeps a second caller
  /// from sending a second message.
  static Future<bool>? _pending;

  /// The cached answer, asked without touching the platform. `false` until a
  /// read has succeeded, which is the same answer a failed read gives — see the
  /// class comment for why that direction is the safe one.
  static bool get isLowRam => _cached ?? false;

  /// Whether the OS says this device is low on memory, reading the platform at
  /// most once and caching whatever it says.
  ///
  /// `true` only when a read succeeded and said so. Never throws, and does not
  /// report how much the answer can be trusted: it cannot, and the copy that
  /// ships alongside it states a consequence rather than a verdict, so nothing
  /// downstream has to reason about where the answer came from.
  static Future<bool> check() {
    final cached = _cached;
    // Warm: the cached value, with no platform message. This is the branch a
    // chat question and a second tap on Download both land in.
    if (cached != null) return Future<bool>.value(cached);

    final pending = _pending;
    if (pending != null) return pending;

    final read = _ask();
    _pending = read;
    return read.whenComplete(() {
      if (identical(_pending, read)) _pending = null;
    });
  }

  /// The one platform message in this file.
  static Future<bool> _ask() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLowRamDevice');
      if (result != null) _cached = result;
    } catch (_) {
      // A missing handler, a host error, or an answer that was not a bool. The
      // plugin's own message can name an Activity or a framework class, and it
      // is not logged — only the fact that there was no answer is.
      debugPrint('Low-RAM device check unavailable');
    }
    // Null until a read succeeds, so a failed read answers false and leaves the
    // cache cold for the next caller.
    return _cached ?? false;
  }

  /// Warms the cache. Called once at startup so the Settings row can draw its
  /// refusal in the frame that builds it, rather than showing a Download action
  /// that the service is about to refuse.
  ///
  /// Deliberately not awaited by anything. Startup must not be able to be
  /// delayed by a device question, and nothing is lost by the cache being warm
  /// late: [check] joins an in-flight read and short-circuits a warm one, so a
  /// Download tap made before the answer arrives waits for the same single
  /// message instead of starting a second one.
  static void warm() {
    unawaited(check());
  }

  /// Forgets the cached answer so a test can present a device that has never
  /// been asked. Only tests call this.
  @visibleForTesting
  static void resetForTest() {
    _cached = null;
    _pending = null;
  }
}
