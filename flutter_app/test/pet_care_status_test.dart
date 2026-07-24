import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet_care_record.dart';

void main() {
  final now = DateTime(2026, 7, 24);

  group('scheduleStatusOf', () {
    test('past date is overdue', () {
      expect(scheduleStatusOf(DateTime(2026, 7, 10), now: now), ScheduleStatus.overdue);
    });
    test('today is soon', () {
      expect(scheduleStatusOf(DateTime(2026, 7, 24), now: now), ScheduleStatus.soon);
    });
    test('within 14 days is soon', () {
      expect(scheduleStatusOf(DateTime(2026, 8, 5), now: now), ScheduleStatus.soon);
    });
    test('beyond 14 days is normal', () {
      expect(scheduleStatusOf(DateTime(2026, 8, 20), now: now), ScheduleStatus.normal);
    });
  });

  group('scheduleCountdownLabel', () {
    test('overdue', () {
      expect(scheduleCountdownLabel(DateTime(2026, 7, 10), now: now), 'Terlambat 14 hari');
    });
    test('today', () {
      expect(scheduleCountdownLabel(DateTime(2026, 7, 24), now: now), 'Hari ini');
    });
    test('tomorrow', () {
      expect(scheduleCountdownLabel(DateTime(2026, 7, 25), now: now), 'Besok');
    });
    test('n days', () {
      expect(scheduleCountdownLabel(DateTime(2026, 7, 30), now: now), '6 hari lagi');
    });
  });

  group('PetCareCategory', () {
    test('ordered list is priority order', () {
      expect(PetCareCategory.ordered.map((c) => c.apiValue).toList(),
          ['grooming', 'deworm', 'flea', 'vaccine', 'vet', 'other']);
    });
    test('fromApi maps and defaults to other', () {
      expect(PetCareCategory.fromApi('flea'), PetCareCategory.flea);
      expect(PetCareCategory.fromApi('bogus'), PetCareCategory.other);
    });
    test('labels are Indonesian', () {
      expect(PetCareCategory.deworm.label, 'Obat Cacing');
      expect(PetCareCategory.vet.label, 'Periksa Dokter');
    });
  });
}
