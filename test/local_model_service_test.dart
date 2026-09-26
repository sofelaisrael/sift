import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/services/litert_local_chat_model.dart';
import 'package:screensort_lam/services/local_chat_model.dart';
import 'package:screensort_lam/services/local_model_service.dart';
import 'package:screensort_lam/services/local_model_spec.dart';

/// A stand-in for the LiteRT-LM runtime. Records every call so a test can
/// assert the model never reaches the network unless someone asked, and can be
/// driven into any outcome: a refused host, a mid-transfer failure, a cancel, a
/// model that will not load.
///
/// Nothing here touches the native LiteRT library, an Android SDK, or a real
/// model: `install` is a scripted sequence of progress ticks.
class FakeLiteRtGateway implements LiteRtGateway {
  FakeLiteRtGateway({
    this.installed = false,
    this.progressTicks = const [0, 50, 100],
    this.installDelay = Duration.zero,
    this.installError,
    this.failureOnCancel,
    this.loadError,
    this.uninstallError,
  });

  /// Whether the runtime's model manager already holds the model.
  bool installed;

  /// Progress ticks `install` reports, in order. Defaults to a short transfer
  /// that completes.
  List<int> progressTicks;

  /// Delay each `install` waits before finishing, so a cancel can land
  /// mid-transfer.
  Duration installDelay;

  /// Thrown by `install` instead of completing, when set.
  Object? installError;

  /// Thrown by `install` when a cancel landed mid-transfer, instead of the
  /// cancel exception. This is the runtime's other cancel path: the transfer is
  /// cut and the failure reaches SIFT as a typed download error or a raw plugin
  /// exception, so the token is the only way to tell it from a real failure.
  Object? failureOnCancel;

  /// Thrown by `load`, when set.
  Object? loadError;

  /// Thrown by `uninstall`, when set.
  Object? uninstallError;

  final List<String> calls = [];
  final List<int> progress = [];
  final List<String> installUrls = [];
  final List<int> contextTokens = [];
  final List<int> maxOutputTokens = [];
  final List<String> systemInstructions = [];
  final List<String> prompts = [];

  /// The exact string each `isInstalled` was asked about. The runtime keys its
  /// model store on the file name, so a bare model id here is a silent miss
  /// rather than an error — recording the argument is the only way to catch it.
  final List<String> isInstalledArgs = [];

  /// The exact string each `uninstall` was asked about, for the same reason as
  /// [isInstalledArgs]: a wrong key leaves the file on disk while the UI claims
  /// it was removed.
  final List<String> uninstallArgs = [];
  int installCalls = 0;
  int loadCalls = 0;
  int closeCalls = 0;
  int openSessionCalls = 0;
  int uninstallCalls = 0;
  int clearIdentityCalls = 0;
  int disposeCalls = 0;
  bool cancelled = false;

  @override
  Future<bool> isInstalled(String modelFileName) async {
    calls.add('isInstalled');
    isInstalledArgs.add(modelFileName);
    return installed;
  }

  @override
  Future<void> install({
    required String modelId,
    required String url,
    required void Function(int percent) onProgress,
    required LocalChatCancellation cancellation,
  }) async {
    installCalls++;
    installUrls.add(url);
    cancellation.attach(() => cancelled = true);
    for (final percent in progressTicks) {
      if (cancellation.isCancelled) break;
      onProgress(percent);
      await Future<void>.delayed(Duration.zero);
    }
    if (installDelay > Duration.zero) {
      await Future<void>.delayed(installDelay);
    }
    if (cancellation.isCancelled) {
      final cancelFailure = failureOnCancel;
      if (cancelFailure != null) throw cancelFailure;
      throw const LiteRtInstallCancelled();
    }
    final error = installError;
    if (error != null) throw error;
    installed = true;
  }

  @override
  Future<void> uninstall(String modelFileName) async {
    uninstallCalls++;
    uninstallArgs.add(modelFileName);
    final error = uninstallError;
    if (error != null) throw error;
    installed = false;
  }

  @override
  Future<void> clearActiveIdentity() async {
    clearIdentityCalls++;
  }

  @override
  Future<void> load({
    required int contextTokens,
    required PreferredBackend backend,
  }) async {
    loadCalls++;
    this.contextTokens.add(contextTokens);
    final error = loadError;
    if (error != null) throw error;
  }

