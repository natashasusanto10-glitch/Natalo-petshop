import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';

void main() {
  test('filter Ditandai memanggil content=tagged', () {
    expect(PublicProfileContentFilter.shoppable.apiValue, 'tagged');
  });
}
