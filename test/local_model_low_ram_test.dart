import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/services/device_memory.dart';
import 'package:screensort_lam/services/litert_local_chat_model.dart';
import 'package:screensort_lam/services/local_chat_model.dart';
import 'package:screensort_lam/services/local_model_service.dart';
import 'package:screensort_lam/theme/app_theme.dart';

import 'wcag_contrast.dart';

/// The same channel [DeviceMemory] opens, rebuilt here so the production
/// surface stays private. `setMockMethodCallHandler` keys on the channel *name*,
/// so this intercepts the real message rather than a copy of it.
const MethodChannel _channel = MethodChannel('screensort_lam/device_memory');

/// Records what the platform was asked and can be told what to answer.
///
/// [answer] is async because that is the shape a mock method-call handler has:
/// returning a `Future` is what lets a test hold a read open and observe a
/// second caller joining it.
///
/// Nothing asserts inside [answer]. [DeviceMemory] catches everything the
/// channel can raise in order to fail open, and a failing `expect` is just
/// another thing that gets caught — so an assertion written in there fails
/// silently as "the platform did not answer". The calls are recorded and checked
/// outside instead.
class _Host {
  final List<MethodCall> received = [];

  int get calls => received.length;

  Future<Object?> Function(MethodCall call)? answer;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
      received.add(call);
      return answer?.call(call);
    });
  }
}

/// The one message SIFT is allowed to send. Asserted field by field rather than
/// as a whole [MethodCall], because the value the test boundary decodes is not
/// the value `==` was given.
const String _method = 'isLowRamDevice';

/// A [LocalChatModel] that records what it was asked to do. The device gates
/// live in the service, so nothing here may be reached on a device that cannot
/// run the model — that is exactly what these tests assert.
class _RecordingModel implements LocalChatModel {
  @override
  LocalChatModelStatus status = LocalChatModelStatus.notInstalled;

  @override
  String? statusMessage;

  int downloadCalls = 0;
  int removeCalls = 0;
  bool _onDisk = false;

  @override
  bool get isUsable => status == LocalChatModelStatus.ready;

  @override
  Future<bool> isInstalled() async => _onDisk;

  @override
  Future<void> download({
    void Function(LocalChatDownloadProgress value)? onProgress,
    LocalChatCancellation? cancellation,
  }) async {
    downloadCalls++;
    onProgress?.call(LocalChatDownloadProgress(100));
    _onDisk = true;
    status = LocalChatModelStatus.installed;
  }

  @override
  Future<bool> ensureLoaded() async => false;

  @override
  Future<String> generate({
    required String prompt,
    required String context,
    int maxTokens = 256,
  }) async =>
      '';

  @override
  Future<LocalModelRemoval> remove() async {
    removeCalls++;
    _onDisk = false;
    status = LocalChatModelStatus.notInstalled;
    return LocalModelRemoval.removed;
  }

  @override
  Future<void> dispose() async {}
}

/// The only runtime the load-path tests need: a model the manager already holds,
/// plus a load that must never be attempted on a device that cannot hold the
/// weights.
class _InstalledGateway implements LiteRtGateway {
  int loadCalls = 0;

  @override
  Future<bool> isInstalled(String modelFileName) async => true;

  @override
  Future<void> load({
    required int contextTokens,
    required PreferredBackend backend,
  }) async {
    loadCalls++;
  }

  @override
  Future<void> install({
    required String modelId,
    required String url,
    required void Function(int percent) onProgress,
    required LocalChatCancellation cancellation,
  }) async {}

  @override
  Future<void> uninstall(String modelFileName) async {}

  @override
  Future<void> clearActiveIdentity() async {}

  @override
  Future<LiteRtSession> openChat({
    required int maxOutputTokens,
    required String systemInstruction,
  }) async =>
      throw StateError('no conversation is opened on a device with no memory');

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Host host;

  setUp(() {
    host = _Host();
    host.install();
    // The answer is cached in a static, so each test presents a device that has
    // never been asked. Without this a previous test's `true` would decide the
    // next one.
    DeviceMemory.resetForTest();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    DeviceMemory.resetForTest();
  });