  @override
  Future<LiteRtSession> openChat({
    required int maxOutputTokens,
    required String systemInstruction,
  }) async {
    openSessionCalls++;
    this.maxOutputTokens.add(maxOutputTokens);
    systemInstructions.add(systemInstruction);
    final gateway = this;
    return _FakeSession(
      answer: 'Your BA123 to Lisbon is on 12 March.',
      onAsk: gateway.prompts.add,
    );
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

class _FakeSession implements LiteRtSession {
  _FakeSession({required this.answer, required this.onAsk});

  final String answer;
  final void Function(String) onAsk;
  int closeCalls = 0;

  @override
  Future<String> ask(String userText) async {
    onAsk(userText);
    return answer;
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

/// A pure [LocalChatModel] fake, for the manager tests that must not know
/// anything about LiteRT. It also records what the engine asked it, so a test
/// can prove a local-only question never triggered a download.
class FakeLocalChatModel implements LocalChatModel {
  FakeLocalChatModel({
    this.status = LocalChatModelStatus.notInstalled,
    this.statusMessage,
  });

  @override
  LocalChatModelStatus status;
  @override
  String? statusMessage;

  int installCalls = 0;
  int loadCalls = 0;
  int removeCalls = 0;
  bool disposed = false;
  bool removeSucceeds = true;

  final List<int> progress = [];
  List<int> progressTicks = const [25, 100];
  bool installedOnDisk = false;
  int cancelAfterTicks = -1;
  int failAfterTicks = -1;

  @override
  bool get isUsable => status == LocalChatModelStatus.ready;

  @override
  Future<bool> isInstalled() async {
    installedOnDisk = true;
    return status != LocalChatModelStatus.notInstalled;
  }

  @override
  Future<void> download({
    void Function(LocalChatDownloadProgress value)? onProgress,
    LocalChatCancellation? cancellation,
  }) async {
    installCalls++;
    status = LocalChatModelStatus.downloading;
    for (var i = 0; i < progressTicks.length; i++) {
      if (cancellation?.isCancelled ?? false) {
        status = LocalChatModelStatus.notInstalled;
        return;
      }
      onProgress?.call(LocalChatDownloadProgress(progressTicks[i]));
      progress.add(progressTicks[i]);
      if (failAfterTicks == i) {
        status = LocalChatModelStatus.error;
        statusMessage = 'The model could not be downloaded.';
        return;
      }
      if (cancelAfterTicks == i) cancellation?.cancel();
    }
    status = LocalChatModelStatus.installed;
    installedOnDisk = true;
  }

  @override
  Future<bool> ensureLoaded() async {
    loadCalls++;
    return status == LocalChatModelStatus.ready;
  }

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
    if (!removeSucceeds) {
      status = LocalChatModelStatus.error;
      statusMessage = 'The model could not be removed from this device.';
      return LocalModelRemoval.failed;
    }
    status = LocalChatModelStatus.notInstalled;
    return LocalModelRemoval.removed;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  group('model spec', () {
    test('the source is one fixed HTTPS URL on the official LiteRT repo', () {
      final uri = Uri.parse(LocalModelSpec.downloadUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, 'huggingface.co');
      expect(
        uri.path,
        '/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
      );
      // No query string: nothing can ride along in a log line or a request the
      // runtime would otherwise echo.
      expect(uri.hasQuery, isFalse);
      expect(uri.fragment, isEmpty);
    });

    test('the expected identity, file name, and license are pinned', () {
      expect(LocalModelSpec.modelId, 'Qwen3-0.6B');
      expect(LocalModelSpec.fileName, 'Qwen3-0.6B.litertlm');
      expect(LocalModelSpec.fileName, endsWith(LocalModelSpec.fileExtension));
      expect(LocalModelSpec.licenseNote, contains('Qwen3'));
      expect(LocalModelSpec.licenseNote, contains('Apache-2.0'));
      expect(LocalModelSpec.licenseNote, contains('on this device'));
      expect(LocalModelSpec.runtimeName, 'LiteRT-LM');
    });

    test('the model is a LiteRT-LM bundle, not a GGUF', () {
      expect(LocalModelSpec.fileExtension, '.litertlm');
      expect(LocalModelSpec.fileName, isNot(endsWith('.gguf')));
    });

    test('the size ceiling leaves headroom above the real file', () {
      expect(LocalModelSpec.expectedBytes, 614236160);
      expect(
          LocalModelSpec.maxBytes, greaterThan(LocalModelSpec.expectedBytes));
      expect(LocalModelSpec.approxSizeLabel, 'about 614 MB');
    });
  });

  group('nothing happens without an explicit setup action', () {
    test('constructing the model makes no call to the runtime', () {
      final gateway = FakeLiteRtGateway();
      LiteRtLocalChatModel(gateway: gateway);
      expect(gateway.calls, isEmpty);
      expect(gateway.installCalls, 0);
      expect(gateway.loadCalls, 0);
    });

    test('an absent model is reported absent without any request', () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);

      expect(await model.isInstalled(), isFalse);
      expect(model.status, LocalChatModelStatus.notInstalled);
      expect(model.isUsable, isFalse);
      expect(gateway.installCalls, 0);
    });

    test('a question with no model on disk never starts a transfer', () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);

      expect(await model.ensureLoaded(), isFalse);
      expect(gateway.installCalls, 0);
      expect(gateway.loadCalls, 0);
      expect(model.status, LocalChatModelStatus.notInstalled);
    });

    test('refreshing the manager reads metadata and starts nothing', () async {
      final model = FakeLocalChatModel();
      final service = LocalModelService(model: model);

      await service.refresh();

      expect(model.installedOnDisk, isTrue, reason: 'a local read happened');
      expect(model.installCalls, 0);
      expect(service.installed, isFalse);
      expect(service.status, LocalChatModelStatus.notInstalled);
    });
  });

