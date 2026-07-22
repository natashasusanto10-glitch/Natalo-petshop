import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/share_content.dart';
import 'package:natalo_petshop_flutter/services/share_sheet_launcher.dart';
import 'package:share_plus/share_plus.dart';

class _FakeShareGateway implements PlatformShareGateway {
  _FakeShareGateway(this._results);

  final List<ShareResultStatus> _results;
  final List<SharePayload> payloads = [];
  final List<Rect?> origins = [];

  @override
  Future<ShareResultStatus> share(SharePayload payload, {Rect? origin}) async {
    payloads.add(payload);
    origins.add(origin);
    return _results.removeAt(0);
  }
}

void main() {
  final payload = SharePayload(
    url: Uri(scheme: 'https', host: 'www.natalopetshop.com', path: '/feed/a'),
    text: 'Lihat postingan Natalo di Natalo.\nhttps://www.natalopetshop.com/feed/a',
  );

  test('success invokes completion once and preserves the popover origin',
      () async {
    final gateway = _FakeShareGateway([ShareResultStatus.success]);
    final launcher = ShareSheetLauncher();
    var completed = 0;
    const origin = Rect.fromLTWH(10, 20, 30, 40);

    final status = await launcher.launchPayload(
      payload,
      gateway: gateway,
      origin: origin,
      onCompleted: () async => completed++,
    );

    expect(status, ShareResultStatus.success);
    expect(completed, 1);
    expect(gateway.payloads, [payload]);
    expect(gateway.origins, [origin]);
  });

  for (final status in [
    ShareResultStatus.dismissed,
    ShareResultStatus.unavailable,
  ]) {
    test('$status never invokes the completion callback', () async {
      final gateway = _FakeShareGateway([status]);
      final launcher = ShareSheetLauncher();
      var completed = 0;

      final result = await launcher.launchPayload(
        payload,
        gateway: gateway,
        onCompleted: () async => completed++,
      );

      expect(result, status);
      expect(completed, 0);
    });
  }
}