  group('the low-memory check asks the platform', () {
    test('a device the OS calls low-RAM answers true', () async {
      host.answer = (_) async => true;

      expect(await DeviceMemory.check(), isTrue);
      // Observable from synchronous code afterwards, which is what the Settings
      // row reads while it builds.
      expect(DeviceMemory.isLowRam, isTrue);
      // The exact message SIFT sent, checked out here rather than inside the
      // handler — see [_Host].
      expect(host.received, hasLength(1));
      expect(host.received.single.method, _method);
      expect(host.received.single.arguments, isNull);
    });

    test('a device the OS does not call low-RAM answers false', () async {
      host.answer = (_) async => false;

      expect(await DeviceMemory.check(), isFalse);
      expect(DeviceMemory.isLowRam, isFalse);
    });

    test('the method name is the one MainActivity answers', () async {
      // The two ends of the channel are separate files that no compiler checks
      // against each other, so the one thing that can tie them together is an
      // assertion that the string crossed the boundary.
      final activity = await File(
        'android/app/src/main/kotlin/com/screensort/screensort_lam/MainActivity.kt',
      ).readAsString();

      host.answer = (_) async => false;
      await DeviceMemory.check();

      expect(host.received.single.method, _method);
      expect(activity, contains('"$_method"'));
      expect(activity, contains('screensort_lam/device_memory'));
      // The framework call itself, so a rewrite that guessed at the verdict
      // instead of asking Android cannot pass.
      expect(activity, contains('ActivityManager'));
      expect(activity, contains('isLowRamDevice'));
    });
  });

  group('it fails open, every time', () {
    test('a thrown platform exception is not low-RAM', () async {
      host.answer =
          (_) async => throw PlatformException(code: 'ERR', message: 'x');

      expect(await DeviceMemory.check(), isFalse);
      // Nothing was cached, so a widget build cannot be handed a block from a
      // read that failed.
      expect(DeviceMemory.isLowRam, isFalse);
    });

    test('a missing plugin is not low-RAM', () async {
      host.answer = (_) async => throw MissingPluginException(
            'no implementation found for $_method',
          );

      expect(await DeviceMemory.check(), isFalse);
      expect(DeviceMemory.isLowRam, isFalse);
    });

    test('a null answer is not low-RAM', () async {
      // The case an unregistered channel takes on an embedder that returns
      // rather than throws. It must reach the same answer as the throw above.
      host.answer = (_) async => null;

      expect(await DeviceMemory.check(), isFalse);
      expect(DeviceMemory.isLowRam, isFalse);
    });

    test('an answer that is not a bool is not low-RAM', () async {
      host.answer = (_) async => 'true';

      expect(await DeviceMemory.check(), isFalse);
      expect(DeviceMemory.isLowRam, isFalse);
    });

    test('no handler at all is not low-RAM', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);

      expect(await DeviceMemory.check(), isFalse);
      expect(DeviceMemory.isLowRam, isFalse);
    });