  group('explicit install', () {
    test('the transfer reports progress and ends on disk but not loaded',
        () async {
      final gateway = FakeLiteRtGateway(
        progressTicks: const [0, 25, 50, 75, 100],
      );
      final model = LiteRtLocalChatModel(gateway: gateway);
      final seen = <int>[];

      await model.download(
        onProgress: (value) => seen.add(value.percent),
      );

      expect(gateway.installUrls, [LocalModelSpec.downloadUrl]);
      expect(seen, [0, 25, 50, 75, 100]);
      // Installed is not ready: nothing can answer until the engine is created.
      expect(model.status, LocalChatModelStatus.installed);
      expect(model.statusMessage, isNull);
      expect(model.isUsable, isFalse);
      expect(gateway.loadCalls, 0, reason: 'no weights read on install');
    });

    test('an existing model is never re-fetched', () async {
      final gateway = FakeLiteRtGateway(installed: true);
      final model = LiteRtLocalChatModel(gateway: gateway);

      await model.download();
      await model.download();

      expect(gateway.installCalls, 0);
      expect(model.status, LocalChatModelStatus.installed);
    });

    test('a concurrent second setup action joins the running transfer',
        () async {
      final gateway = FakeLiteRtGateway(
        progressTicks: const [10, 20, 30],
        installDelay: const Duration(milliseconds: 20),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);

      await Future.wait([model.download(), model.download()]);

      expect(gateway.installCalls, 1);
      expect(model.status, LocalChatModelStatus.installed);
    });

    test('the manager mirrors progress and clears it when the transfer ends',
        () async {
      final gateway = FakeLiteRtGateway(
        progressTicks: const [25, 50, 100],
      );
      final service = LocalModelService(
        model: LiteRtLocalChatModel(gateway: gateway),
      );
      final percents = <int>[];
      service.addListener(() {
        final percent = service.downloadPercent;
        if (percent != null) percents.add(percent);
      });

      await service.startDownload();

      expect(percents, containsAllInOrder([25, 50]));
      expect(percents, contains(100));
      expect(service.progress, isNull,
          reason: 'cleared once the transfer ends');
      expect(service.downloadFraction, isNull);
      expect(service.installed, isTrue);
      expect(service.isDownloading, isFalse);
    });
  });

