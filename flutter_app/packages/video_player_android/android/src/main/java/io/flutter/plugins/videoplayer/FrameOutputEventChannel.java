// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.media.MediaFormat;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.Format;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.video.VideoFrameMetadataListener;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Global stream of throttled frame-output heartbeats for Android video players.
 *
 * <p>Media3 calls {@link VideoFrameMetadataListener} immediately before handing a frame to the
 * renderer. These events confirm decoder/renderer output, not GPU composition or display
 * presentation. The external channel name is retained for compatibility.
 *
 * <p>The app contract subscribes for the active, intended-playing player. Paused and preloaded
 * players do not produce frame-output callbacks. Each player is independently bounded to four
 * messages per second; a global winner-takes-all cap is intentionally avoided because it could
 * starve the active player when another renderer is producing output concurrently.
 */
final class FrameOutputEventChannel implements EventChannel.StreamHandler {
  static final String CHANNEL_NAME = "com.natalopetshop/video_rendered_frames";
  private static final long MIN_EMISSION_INTERVAL_US = 250_000L;

  interface Clock {
    long monotonicTimeUs();
  }

  interface Dispatcher {
    void dispatch(@NonNull Runnable runnable);
  }

  private final EventChannel channel;
  private final Clock clock;
  private final Dispatcher dispatcher;
  @Nullable private EventChannel.EventSink sink;
  private long subscriptionGeneration;

  FrameOutputEventChannel(@NonNull BinaryMessenger messenger) {
    this(
        new EventChannel(messenger, CHANNEL_NAME),
        () -> SystemClock.elapsedRealtimeNanos() / 1_000L,
        runnable -> new Handler(Looper.getMainLooper()).post(runnable));
  }

  FrameOutputEventChannel(
      @NonNull EventChannel channel, @NonNull Clock clock, @NonNull Dispatcher dispatcher) {
    this.channel = channel;
    this.clock = clock;
    this.dispatcher = dispatcher;
    channel.setStreamHandler(this);
  }

  @Override
  public synchronized void onListen(
      @Nullable Object arguments, @NonNull EventChannel.EventSink events) {
    subscriptionGeneration++;
    sink = events;
  }

  @Override
  public synchronized void onCancel(@Nullable Object arguments) {
    subscriptionGeneration++;
    sink = null;
  }

  private synchronized void clearSinkForDetach() {
    subscriptionGeneration++;
    sink = null;
  }

  void detach() {
    clearSinkForDetach();
    channel.setStreamHandler(null);
  }

  @NonNull
  PlayerListener createPlayerListener(long playerId, @Nullable Long textureId) {
    return new PlayerListener(this, playerId, textureId, clock, dispatcher);
  }

  @Nullable
  synchronized Long activeSubscriptionGeneration() {
    return sink == null ? null : subscriptionGeneration;
  }

  synchronized void emit(@NonNull Map<String, Object> event, long expectedGeneration) {
    if (sink != null && subscriptionGeneration == expectedGeneration) {
      sink.success(event);
    }
  }

  @OptIn(markerClass = UnstableApi.class)
  static final class PlayerListener implements VideoFrameMetadataListener {
    private final FrameOutputEventChannel owner;
    private final long playerId;
    @Nullable private final Long textureId;
    private final Clock clock;
    private final Dispatcher dispatcher;
    private long frameCount;
    private long lastEmissionTimeUs = Long.MIN_VALUE;
    private boolean active;
    private boolean disposed;

    PlayerListener(
        @NonNull FrameOutputEventChannel owner,
        long playerId,
        @Nullable Long textureId,
        @NonNull Clock clock,
        @NonNull Dispatcher dispatcher) {
      this.owner = owner;
      this.playerId = playerId;
      this.textureId = textureId;
      this.clock = clock;
      this.dispatcher = dispatcher;
    }

    @Override
    public synchronized void onVideoFrameAboutToBeRendered(
        long presentationTimeUs,
        long releaseTimeNs,
        @NonNull Format format,
        @Nullable MediaFormat mediaFormat) {
      if (disposed || !active) {
        return;
      }
      final Long expectedGeneration = owner.activeSubscriptionGeneration();
      if (expectedGeneration == null) {
        return;
      }
      frameCount++;
      final long nowUs = clock.monotonicTimeUs();
      if (lastEmissionTimeUs != Long.MIN_VALUE
          && nowUs - lastEmissionTimeUs < MIN_EMISSION_INTERVAL_US) {
        return;
      }
      lastEmissionTimeUs = nowUs;
      final long emittedFrameCount = frameCount;
      dispatcher.dispatch(
          () ->
              emitIfActive(
                  presentationTimeUs, emittedFrameCount, nowUs, expectedGeneration));
    }

    private synchronized void emitIfActive(
        long mediaTimeUs,
        long emittedFrameCount,
        long monotonicTimeUs,
        long expectedGeneration) {
      if (disposed || !active) {
        return;
      }
      Map<String, Object> event = new LinkedHashMap<>();
      event.put("playerId", playerId);
      event.put("textureId", textureId);
      event.put("frameCount", emittedFrameCount);
      event.put("mediaTimeUs", mediaTimeUs);
      event.put("monotonicTimeUs", monotonicTimeUs);
      event.put("platform", "android");
      owner.emit(event, expectedGeneration);
    }

    synchronized void dispose() {
      disposed = true;
      active = false;
    }

    synchronized void setActive(boolean active) {
      if (!disposed) {
        this.active = active;
      }
    }
  }
}
