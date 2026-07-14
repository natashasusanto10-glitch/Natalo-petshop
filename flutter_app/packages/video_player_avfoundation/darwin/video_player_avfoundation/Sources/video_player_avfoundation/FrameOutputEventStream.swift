// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if os(iOS)
  import Flutter

  /// A throttled heartbeat for newly copied video-output buffers.
  ///
  /// This does not prove that a frame was presented by the GPU or displayed to the user.
  final class FrameOutputEventStream: NSObject, FlutterStreamHandler {
    typealias PlayerGeneration = UInt64

    private let minimumInterval: TimeInterval = 0.25
    private var eventSink: FlutterEventSink?
    private var lastEmissionByPlayer: [Int64: TimeInterval] = [:]
    private var activePlayerGenerations: [Int64: PlayerGeneration] = [:]
    private var nextPlayerGeneration: PlayerGeneration = 1

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
      -> FlutterError?
    {
      performOnMainSync {
        lastEmissionByPlayer.removeAll()
        eventSink = events
      }
      return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
      performOnMainSync {
        eventSink = nil
        lastEmissionByPlayer.removeAll()
      }
      return nil
    }

    func registerPlayer(_ playerId: Int64) -> PlayerGeneration {
      performOnMainSync {
        let generation = nextPlayerGeneration
        nextPlayerGeneration &+= 1
        activePlayerGenerations[playerId] = generation
        return generation
      }
    }

    func recordOutput(
      playerId: Int64, playerGeneration: PlayerGeneration, textureId: Int64, frameCount: Int64,
      mediaTimeUs: Int64, monotonicTimeUs: Int64
    ) {
      let event: [String: Any] = [
        "playerId": playerId,
        "textureId": textureId,
        "frameCount": frameCount,
        "mediaTimeUs": mediaTimeUs,
        "monotonicTimeUs": monotonicTimeUs,
        "platform": "ios",
      ]
      performOnMainAsync { [weak self] in
        self?.enqueue(
          event: event, playerId: playerId, playerGeneration: playerGeneration)
      }
    }

    func removePlayer(_ playerId: Int64) {
      performOnMainSync {
        activePlayerGenerations.removeValue(forKey: playerId)
        lastEmissionByPlayer.removeValue(forKey: playerId)
      }
    }

    func invalidate() {
      performOnMainSync {
        eventSink = nil
        activePlayerGenerations.removeAll()
        lastEmissionByPlayer.removeAll()
      }
    }

    private func enqueue(
      event: [String: Any], playerId: Int64, playerGeneration: PlayerGeneration
    ) {
      guard activePlayerGenerations[playerId] == playerGeneration, let sink = eventSink else {
        return
      }
      let now = ProcessInfo.processInfo.systemUptime
      let elapsed = now - (lastEmissionByPlayer[playerId] ?? -Double.infinity)
      guard elapsed >= minimumInterval else {
        return
      }
      lastEmissionByPlayer[playerId] = now
      sink(event)
    }

    private func performOnMainAsync(_ action: @escaping () -> Void) {
      if Thread.isMainThread {
        action()
      } else {
        DispatchQueue.main.async(execute: action)
      }
    }

    private func performOnMainSync<T>(_ action: () -> T) -> T {
      if Thread.isMainThread {
        return action()
      }
      return DispatchQueue.main.sync(execute: action)
    }
  }
#endif
