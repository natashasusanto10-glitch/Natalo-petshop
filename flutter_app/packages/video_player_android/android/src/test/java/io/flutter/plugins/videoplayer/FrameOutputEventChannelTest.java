// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import androidx.media3.common.Format;
import io.flutter.plugin.common.EventChannel;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.junit.Test;

public final class FrameOutputEventChannelTest {
  private static final Format FORMAT = new Format.Builder().build();

  @Test
  public void doesNoHeartbeatWorkWithoutDartSubscriber() {
    EventChannel eventChannel = mock(EventChannel.class);
    CountingClock clock = new CountingClock();
    List<Runnable> queued = new ArrayList<>();
    FrameOutputEventChannel channel =
        new FrameOutputEventChannel(eventChannel, clock, queued::add);
    FrameOutputEventChannel.PlayerListener listener =
        channel.createPlayerListener(6L, 10L);

    listener.onVideoFrameAboutToBeRendered(100L, 0L, FORMAT, null);

    assertEquals(0, clock.readCount);
    assertEquals(0, queued.size());

    EventChannel.EventSink sink = mock(EventChannel.EventSink.class);
    channel.onListen(null, sink);
    listener.onVideoFrameAboutToBeRendered(150L, 0L, FORMAT, null);

    assertEquals(0, clock.readCount);
    assertEquals(0, queued.size());

    listener.setActive(true);
    listener.onVideoFrameAboutToBeRendered(200L, 0L, FORMAT, null);

    assertEquals(1, clock.readCount);
    assertEquals(1, queued.size());
    queued.get(0).run();
    verify(sink).success(org.mockito.ArgumentMatchers.any());
  }

  @SuppressWarnings("unchecked")
  @Test
  public void emitsCumulativeHeartbeatsAtMostFourTimesPerSecond() {
    EventChannel eventChannel = mock(EventChannel.class);
    MutableClock clock = new MutableClock();
    FrameOutputEventChannel channel =
        new FrameOutputEventChannel(eventChannel, clock, Runnable::run);
    EventChannel.EventSink sink = mock(EventChannel.EventSink.class);
    channel.onListen(null, sink);

    FrameOutputEventChannel.PlayerListener listener =
        channel.createPlayerListener(7L, 11L);
    listener.setActive(true);
    listener.onVideoFrameAboutToBeRendered(100L, 0L, FORMAT, null);
    clock.timeUs = 249_999L;
    listener.onVideoFrameAboutToBeRendered(200L, 0L, FORMAT, null);
    clock.timeUs = 250_000L;
    listener.onVideoFrameAboutToBeRendered(300L, 0L, FORMAT, null);

    org.mockito.ArgumentCaptor<Object> captor = org.mockito.ArgumentCaptor.forClass(Object.class);
    verify(sink, org.mockito.Mockito.times(2)).success(captor.capture());
    List<Object> captured = captor.getAllValues();
    Map<String, Object> first = (Map<String, Object>) captured.get(0);
    Map<String, Object> second = (Map<String, Object>) captured.get(1);
    assertEquals(7L, first.get("playerId"));
    assertEquals(11L, first.get("textureId"));
    assertEquals(1L, first.get("frameCount"));
    assertEquals(100L, first.get("mediaTimeUs"));
    assertEquals(0L, first.get("monotonicTimeUs"));
    assertEquals("android", first.get("platform"));
    assertEquals(3L, second.get("frameCount"));
    assertEquals(300L, second.get("mediaTimeUs"));
  }