    test('a failed read is retried, not remembered as false', () async {
      host.answer = (_) async => throw PlatformException(code: 'ERR');
      expect(await DeviceMemory.check(), isFalse);

      // The platform recovers. A cache poisoned with the first failure would
      // keep this phone's one chance to be classified correctly forever.
      host.answer = (_) async => true;
      expect(await DeviceMemory.check(), isTrue);
      expect(host.calls, 2);
    });
  });

  group('it is not asked on every call', () {
    test('a successful answer is cached', () async {
      host.answer = (_) async => true;

      for (var i = 0; i < 5; i++) {
        expect(await DeviceMemory.check(), isTrue);
      }

      // One message for five callers. A platform round trip on the chat path
      // would put a channel call in front of every local question.
      expect(host.calls, 1);
    });

    test('a false answer is cached just as firmly', () async {
      host.answer = (_) async => false;

      for (var i = 0; i < 5; i++) {
        expect(await DeviceMemory.check(), isFalse);
      }

      expect(host.calls, 1);
    });

    test('callers arriving together share one message', () async {
      final gate = Completer<Object?>();
      host.answer = (_) => gate.future;

      final first = DeviceMemory.check();
      final second = DeviceMemory.check();
      // Both are waiting on the same read, which has not answered yet.
      expect(host.calls, 1);

      gate.complete(true);
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(host.calls, 1);
    });

    test('warming is fire and forget, and warms the same cache', () async {
      host.answer = (_) async => true;

      DeviceMemory.warm();
      // Nothing is awaited by the caller, so the answer may not have landed on
      // this line — which is the point: startup cannot be blocked by it.
      await Future<void>.delayed(Duration.zero);

      expect(await DeviceMemory.check(), isTrue);
      expect(host.calls, 1, reason: 'the warm and the check are one read');
    });
  });

  group('the setup action refuses before any request', () {
    test('a low-RAM device starts no transfer', () async {
      final model = _RecordingModel();
      final service = LocalModelService(
        model: model,
        isSupportedDevice: true,
        isLowRamDevice: true,
      );

      await service.startDownload();

      expect(model.downloadCalls, 0, reason: 'no request, no bytes');
      expect(service.downloadPercent, isNull);
      expect(service.progress, isNull);
      expect(service.isDownloading, isFalse);
      expect(service.installed, isFalse);
    });

    test('a cold cache still refuses when the platform says low-RAM', () async {
      // The constructor argument is not what makes this device low-RAM; the
      // platform is. This is the test that would fail if the service trusted its
      // own cached field instead of asking before 614 MB moves.
      host.answer = (_) async => true;
      final model = _RecordingModel();
      final service = LocalModelService(
        model: model,
        isSupportedDevice: true,
        isLowRamDevice: false,
      );

      await service.startDownload();

      expect(model.downloadCalls, 0);
      expect(host.calls, 1,
          reason: 'the setup action must consult the platform');
      expect(service.statusMessage, LiteRtLocalChatModel.lowRamDeviceNote);
    });

    test('the refusal is this reason\'s copy, not the architecture one',
        () async {
      final model = _RecordingModel();
      final service = LocalModelService(
        model: model,
        isSupportedDevice: true,
        isLowRamDevice: true,
      );

      await service.startDownload();

      expect(service.status, LocalChatModelStatus.error);
      expect(service.statusMessage, LiteRtLocalChatModel.lowRamDeviceNote);
      expect(
        service.statusMessage,
        isNot(LiteRtLocalChatModel.unsupportedDeviceNote),
        reason: 'two different causes, two different sentences',
      );
      expect(service.statusMessage, contains('memory'));
    });

    test('the copy names the consequence and blames nothing else', () async {
      final model = _RecordingModel();
      final service = LocalModelService(
        model: model,
        isSupportedDevice: true,
        isLowRamDevice: true,
      );

      await service.startDownload();
      final message = service.statusMessage!.toLowerCase();

      // The network, the host, and the transfer are all innocent here, and the
      // sentence must not send the user to fix any of them.
      expect(message, isNot(contains('connection')));
      expect(message, isNot(contains('download')));
      expect(message, isNot(contains('http')));
      expect(message, isNot(contains('huggingface')));
      expect(message, isNot(contains('bandwidth')));
      // And no platform jargon or exception text: a user cannot act on any of it.
      expect(message, isNot(contains('activitymanager')));
      expect(message, isNot(contains('lowram')));
      expect(message, isNot(contains('exception')));
    });

    test('the copy is shared with the model so the two cannot drift', () {
      expect(LiteRtLocalChatModel.lowRamDeviceNote, contains('memory'));
      expect(
        LiteRtFailure.values,
        contains(LiteRtFailure.insufficientMemory),
      );
      expect(LiteRtLocalChatModel.lowRamDeviceNote,
          isNot(LiteRtLocalChatModel.unsupportedDeviceNote));
    });
  });

  group('a device that can run the model is not blocked', () {
    test('a normal device downloads exactly as before', () async {
      host.answer = (_) async => false;
      final model = _RecordingModel();
      final service = LocalModelService(
        model: model,
        isSupportedDevice: true,
        isLowRamDevice: false,
      );

      await service.startDownload();

      expect(model.downloadCalls, 1);
      expect(service.installed, isTrue);
      expect(service.status, LocalChatModelStatus.installed);
      expect(service.statusMessage, isNull);
    });

    test('an unanswered check proceeds, because it fails open', () async {
      host.answer = (_) async => throw PlatformException(code: 'ERR');
      final model = _RecordingModel();
      final service = LocalModelService(
        model: model,
        isSupportedDevice: true,
        isLowRamDevice: false,
      );

      await service.startDownload();

      // The whole contract of failing open, from the caller's side: SIFT cannot
      // tell, so it does exactly what it did before this check existed, rather
      // than refusing a phone that may be perfectly capable.
      expect(model.downloadCalls, 1);
      expect(service.installed, isTrue);
    });

    test('the architecture gate is still decided first and still refuses',
        () async {
      // Both gates refuse; the one that already existed must not have been
      // reordered behind the new one or made conditional on it.
      host.answer = (_) async => true;
      final model = _RecordingModel();
      final service = LocalModelService(
        model: model,
        isSupportedDevice: false,
        isLowRamDevice: false,
      );

      await service.startDownload();

      expect(model.downloadCalls, 0);
      expect(host.calls, 0,
          reason: 'no reason to ask a question it cannot change');
      expect(
        service.statusMessage,
        LiteRtLocalChatModel.unsupportedDeviceNote,
      );
    });
  });

  group('a model already on a low-RAM device names the true cause', () {
    test('the weights are not read and the reason is the memory one', () async {
      // SIFT's own setup action refuses this device, so a bundle can only be
      // here by another route — a sideloaded file, a restored backup. The setup
      // check does not cover that, so the load path is what has to say why.
      final gateway = _InstalledGateway();
      final model = LiteRtLocalChatModel(
        gateway: gateway,
        isSupportedDevice: true,
        isLowRamDevice: true,
      );

      expect(await model.ensureLoaded(), isFalse);

      // No attempt: reading 614 MB into a phone the OS classes as low on
      // memory is the failure being avoided, and a failed attempt would only
      // report the vague "could not be loaded".
      expect(gateway.loadCalls, 0);
      expect(model.status, LocalChatModelStatus.error);
      expect(model.statusMessage, LiteRtLocalChatModel.lowRamDeviceNote);
      expect(model.statusMessage,
          isNot(contains('lowRamDevice'))); // no enum or field name leaked
    });

    test('a capable device with the model on disk still loads', () async {
      final gateway = _InstalledGateway();
      final model = LiteRtLocalChatModel(
        gateway: gateway,
        isSupportedDevice: true,
        isLowRamDevice: false,
      );

      expect(await model.ensureLoaded(), isTrue);
      expect(gateway.loadCalls, 1);
      expect(model.status, LocalChatModelStatus.ready);
    });
  });

  group('the UI cannot offer a transfer on such a device', () {
    test('both the subtitle and the dialog refuse before the download exists',
        () async {
      final source =
          await File('lib/screens/settings_screen.dart').readAsString();

      expect(source, contains('service.lowRamDeviceNote'));

      // The row leads with the refusal, ahead of every state that would promise
      // a setup.
      final subtitle = source.indexOf('if (service.isLowRamDevice) {');
      expect(subtitle, greaterThan(-1));
      expect(
        subtitle,
        lessThan(source.indexOf("case LocalChatModelStatus.downloading:")),
      );

      // The tap opens a dialog with no Download action and returns.
      final tap = source.indexOf('Future<void> _onLocalModelTap');
      expect(tap, greaterThan(-1));
      final body = source.substring(tap, source.indexOf('\n  }', tap));
      final gate = body.indexOf('if (service.isLowRamDevice) {');
      expect(gate, greaterThan(-1));
      expect(body.indexOf('service.startDownload()'), greaterThan(gate));
      // The arch gate still comes first in the same handler.
      expect(
        body.indexOf('if (!service.isSupportedDevice) {'),
        lessThan(gate),
      );
    });

    test('the copy it renders clears 4.5:1 on both surfaces', () {
      // Two surfaces render this sentence and they are not the same colour: the
      // row's subtitle sits on the scaffold (`canvas`) in `graphite`, and the
      // dialog's content text is `graphite` on the dialog's own `paper`. Both
      // are read off the built theme rather than restated, so a palette change
      // cannot leave this passing against a colour nothing paints on.
      const floor = 4.5;

      for (final theme in {
        Brightness.light: AppTheme.lightTheme,
        Brightness.dark: AppTheme.darkTheme,
      }.entries) {
        final colors = theme.value.extension<SiftColors>()!;
        final dialog = theme.value.dialogTheme;

        final onCanvas = wcagContrast(colors.graphite, colors.canvas);
        final onPaper = wcagContrast(
          dialog.contentTextStyle!.color!,
          dialog.backgroundColor!,
        );

        expect(
          onCanvas,
          greaterThanOrEqualTo(floor),
          reason:
              'Settings row subtitle, ${theme.key}: ${onCanvas.toStringAsFixed(2)}:1',
        );
        expect(
          onPaper,
          greaterThanOrEqualTo(floor),
          reason:
              'dialog content, ${theme.key}: ${onPaper.toStringAsFixed(2)}:1',
        );
        // The dialog really is the surface the note is shown on, so this is the
        // pair that matters and not a hypothetical one.
        expect(dialog.contentTextStyle!.color, colors.graphite);
      }
    });
  });
}
