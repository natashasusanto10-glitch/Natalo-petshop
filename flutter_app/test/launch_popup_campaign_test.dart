import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/config/launch_popup_campaigns.dart';
import 'package:natalo_petshop_flutter/models/launch_popup_campaign.dart';

void main() {
  test('activeLaunchPopup mengembalikan campaign promo dengan CTA', () {
    final c = activeLaunchPopup();
    expect(c, isNotNull);
    expect(c!.tone, LaunchPopupTone.promo);
    expect(c.title, isNotEmpty);
    expect(c.hasCta, isTrue);
    expect(c.ctaHref, startsWith('/produk/'));
  });

  test('hasImage false saat imageUrl null', () {
    const c = LaunchPopupCampaign(
      id: 'x', tone: LaunchPopupTone.announcement,
      title: 't', body: 'b', categoryLabel: 'Pengumuman',
    );
    expect(c.hasImage, isFalse);
    expect(c.hasCta, isFalse);
    expect(c.dismissLabel, 'Nanti saja');
  });
}