  group('install failures and cancellation', () {
    test('a refused host leaves nothing on disk and shows fixed copy',
        () async {
      final gateway = FakeLiteRtGateway(
        installError: const LiteRtOperationFailed(LiteRtFailure.hostRefused),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);

      await model.download();

      expect(gateway.installed, isFalse);
      expect(model.status, LocalChatModelStatus.error);
      final message = model.statusMessage ?? '';
      expect(message, isNotEmpty);
      // Nothing from the transport may reach the user: no host, no scheme, no
      // status code.
      expect(message, isNot(contains('http')));
      expect(message, isNot(contains('huggingface')));
      expect(message, isNot(contains('404')));
    });

    test('a raw plugin exception is never surfaced or echoed', () async {
      final gateway = FakeLiteRtGateway(
        installError: StateError(
          'dlopen failed: /data/user/0/com.example/files/Qwen3-0.6B.litertlm',
        ),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);

      await model.download();

      expect(model.status, LocalChatModelStatus.error);
      final message = model.statusMessage ?? '';
      expect(message, isNot(contains('dlopen')));
      expect(message, isNot(contains('/data/user')));
      expect(message, isNot(contains('.litertlm')));
    });

    test('a busy host is reported as busy, not as a bad connection', () async {
      final gateway = FakeLiteRtGateway(
        installError: const LiteRtOperationFailed(LiteRtFailure.hostBusy),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);

      await model.download();

      expect(model.status, LocalChatModelStatus.error);
      expect(model.statusMessage, contains('busy'));
    });

    test('a transfer the runtime completed but did not save is a failure',
        () async {
      // The gateway's `install` returns without ever registering the model, so
      // a manager that no longer holds it means the save did not stick.
      final gateway = _GatewayThatInstallsNothing(FakeLiteRtGateway());
      final model = LiteRtLocalChatModel(gateway: gateway);

      await model.download();

      expect(gateway.installCalls, 1);
      expect(model.status, LocalChatModelStatus.error);
      expect(model.statusMessage, contains('not saved'));
    });

    test('a cancel is not an error and leaves nothing installed', () async {
      final gateway = FakeLiteRtGateway(
        progressTicks: const [10, 20, 30, 40, 50],
        installDelay: const Duration(milliseconds: 20),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);
      final cancellation = LocalChatCancellation();

      await model.download(
        onProgress: (value) {
          if (value.percent == 20) cancellation.cancel();
        },
        cancellation: cancellation,
      );

      expect(gateway.cancelled, isTrue,
          reason: 'the cancel reached the runtime');
      expect(gateway.installed, isFalse);
      expect(model.status, LocalChatModelStatus.notInstalled);
      expect(model.statusMessage, isNull);
    });

    test('a cancel that lands before the transfer never starts it', () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      final cancellation = LocalChatCancellation()..cancel();

      await model.download(cancellation: cancellation);

      expect(gateway.installCalls, 0);
      expect(model.status, LocalChatModelStatus.notInstalled);
    });

    test('a cancel the runtime reports as a connection error is still a cancel',
        () async {
      // `DownloadError.canceled()` is a member of the same sealed type the
      // network failure is, so the gateway can only map it to `connection`. The
      // token is what tells the model the user stopped the transfer, and it has
      // to be asked before that copy is shown.
      final gateway = FakeLiteRtGateway(
        progressTicks: const [10, 20, 30, 40],
        installDelay: const Duration(milliseconds: 20),
        failureOnCancel: const LiteRtOperationFailed(LiteRtFailure.connection),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);
      final cancellation = LocalChatCancellation();

      await model.download(
        onProgress: (value) {
          if (value.percent == 20) cancellation.cancel();
        },
        cancellation: cancellation,
      );

      expect(model.status, LocalChatModelStatus.notInstalled);
      expect(model.statusMessage, isNull);
      expect(gateway.installed, isFalse);
    });

    test('a cancel the runtime reports as a raw error is still a cancel',
        () async {
      final gateway = FakeLiteRtGateway(
        progressTicks: const [10, 20, 30, 40],
        installDelay: const Duration(milliseconds: 20),
        failureOnCancel: StateError(
          'dlopen failed: /data/user/0/com.example/files/Qwen3-0.6B.litertlm',
        ),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);
      final cancellation = LocalChatCancellation();

      await model.download(
        onProgress: (value) {
          if (value.percent == 20) cancellation.cancel();
        },
        cancellation: cancellation,
      );

      expect(model.status, LocalChatModelStatus.notInstalled);
      expect(model.statusMessage, isNull);
    });

    test('a failure with no cancel behind it still names a real cause',
        () async {
      // The counterpart to the two above: the same mapping must not swallow a
      // genuine failure just because the check exists.
      final gateway = FakeLiteRtGateway(
        installError: const LiteRtOperationFailed(LiteRtFailure.connection),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);

      await model.download();

      expect(model.status, LocalChatModelStatus.error);
      expect(model.statusMessage, contains('connection'));
    });

    test('the manager exposes a cancellation that reaches the transfer',
        () async {
      final gateway = FakeLiteRtGateway(
        progressTicks: const [10, 20, 30, 40, 50, 60, 70, 80],
        installDelay: const Duration(milliseconds: 20),
      );
      final service = LocalModelService(
        model: LiteRtLocalChatModel(gateway: gateway),
      );
      // Wait for a tick the runtime actually reported. The manager seeds 0% so
      // the row has a value from the first frame, and cancelling on that would
      // be a cancel before the transfer started, not a cancel of it.
      final running = Completer<void>();
      service.addListener(() {
        final percent = service.downloadPercent;
        if (!running.isCompleted && percent != null && percent > 0) {
          running.complete();
        }
      });

      final download = service.startDownload();
      await running.future;
      service.cancelDownload();
      await download;

      expect(gateway.cancelled, isTrue);
      expect(gateway.installed, isFalse);
      expect(service.installed, isFalse);
      expect(service.status, LocalChatModelStatus.notInstalled);
    });

    test('a retry after a failure clears the failure state', () async {
      final gateway = FakeLiteRtGateway(
        installError: const LiteRtOperationFailed(LiteRtFailure.connection),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);

      await model.download();
      expect(model.status, LocalChatModelStatus.error);
      expect(model.statusMessage, isNotNull);

      // The next attempt succeeds, so the old message must not survive.
      gateway.installError = null;
      await model.download();

      expect(model.status, LocalChatModelStatus.installed);
      expect(model.statusMessage, isNull);
    });

    test('a remove after a failure clears the failure state', () async {
      final gateway = FakeLiteRtGateway(
        installError: const LiteRtOperationFailed(LiteRtFailure.connection),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      expect(model.status, LocalChatModelStatus.error);

      // The failed transfer left a partially registered model behind, so there
      // is something to remove; the removal must clear the error.
      gateway.installed = true;
      expect(await model.remove(), LocalModelRemoval.removed);

      expect(model.status, LocalChatModelStatus.notInstalled);
      expect(model.statusMessage, isNull);
    });
  });

