import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_helper.dart';

class BackupService {
  static final _db = DatabaseHelper();

  /// Create a backup of the SQLite database and save to Downloads/chosen path
  static Future<String?> backup() async {
    final dir = await getExternalStorageDirectory();
    if (dir == null) return null;

    final backupPath = '${dir.path}/${AppConstants.backupFileName}';
    await _db.copyDatabaseTo(backupPath);
    return backupPath;
  }

  /// Let the user pick a backup file and restore from it
  static Future<bool> restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return false;

    final pickedPath = result.files.single.path;
    if (pickedPath == null) return false;

    try {
      await _db.restoreFrom(pickedPath);
      return true;
    } catch (e) {
      return false;
    }
  }
}
