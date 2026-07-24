import '../models/pet.dart';
import '../models/pet_care_record.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

/// CRUD pet ("Anabulku") — GET/POST /api/member/pets,
/// PATCH/DELETE /api/member/pets/{id}, foto via
/// POST /api/member/pets/{id}/photo (multipart, sudah di-compress+crop
/// oleh caller lewat engine photo_crop bersama sebelum sampai sini).
class PetService {
  PetService._();

  Future<List<Pet>> fetchPets() async {
    final data = await apiClient.getJson('/api/member/pets');
    if (data is! Map<String, dynamic>) return const [];
    final raw = data['pets'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Pet.fromJson)
        .toList(growable: false);
  }

  Future<Pet> createPet({
    required String name,
    required String type,
    String? breed,
    DateTime? birthDate,
    PetGender? gender,
    String? bio,
    bool? sterilized,
    String? allergy,
    String? healthNote,
  }) async {
    readOnlyMode.assertWritable('pet_create');
    final data = await apiClient.postJson(
      '/api/member/pets',
      body: {
        'name': name,
        'type': type,
        if (breed != null) 'breed': breed,
        if (birthDate != null) 'birthDate': birthDate.toIso8601String(),
        if (gender != null) 'gender': gender.apiValue,
        if (bio != null) 'bio': bio,
        if (sterilized != null) 'sterilized': sterilized,
        if (allergy != null) 'allergy': allergy,
        if (healthNote != null) 'healthNote': healthNote,
      },
    );
    return Pet.fromJson((data as Map<String, dynamic>)['pet']);
  }

  Future<Pet> updatePet(
    String id, {
    required String name,
    required String type,
    String? breed,
    DateTime? birthDate,
    PetGender? gender,
    String? bio,
    bool? sterilized,
    String? allergy,
    String? healthNote,
  }) async {
    readOnlyMode.assertWritable('pet_update');
    final data = await apiClient.patchJson(
      '/api/member/pets/$id',
      body: {
        'name': name,
        'type': type,
        if (breed != null) 'breed': breed,
        if (birthDate != null) 'birthDate': birthDate.toIso8601String(),
        if (gender != null) 'gender': gender.apiValue,
        if (bio != null) 'bio': bio,
        if (sterilized != null) 'sterilized': sterilized,
        if (allergy != null) 'allergy': allergy,
        if (healthNote != null) 'healthNote': healthNote,
      },
    );
    return Pet.fromJson((data as Map<String, dynamic>)['pet']);
  }

  Future<void> deletePet(String id) async {
    readOnlyMode.assertWritable('pet_delete');
    await apiClient.deleteJson('/api/member/pets/$id');
  }

  /// Upload foto pet — file sudah di-crop+compress oleh caller (photo_crop
  /// engine, sama seperti foto profil user).
  Future<Pet> uploadPetPhoto(String id, String filePath) async {
    readOnlyMode.assertWritable('pet_photo_upload');
    final data = await apiClient.postMultipartFile(
      '/api/member/pets/$id/photo',
      fieldName: 'file',
      filePath: filePath,
      filename: 'pet.jpg',
      contentType: filePath.toLowerCase().endsWith('.png')
          ? 'image/png'
          : filePath.toLowerCase().endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg',
    );
    return Pet.fromJson((data as Map<String, dynamic>)['pet']);
  }

  Future<({List<PetCareRecord> records, List<PetSchedule> upcoming})>
      fetchCare(String petId) async {
    final data = await apiClient.getJson('/api/member/pets/$petId/care');
    final map = data as Map<String, dynamic>;
    final recordsRaw = map['records'];
    final upcomingRaw = map['upcoming'];
    final records = recordsRaw is List
        ? recordsRaw
            .whereType<Map<String, dynamic>>()
            .map(PetCareRecord.fromJson)
            .toList()
        : <PetCareRecord>[];
    final upcoming = upcomingRaw is List
        ? upcomingRaw
            .whereType<Map<String, dynamic>>()
            .map(PetSchedule.fromJson)
            .toList()
        : <PetSchedule>[];
    return (records: records, upcoming: upcoming);
  }

  Future<PetCareRecord> createCare(
    String petId, {
    required PetCareCategory category,
    required DateTime doneAt,
    String? note,
    DateTime? nextDueAt,
  }) async {
    readOnlyMode.assertWritable('createCare');
    final data = await apiClient.postJson(
      '/api/member/pets/$petId/care',
      body: {
        'category': category.apiValue,
        'doneAt': doneAt.toIso8601String(),
        if (note != null) 'note': note,
        if (nextDueAt != null) 'nextDueAt': nextDueAt.toIso8601String(),
      },
    );
    return PetCareRecord.fromJson(
        (data as Map<String, dynamic>)['record'] as Map<String, dynamic>);
  }

  Future<void> deleteCare(String petId, String recordId) async {
    readOnlyMode.assertWritable('deleteCare');
    await apiClient.deleteJson('/api/member/pets/$petId/care/$recordId');
  }
}

final petService = PetService._();
