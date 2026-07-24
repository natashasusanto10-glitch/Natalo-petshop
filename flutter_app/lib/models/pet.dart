/// Jenis pet — WAJIB sinkron dengan `PET_TYPES` di
/// `lib/pets-api.ts` (backend). Urutan dipakai sebagai opsi dropdown form.
const List<String> kPetTypes = [
  'Kucing',
  'Anjing',
  'Ikan',
  'Burung',
  'Reptil',
  'Lainnya',
];

/// Gender pet — 'male' | 'female' | null (belum diisi).
enum PetGender {
  male,
  female;

  static PetGender? fromApi(String? value) {
    switch (value) {
      case 'male':
        return PetGender.male;
      case 'female':
        return PetGender.female;
      default:
        return null;
    }
  }

  String get apiValue => name;

  String get label => this == PetGender.male ? 'Jantan' : 'Betina';
}

class Pet {
  final String id;
  final String name;
  final String type;
  final String? breed;
  final String? photoUrl;
  final DateTime? birthDate;
  final PetGender? gender;
  final String? bio;

  const Pet({
    required this.id,
    required this.name,
    required this.type,
    this.breed,
    this.photoUrl,
    this.birthDate,
    this.gender,
    this.bio,
  });

  factory Pet.fromJson(Map<String, dynamic> json) {
    final birthDateRaw = json['birthDate'] as String?;
    return Pet(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? kPetTypes.last,
      breed: json['breed'] as String?,
      photoUrl: json['photoUrl'] as String?,
      birthDate:
          birthDateRaw == null ? null : DateTime.tryParse(birthDateRaw),
      gender: PetGender.fromApi(json['gender'] as String?),
      bio: json['bio'] as String?,
    );
  }

  Pet copyWith({
    String? name,
    String? type,
    String? breed,
    String? photoUrl,
    DateTime? birthDate,
    PetGender? gender,
    String? bio,
  }) {
    return Pet(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      breed: breed ?? this.breed,
      photoUrl: photoUrl ?? this.photoUrl,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
    );
  }

  /// Umur ringkas ala "2 tahun 3 bulan" — null kalau birthDate belum diisi.
  String? get ageLabel {
    final birth = birthDate;
    if (birth == null) return null;
    final now = DateTime.now();
    var years = now.year - birth.year;
    var months = now.month - birth.month;
    if (now.day < birth.day) months -= 1;
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    if (years <= 0 && months <= 0) return 'Baru lahir';
    final parts = <String>[];
    if (years > 0) parts.add('$years tahun');
    if (months > 0) parts.add('$months bulan');
    return parts.join(' ');
  }
}