  @SuppressWarnings("unchecked")
  @Test
  public void suppressesQueuedEmissionAfterDisposeAndSupportsNullTextureId() {
    EventChannel eventChannel = mock(EventChannel.class);
    MutableClock clock = new MutableClock();
    List<Runnable> queued = new ArrayList<>();
    FrameOutputEventChannel channel =
        new FrameOutputEventChannel(eventChannel, clock, queued::add);
    EventChannel.EventSink sink = mock(EventChannel.EventSink.class);
    channel.onListen(null, sink);

    FrameOutputEventChannel.PlayerListener listener =
        channel.createPlayerListener(8L, null);
    listener.setActive(true);
    listener.onVideoFrameAboutToBeRendered(100L, 0L, FORMAT, null);
    listener.dispose();
    queued.get(0).run();

    verify(sink, org.mockito.Mockito.never()).success(org.mockito.ArgumentMatchers.any());

    FrameOutputEventChannel.PlayerListener activeListener =
        channel.createPlayerListener(9L, null);
    activeListener.setActive(true);
    activeListener.onVideoFrameAboutToBeRendered(200L, 0L, FORMAT, null);
    queued.get(1).run();
    org.mockito.ArgumentCaptor<Object> captor = org.mockito.ArgumentCaptor.forClass(Object.class);
    verify(sink).success(captor.capture());
    assertNull(((Map<String, Object>) captor.getValue()).get("textureId"));
  }

  @Test
  public void queuedEventCannotCrossCancelAndRelisten() {
    EventChannel eventChannel = mock(EventChannel.class);
    MutableClock clock = new MutableClock();
    List<Runnable> queued = new ArrayList<>();
    FrameOutputEventChannel channel =
        new FrameOutputEventChannel(eventChannel, clock, queued::add);
    EventChannel.EventSink oldSink = mock(EventChannel.EventSink.class);
    EventChannel.EventSink newSink = mock(EventChannel.EventSink.class);
    channel.onListen(null, oldSink);

    FrameOutputEventChannel.PlayerListener listener =
        channel.createPlayerListener(10L, 12L);
    listener.setActive(true);
    listener.onVideoFrameAboutToBeRendered(100L, 0L, FORMAT, null);
    channel.onCancel(null);
    channel.onListen(null, newSink);
    queued.get(0).run();

    verify(oldSink, never()).success(org.mockito.ArgumentMatchers.any());
    verify(newSink, never()).success(org.mockito.ArgumentMatchers.any());

    clock.timeUs = 250_000L;
    listener.onVideoFrameAboutToBeRendered(200L, 0L, FORMAT, null);
    queued.get(1).run();
    verify(newSink).success(org.mockito.ArgumentMatchers.any());
  }

  @Test
  public void queuedEventIsSuppressedAfterPlayerBecomesInactive() {
    EventChannel eventChannel = mock(EventChannel.class);
    MutableClock clock = new MutableClock();
    List<Runnable> queued = new ArrayList<>();
    FrameOutputEventChannel channel =
        new FrameOutputEventChannel(eventChannel, clock, queued::add);
    EventChannel.EventSink sink = mock(EventChannel.EventSink.class);
    channel.onListen(null, sink);
    FrameOutputEventChannel.PlayerListener listener =
        channel.createPlayerListener(12L, 14L);
    listener.setActive(true);

    listener.onVideoFrameAboutToBeRendered(100L, 0L, FORMAT, null);
    listener.setActive(false);
    queued.get(0).run();

    verify(sink, never()).success(org.mockito.ArgumentMatchers.any());
  }

  @Test
  public void highFrameRateIsBoundedPerIntendedPlayingPlayer() {
    EventChannel eventChannel = mock(EventChannel.class);
    MutableClock clock = new MutableClock();
    FrameOutputEventChannel channel =
        new FrameOutputEventChannel(eventChannel, clock, Runnable::run);
    EventChannel.EventSink sink = mock(EventChannel.EventSink.class);
    channel.onListen(null, sink);
    FrameOutputEventChannel.PlayerListener listener =
        channel.createPlayerListener(11L, 13L);
    listener.setActive(true);

    for (int frame = 0; frame < 10_000; frame++) {
      clock.timeUs = frame * 1_000L;
      listener.onVideoFrameAboutToBeRendered(frame * 1_000L, 0L, FORMAT, null);
    }

    verify(sink, times(40)).success(org.mockito.ArgumentMatchers.any());
  }

  private static final class MutableClock implements FrameOutputEventChannel.Clock {
    long timeUs;

    @Override
    public long monotonicTimeUs() {
      return timeUs;
    }
  }

  private static final class CountingClock implements FrameOutputEventChannel.Clock {
    int readCount;

    @Override
    public long monotonicTimeUs() {
      readCount++;
      return 0L;
    }
  }
}
