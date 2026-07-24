import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Menyimpan foto catatan perawatan LOKAL di HP (bukan server). File hidup di
/// folder privat app: `<AppDocuments>/pet_care/<recordId>.jpg`. Hilang saat
/// user ganti HP / reinstall — record tetap utuh tanpa error.
class PetCarePhotoStore {
  PetCarePhotoStore._();

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/pet_care');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _fileFor(Directory dir, String recordId) =>
      File('${dir.path}/$recordId.jpg');

  Future<File> save(String recordId, String sourcePath) async {
    final dir = await _dir();
    final dest = _fileFor(dir, recordId);
    return File(sourcePath).copy(dest.path);
  }

  Future<File?> get(String recordId) async {
    final dir = await _dir();
    final file = _fileFor(dir, recordId);
    return await file.exists() ? file : null;
  }

  Future<void> delete(String recordId) async {
    final dir = await _dir();
    final file = _fileFor(dir, recordId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

final petCarePhotoStore = PetCarePhotoStore._();
