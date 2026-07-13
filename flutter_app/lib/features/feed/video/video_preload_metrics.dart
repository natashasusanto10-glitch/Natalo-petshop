import 'dart:async';

import '../../../services/app_analytics.dart';
import '../../../services/video_quality_service.dart';

void recordVideoPreloadMetric(
  String state, {
  required String surface,
  required NetworkTier tier,
  required int windowSize,
}) {
  unawaited(AppAnalytics.logEvent('video_preload_$state', {
    'surface': surface,
    'tier': tier.name,
    'window_size': windowSize,
  }));
}
