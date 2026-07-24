import 'package:flutter/material.dart';

/// Kategori perawatan — WAJIB sinkron dengan `CARE_CATEGORIES` di
/// `lib/pet-care-api.ts` (backend). Urutan `ordered` = prioritas UI.
enum PetCareCategory {
  grooming,
  deworm,
  flea,
  vaccine,
  vet,
  other;

  static const List<PetCareCategory> ordered = [
    PetCareCategory.grooming,
    PetCareCategory.deworm,
    PetCareCategory.flea,
    PetCareCategory.vaccine,
    PetCareCategory.vet,
    PetCareCategory.other,
  ];

  static PetCareCategory fromApi(String? value) {
    for (final c in PetCareCategory.values) {
      if (c.name == value) return c;
    }
    return PetCareCategory.other;
  }

  String get apiValue => name;

  String get label {
    switch (this) {
      case PetCareCategory.grooming:
        return 'Grooming';
      case PetCareCategory.deworm:
        return 'Obat Cacing';
      case PetCareCategory.flea:
        return 'Obat Kutu';
      case PetCareCategory.vaccine:
        return 'Vaksin';
      case PetCareCategory.vet:
        return 'Periksa Dokter';
      case PetCareCategory.other:
        return 'Lainnya';
    }
  }

  IconData get icon {
    switch (this) {
      case PetCareCategory.grooming:
        return Icons.bathtub_outlined;
      case PetCareCategory.deworm:
        return Icons.medication_outlined;
      case PetCareCategory.flea:
        return Icons.pest_control_outlined;
      case PetCareCategory.vaccine:
        return Icons.vaccines_outlined;
      case PetCareCategory.vet:
        return Icons.medical_services_outlined;
      case PetCareCategory.other:
        return Icons.more_horiz_rounded;
    }
  }
}

class PetCareRecord {
  final String id;
  final PetCareCategory category;
  final DateTime doneAt;
  final String? note;
  final DateTime? nextDueAt;

  const PetCareRecord({
    required this.id,
    required this.category,
    required this.doneAt,
    this.note,
    this.nextDueAt,
  });

  factory PetCareRecord.fromJson(Map<String, dynamic> json) {
    final next = json['nextDueAt'] as String?;
    return PetCareRecord(
      id: json['id'] as String? ?? '',
      category: PetCareCategory.fromApi(json['category'] as String?),
      doneAt: DateTime.tryParse(json['doneAt'] as String? ?? '') ??
          DateTime.now(),
      note: json['note'] as String?,
      nextDueAt: next == null ? null : DateTime.tryParse(next),
    );
  }
}

class PetSchedule {
  final String recordId;
  final PetCareCategory category;
  final DateTime nextDueAt;

  const PetSchedule({
    required this.recordId,
    required this.category,
    required this.nextDueAt,
  });

  factory PetSchedule.fromJson(Map<String, dynamic> json) {
    return PetSchedule(
      recordId: json['recordId'] as String? ?? '',
      category: PetCareCategory.fromApi(json['category'] as String?),
      nextDueAt:
          DateTime.tryParse(json['nextDueAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

enum ScheduleStatus { overdue, soon, normal }

/// Days from `now` (date-only) to `due` (date-only). Negative = overdue.
int daysUntil(DateTime due, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final target = DateTime(due.year, due.month, due.day);
  return target.difference(today).inDays;
}

ScheduleStatus scheduleStatusOf(DateTime due, {DateTime? now}) {
  final days = daysUntil(due, now: now);
  if (days < 0) return ScheduleStatus.overdue;
  if (days <= 14) return ScheduleStatus.soon;
  return ScheduleStatus.normal;
}

String scheduleCountdownLabel(DateTime due, {DateTime? now}) {
  final days = daysUntil(due, now: now);
  if (days < 0) return 'Terlambat ${-days} hari';
  if (days == 0) return 'Hari ini';
  if (days == 1) return 'Besok';
  return '$days hari lagi';
}