  group('lazy load and answer', () {
    test('loading is deferred to the first question and then sticks', () async {
      final gateway = FakeLiteRtGateway(installed: true);
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      expect(gateway.loadCalls, 0, reason: 'install does not read weights');

      expect(await model.ensureLoaded(), isTrue);
      expect(gateway.loadCalls, 1);
      expect(model.status, LocalChatModelStatus.ready);
      expect(model.isUsable, isTrue);

      // A second question reuses the loaded engine.
      expect(await model.ensureLoaded(), isTrue);
      expect(gateway.loadCalls, 1);
    });

    test('the engine is given a capped context window and output budget',
        () async {
      final gateway = FakeLiteRtGateway(installed: true);
      final model = LiteRtLocalChatModel(gateway: gateway, contextTokens: 2048);
      await model.download();

      final answer = await model.generate(
        prompt: 'QUESTION: what was that flight?',
        context: 'Flight BA123 to Lisbon',
      );

      expect(answer, 'Your BA123 to Lisbon is on 12 March.');
      expect(gateway.contextTokens, [2048]);
      expect(gateway.maxOutputTokens.single, inInclusiveRange(64, 512));
    });

    test('a tiny output request is raised to the floor, a huge one capped',
        () async {
      final gateway = FakeLiteRtGateway(installed: true);
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();

      await model.generate(prompt: 'q', context: '', maxTokens: 1);
      await model.generate(prompt: 'q', context: '', maxTokens: 100000);

      expect(gateway.maxOutputTokens, [
        LiteRtLocalChatModel.minMaxTokens,
        LiteRtLocalChatModel.maxTokensCap,
      ]);
    });

    test('the grounding rules travel as the runtime system instruction',
        () async {
      final gateway = FakeLiteRtGateway(installed: true);
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();

      await model.generate(prompt: 'QUESTION: flight?', context: 'BA123');

      final system = gateway.systemInstructions.last;
      expect(system, contains('Answer ONLY from the CONTEXT'));
      expect(system, contains('Never invent a screenshot'));
      expect(system, contains('say so plainly and stop'));
      expect(system, contains('Be concise and plain text'));
      // The rules must not also be inlined into the user turn: LiteRT-LM
      // applies the model's own chat template, so a hand-built second copy
      // would be duplicated by the runtime.
      expect(gateway.prompts.last, isNot(contains('RULES:')));
      expect(gateway.prompts.last, 'QUESTION: flight?\n\nCONTEXT:\nBA123');
    });

    test('a failed load never leaves a false ready status', () async {
      final gateway = FakeLiteRtGateway(
        installed: true,
        loadError: StateError('dlopen failed: /data/user/0/app/files/model'),
      );
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();

      expect(await model.ensureLoaded(), isFalse);

      expect(model.status, LocalChatModelStatus.error);
      expect(model.isUsable, isFalse);
      final message = model.statusMessage ?? '';
      expect(message, isNotEmpty);
      expect(message, isNot(contains('dlopen')));
      expect(message, isNot(contains('/data/user')));
    });

    test('a failed load is not retried per question', () async {
      final gateway = FakeLiteRtGateway(installed: true, loadError: 'boom');
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();

      await model.ensureLoaded();
      await model.ensureLoaded();
      await model.ensureLoaded();

      expect(gateway.loadCalls, 1, reason: 'one failure, one attempt');
    });

    test('an answer on an unusable model throws instead of inventing one',
        () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);

      expect(
        () => model.generate(prompt: 'q', context: ''),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('removal', () {
    test('remove deletes the model and clears the active identity', () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      await model.ensureLoaded();

      expect(await model.remove(), LocalModelRemoval.removed);

      expect(gateway.uninstallCalls, 1);
      expect(gateway.clearIdentityCalls, 1);
      expect(gateway.closeCalls, 1, reason: 'the engine is released first');
      expect(gateway.installed, isFalse);
      expect(model.status, LocalChatModelStatus.notInstalled);
      expect(model.statusMessage, isNull);
    });

    test('a removal that fails is reported, not claimed as done', () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      gateway.uninstallError = const FileSystemException('EACCES: /data/x');

      expect(await model.remove(), LocalModelRemoval.failed);

      expect(model.status, LocalChatModelStatus.error);
      final message = model.statusMessage ?? '';
      expect(message, isNot(contains('EACCES')));
      expect(message, isNot(contains('/data/x')));
    });

    test('removing when nothing was ever installed is a no-op success',
        () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);

      // Not `removed`: no file was deleted by this call, and a caller must not
      // be able to read a deleted file out of it.
      expect(await model.remove(), LocalModelRemoval.notRegistered);

      expect(gateway.uninstallCalls, 0);
      expect(gateway.installCalls, 0);
      expect(model.status, LocalChatModelStatus.notInstalled);
    });

    test('a removal that already failed is never later reported as removed',
        () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      gateway.uninstallError = const FileSystemException('EACCES: /data/x');

      // 1. "Delete everything" removes the model first and it fails, so the
      // file is still on this device.
      expect(await model.remove(), LocalModelRemoval.failed);
      expect(gateway.uninstallCalls, 1);

      // 2. The wipe then clears the store the runtime keeps its model index in.
      // The record of the file is gone; the file is not.
      gateway.uninstallError = null;
      gateway.installed = false;
      expect(await model.isInstalled(), isFalse);

      // 3. The user taps the row and removes again. Nothing is registered, so
      // this is the exact call that used to report a successful removal for a
      // file still sitting on the device, unreachable from in here for good.
      final second = await model.remove();

      expect(second, isNot(LocalModelRemoval.removed));
      expect(second, LocalModelRemoval.failed);
      // Nothing was asked of the runtime a second time, so nothing changed.
      expect(gateway.uninstallCalls, 1);
      // And the state says the truth: an error, not a clean "not installed".
      expect(model.status, LocalChatModelStatus.error);
      final message = model.statusMessage ?? '';
      expect(message, isNotEmpty);
      expect(message, contains('no longer track'));
      expect(message, isNot(contains('EACCES')));
      expect(message, isNot(contains('/data/x')));
    });

