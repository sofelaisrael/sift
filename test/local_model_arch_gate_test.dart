import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/services/litert_local_chat_model.dart';
import 'package:screensort_lam/services/local_chat_model.dart';
import 'package:screensort_lam/services/local_model_service.dart';

/// A [LocalChatModel] that records what it was asked to do. The arch gate lives
/// in the service, so nothing here may be reached on a device that cannot run
/// the model — that is exactly what these tests assert.
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

/// The only runtime these tests need: a model the manager already holds, plus a
/// load that must never be attempted on a device with no library to read the
/// weights with.
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
      throw StateError('no conversation is opened on a device with no library');

  @override
  Future<void> close() async {}
}

void main() {
  // Google publishes the LiteRT-LM native library for arm64-v8a on Android
  // only. A transfer on x86_64 or 32-bit would fetch 614 MB that can never be
  // loaded, so SIFT refuses it before any byte moves and says why.
  group('the architecture gate', () {
    test('a device that cannot run the model starts no transfer', () async {
      final model = _RecordingModel();
      final service = LocalModelService(model: model, isSupportedDevice: false);

      expect(service.isSupportedDevice, isFalse);
      await service.startDownload();

      expect(model.downloadCalls, 0, reason: 'no request, no bytes');
      expect(service.downloadPercent, isNull);
      expect(service.progress, isNull);
      expect(service.isDownloading, isFalse);
    });

    test('the refusal is reported as an error in fixed copy', () async {
      final model = _RecordingModel();
      final service = LocalModelService(model: model, isSupportedDevice: false);

      await service.startDownload();

      expect(service.status, LocalChatModelStatus.error);
      expect(service.statusMessage, LiteRtLocalChatModel.unsupportedDeviceNote);
      // The real cause, named plainly.
      expect(service.statusMessage, contains('arm64-v8a'));
      // Not the network's fault and not the host's: neither may be blamed.
      final message = service.statusMessage!.toLowerCase();
      expect(message, isNot(contains('http')));
      expect(message, isNot(contains('huggingface')));
      expect(message, isNot(contains('connection')));
      expect(message, isNot(contains('download')));
    });

    test('the copy is shared with the model so the two cannot drift', () {
      expect(
        LiteRtLocalChatModel.unsupportedDeviceNote,
        contains('arm64-v8a'),
      );
      // A reason exists for it, so the load path below reports the same sentence
      // instead of inventing a second one.
      expect(
        LiteRtFailure.values,
        contains(LiteRtFailure.unsupportedArchitecture),
      );
    });

    test('a model on a device that cannot run it names the true cause',
        () async {
      // SIFT's own setup action refuses this device, so a bundle can only be
      // here by another route — a sideloaded file, a restored backup. The setup
      // check does not cover that, so the load path is what has to say why.
      final gateway = _InstalledGateway();
      final model = LiteRtLocalChatModel(
        gateway: gateway,
        isSupportedDevice: false,
      );

      expect(await model.ensureLoaded(), isFalse);

      // No attempt: there is no library here to read the weights with, and a
      // failed attempt would only report a generic load failure.
      expect(gateway.loadCalls, 0);
      expect(model.status, LocalChatModelStatus.error);
      expect(model.statusMessage, LiteRtLocalChatModel.unsupportedDeviceNote);
      // The same fixed copy the gate uses: no exception text, no architecture
      // string the runtime made up, no blame on the host.
      final message = (model.statusMessage ?? '').toLowerCase();
      expect(message, isNot(contains('dlopen')));
      expect(message, isNot(contains('liblitert')));
      expect(message, isNot(contains('http')));
    });

    test('a device that can run the model is not blocked', () async {
      final model = _RecordingModel();
      final service = LocalModelService(model: model, isSupportedDevice: true);

      await service.startDownload();

      expect(model.downloadCalls, 1);
      expect(service.installed, isTrue);
    });

    test('detection cannot throw and fails open off Android', () {
      // This host is not Android, so the check must answer without touching the
      // runtime and without throwing: a real device is never wrongly blocked.
      expect(LiteRtLocalChatModel.isSupportedDevice, isTrue);
    });
  });

  group('the UI cannot offer a transfer on such a device', () {
    test('the explanation is shown before the download action exists',
        () async {
      final source =
          await File('lib/screens/settings_screen.dart').readAsString();
      // The row's own subtitle leads with the requirement, and the dialog
      // returns before the branch that starts a transfer.
      expect(source, contains('service.unsupportedDeviceNote'));
      final gate = source.indexOf('if (!service.isSupportedDevice) {');
      expect(gate, greaterThan(-1));
      final download = source.indexOf('service.startDownload()');
      expect(download, greaterThan(gate));
    });

    test('the build is not pinned to one ABI', () async {
      final raw = await File('android/app/build.gradle.kts').readAsString();
      // The comment has to name arm64-v8a to explain why the filter is gone, so
      // prose is not what is asserted here. What must be absent is the
      // executable restriction, which is the only thing that stops an x86_64
      // emulator or a 32-bit device from installing the app at all.
      final code = raw
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('abiFilters')));
      expect(code, isNot(contains('ndk {')));
      expect(code, isNot(contains('arm64-v8a')));
    });
  });
}
