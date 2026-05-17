import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voice search service — wrapper di atas `speech_to_text` package.
///
/// Pakai SpeechRecognizer native Android + SFSpeechRecognizer iOS. Capacitor
/// WebView pakai webkitSpeechRecognition browser API yang tidak reliable di
/// Android (kadang hang, kadang permission stuck). Native jauh lebih akurat,
/// support partial results untuk live transcript, dan auto-stop saat user
/// diam.
///
/// API design:
/// - `initialize()` — request mic permission, check availability. Idempotent.
/// - `listen()` — start listening, returns Stream of partial transcripts.
///                Emits final transcript saat selesai, lalu close stream.
/// - `cancel()` — abort listening, no transcript emitted.
class VoiceSearchService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _available = false;
  StreamController<VoiceTranscript>? _activeController;

  bool get isAvailable => _available;
  bool get isListening => _speech.isListening;

  /// Initialize + request mic permission. Idempotent. Return true kalau
  /// service siap dipakai (permission granted + ada recognizer di device).
  Future<bool> initialize() async {
    if (_initialized) return _available;
    try {
      _available = await _speech.initialize(
        onError: (error) {
          if (kDebugMode) {
            debugPrint('[voice] error: ${error.errorMsg}');
          }
          _emitError(error);
        },
        onStatus: (status) {
          if (kDebugMode) {
            debugPrint('[voice] status: $status');
          }
          // status: "listening" | "notListening" | "done"
          if (status == 'done' || status == 'notListening') {
            _closeActive();
          }
        },
        debugLogging: kDebugMode,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[voice] init failed: $e');
      }
      _available = false;
    }
    _initialized = true;
    return _available;
  }

  /// Start listening — returns stream yang emit partial transcript
  /// + 1 final transcript (`isFinal: true`) sebelum close.
  ///
  /// Caller wajib `cancel()` kalau user tutup modal sebelum auto-stop.
  Stream<VoiceTranscript> listen({String localeId = 'id_ID'}) {
    // Kalau sebelumnya ada session yang belum di-close, abort dulu.
    _closeActive();

    final controller = StreamController<VoiceTranscript>();
    _activeController = controller;

    _speech
        .listen(
      onResult: (SpeechRecognitionResult result) {
        if (controller.isClosed) return;
        controller.add(
          VoiceTranscript(
            text: result.recognizedWords,
            isFinal: result.finalResult,
            confidence: result.confidence,
          ),
        );
        if (result.finalResult) {
          _closeActive();
        }
      },
      localeId: localeId,
      // listenFor: max session duration. Auto-stop kalau silence 3 detik.
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.search,
      ),
    )
        .catchError((Object error) {
      if (kDebugMode) {
        debugPrint('[voice] listen failed: $error');
      }
      if (!controller.isClosed) {
        controller.addError(error);
        controller.close();
      }
      _activeController = null;
    });

    return controller.stream;
  }

  /// Cancel current session — no transcript emitted, stream closes.
  Future<void> cancel() async {
    if (_speech.isListening) {
      try {
        await _speech.cancel();
      } catch (_) {}
    }
    _closeActive();
  }

  /// Stop listening softly — current partial transcript finalized.
  Future<void> stop() async {
    if (_speech.isListening) {
      try {
        await _speech.stop();
      } catch (_) {}
    }
  }

  void _emitError(SpeechRecognitionError error) {
    final controller = _activeController;
    if (controller != null && !controller.isClosed) {
      controller.addError(error.errorMsg);
      controller.close();
    }
    _activeController = null;
  }

  void _closeActive() {
    final controller = _activeController;
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
    _activeController = null;
  }
}

/// Snapshot transcript dari satu emit dari recognizer.
class VoiceTranscript {
  final String text;
  final bool isFinal;
  final double confidence;

  const VoiceTranscript({
    required this.text,
    required this.isFinal,
    required this.confidence,
  });
}

final voiceSearchService = VoiceSearchService();