    test('the manager passes an unconfirmed removal through as a failure',
        () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      final service = LocalModelService(model: model);
      await model.download();
      gateway.uninstallError = const FileSystemException('EACCES: /data/x');
      expect(await service.removeModel(), LocalModelRemoval.failed);

      // The wipe the same "Delete everything" tap performs.
      gateway.uninstallError = null;
      gateway.installed = false;
      final second = await service.removeModel();

      expect(second, LocalModelRemoval.failed);
      // The row cannot keep offering Remove over a model it cannot see.
      expect(service.installed, isFalse);
      expect(service.status, LocalChatModelStatus.error);
      expect(service.statusMessage, contains('no longer track'));
    });

    test('a removal that did delete a file clears the unconfirmed flag',
        () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      gateway.uninstallError = const FileSystemException('EACCES: /data/x');
      expect(await model.remove(), LocalModelRemoval.failed);

      // The model is still registered, so a retry reaches the runtime and this
      // time deletes the file. That is a real removal, and it must clear the
      // doubt the failed attempt left behind.
      gateway.uninstallError = null;
      expect(await model.remove(), LocalModelRemoval.removed);
      expect(gateway.uninstallCalls, 2);

      expect(model.status, LocalChatModelStatus.notInstalled);
      expect(model.statusMessage, isNull);
      // And the doubt is gone: a later read that finds nothing is a plain
      // notRegistered again, not an unconfirmed removal that can never clear.
      expect(await model.remove(), LocalModelRemoval.notRegistered);
      expect(model.status, LocalChatModelStatus.notInstalled);
    });

    test('the model can be installed again after a removal', () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      await model.remove();

      await model.download();

      expect(gateway.installCalls, 2);
      expect(model.status, LocalChatModelStatus.installed);
    });

    test('the manager reports a partial removal honestly', () async {
      final model = FakeLocalChatModel(status: LocalChatModelStatus.installed)
        ..removeSucceeds = false;
      final service = LocalModelService(model: model);

      expect(await service.removeModel(), LocalModelRemoval.failed);

      expect(model.removeCalls, 1);
      expect(service.status, LocalChatModelStatus.error);
      expect(service.statusMessage, isNotNull);
    });

    test('disposing releases the engine but keeps the model on disk', () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      await model.ensureLoaded();

      await model.dispose();

      expect(gateway.closeCalls, 1);
      expect(gateway.uninstallCalls, 0);
      expect(gateway.installed, isTrue);
      expect(await model.isInstalled(), isFalse,
          reason: 'a disposed model reports nothing to the caller');
    });
  });

  group('the model store is keyed by file name', () {
    test('a full cycle asks the runtime only about the bundle file name',
        () async {
      final gateway = FakeLiteRtGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);

      // The cycle drives every model-manager call there is: the check before
      // the transfer, the verification after it, the check on the lazy load,
      // and the removal.
      await model.download();
      await model.ensureLoaded();
      expect(await model.remove(), LocalModelRemoval.removed);

      // Without this the assertion below would still pass if the bare id and
      // the file name ever became the same string.
      expect(
        LocalModelSpec.fileName,
        isNot(LocalModelSpec.modelId),
        reason: 'the bare model name is exactly what this guards against',
      );
      // The runtime looks its store up by the exact file name derived from the
      // download URL, so the base name would report a model that is on disk as
      // absent, and would delete nothing while the UI claimed a removal.
      expect(gateway.isInstalledArgs, isNotEmpty);
      expect(gateway.isInstalledArgs, everyElement(LocalModelSpec.fileName));
      expect(gateway.uninstallArgs, [LocalModelSpec.fileName]);
    });
  });

  group('source and privacy hygiene', () {
    test('the implementation never logs a URL, a path, or a raw error',
        () async {
      final source = await File('lib/services/litert_local_chat_model.dart')
          .readAsString();
      var checked = 0;
      for (final line in const LineSplitter().convert(source)) {
        if (!line.contains('debugPrint')) continue;
        checked++;
        expect(line, isNot(contains(r'$e')), reason: line);
        expect(line, isNot(contains(r'$error')), reason: line);
        expect(line.toLowerCase(), isNot(contains('url')), reason: line);
        expect(line.toLowerCase(), isNot(contains('path')), reason: line);
        expect(line.toLowerCase(), isNot(contains('exception')), reason: line);
      }
      // The file logs at all, so the loop above is not vacuous.
      expect(checked, greaterThan(0));
    });

    test('plugin logging is silenced so prompts never reach a device log',
        () async {
      final source = await File('lib/services/litert_local_chat_model.dart')
          .readAsString();
      // The verbose level writes prompts and conversation history, which for
      // SIFT is screenshot text.
      expect(source, contains('GemmaLogLevel.none'));
    });

    test('no hosted provider key or endpoint is required by this path',
        () async {
      for (final path in const [
        'lib/services/local_chat_model.dart',
        'lib/services/local_model_spec.dart',
        'lib/services/litert_local_chat_model.dart',
        'lib/services/local_model_service.dart',
      ]) {
        final source = await File(path).readAsString();
        expect(source, isNot(contains('apiKey')), reason: path);
        expect(source, isNot(contains('api_key')), reason: path);
        expect(source, isNot(contains('Bearer')), reason: path);
        expect(source, isNot(contains('AppConfig')), reason: path);
      }
    });

    test('the model binary is neither present in the tree nor an asset',
        () async {
      for (final dir in const ['lib', 'assets', 'test']) {
        final entities = await Directory(dir).list(recursive: true).toList();
        for (final entity in entities) {
          if (entity is! File) continue;
          final path = entity.path.toLowerCase();
          expect(path, isNot(endsWith('.gguf')), reason: entity.path);
          expect(path, isNot(endsWith('.litertlm')), reason: entity.path);
        }
      }
      final pubspec = await File('pubspec.yaml').readAsString();
      // The prose in a dependency comment may name the format; what must not
      // appear is a model committed as an asset or a dependency on a bundled
      // model file.
      expect(pubspec, isNot(contains('.gguf')));
      expect(pubspec, isNot(contains('Qwen3')));
      expect(pubspec, isNot(contains('flutter_llama')));
      // No declared list entry may point at a model bundle.
      final modelAsset = RegExp(
        r'^\s*-\s*\S*\.(litertlm|gguf|task|tflite|bin)\s*$',
        multiLine: true,
      );
      expect(modelAsset.hasMatch(pubspec), isFalse, reason: pubspec);
    });
    test('no llama.cpp or GGUF reference survives in the on-device path', () {
      // Scoped to the on-device model path on purpose. The cloud provider
      // catalog in lam_service.dart names hosted Llama model ids, and cloud
      // chat is deliberately unchanged, so a repo-wide ban would be wrong.
      const forbidden = ['llama', 'gguf'];
      for (final path in const [
        'lib/services/local_chat_model.dart',
        'lib/services/local_model_spec.dart',
        'lib/services/litert_local_chat_model.dart',
        'lib/services/local_model_service.dart',
      ]) {
        final lower = File(path).readAsStringSync().toLowerCase();
        for (final needle in forbidden) {
          expect(lower, isNot(contains(needle)), reason: path);
        }
      }
      // The runtime that is actually wired is LiteRT-LM.
      expect(LocalModelSpec.runtimeName, 'LiteRT-LM');
    });
  });
}

/// A gateway whose `install` completes without ever registering the model, so
/// the "the transfer returned but nothing was saved" branch can be exercised.
class _GatewayThatInstallsNothing implements LiteRtGateway {
  _GatewayThatInstallsNothing(this._inner);

  final LiteRtGateway _inner;
  int installCalls = 0;

  @override
  Future<bool> isInstalled(String modelFileName) =>
      _inner.isInstalled(modelFileName);

  @override
  Future<void> install({
    required String modelId,
    required String url,
    required void Function(int percent) onProgress,
    required LocalChatCancellation cancellation,
  }) async {
    installCalls++;
    onProgress(100);
  }

  @override
  Future<void> uninstall(String modelFileName) =>
      _inner.uninstall(modelFileName);

  @override
  Future<void> clearActiveIdentity() => _inner.clearActiveIdentity();

  @override
  Future<void> load({
    required int contextTokens,
    required PreferredBackend backend,
  }) =>
      _inner.load(contextTokens: contextTokens, backend: backend);

  @override
  Future<LiteRtSession> openChat({
    required int maxOutputTokens,
    required String systemInstruction,
  }) =>
      _inner.openChat(
        maxOutputTokens: maxOutputTokens,
        systemInstruction: systemInstruction,
      );

  @override
  Future<void> close() => _inner.close();
}
