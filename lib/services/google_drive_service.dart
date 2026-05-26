import 'dart:io';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/database_helper.dart';

/// Handles Google Sign-In and Google Drive backup/restore.
///
/// ⚠️  SETUP REQUIRED before this works:
/// 1. Go to https://console.cloud.google.com/
/// 2. Create a project (or open an existing one)
/// 3. Enable "Google Drive API" for the project
/// 4. Go to APIs & Services → Credentials
/// 5. Create OAuth 2.0 Client ID → Android
///    Package name : com.hkmc.milk_parlour
///    SHA-1        : run the command below in your terminal:
///    keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
/// 6. Download the updated google-services.json → place at android/app/google-services.json
/// 7. Rebuild the app
class GoogleDriveService {
  static const _driveScope = 'https://www.googleapis.com/auth/drive.file';
  static const _folderName = 'HKMC Milk Backup';
  static const _prefLastBackupKey = 'last_drive_backup_time';
  static const _prefAutoBackupKey = 'auto_drive_backup_enabled';

  static final _googleSignIn = GoogleSignIn(scopes: [_driveScope]);

  // ── Auth ────────────────────────────────────────────────────────────────────

  static Future<bool> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      return account != null;
    } catch (e) {
      return false;
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  static Future<bool> isSignedIn() async {
    return _googleSignIn.isSignedIn();
  }

  static Future<GoogleSignInAccount?> currentUser() async {
    if (await isSignedIn()) return _googleSignIn.currentUser;
    return await _googleSignIn.signInSilently();
  }

  // ── Drive API access ────────────────────────────────────────────────────────

  static Future<drive.DriveApi?> _getApi() async {
    final account = _googleSignIn.currentUser ??
        await _googleSignIn.signInSilently();
    if (account == null) return null;
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  // ── Folder helpers ──────────────────────────────────────────────────────────

  static Future<String?> _getOrCreateFolder(drive.DriveApi api) async {
    try {
      final resp = await api.files.list(
        q: "mimeType='application/vnd.google-apps.folder'"
            " and name='$_folderName'"
            " and trashed=false",
        spaces: 'drive',
        $fields: 'files(id,name)',
      );
      if (resp.files != null && resp.files!.isNotEmpty) {
        return resp.files!.first.id!;
      }
      final folder = drive.File()
        ..name = _folderName
        ..mimeType = 'application/vnd.google-apps.folder';
      final created = await api.files.create(folder);
      return created.id;
    } catch (_) {
      return null;
    }
  }

  // ── Upload ──────────────────────────────────────────────────────────────────

  /// Uploads the current SQLite database to Google Drive.
  /// Returns the Drive file ID on success, null on failure.
  static Future<String?> uploadBackup() async {
    try {
      final api = await _getApi();
      if (api == null) return null;

      final dbPath = await DatabaseHelper().getDatabasePath();
      final dbFile = File(dbPath);
      if (!dbFile.existsSync()) return null;

      final folderId = await _getOrCreateFolder(api);
      if (folderId == null) return null;

      final timestamp =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'HKMC_backup_$timestamp.db';

      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId];

      final media = drive.Media(
        dbFile.openRead(),
        dbFile.lengthSync(),
        contentType: 'application/octet-stream',
      );

      final result =
          await api.files.create(driveFile, uploadMedia: media);

      // Persist last backup time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefLastBackupKey, DateTime.now().toIso8601String());

      return result.id;
    } catch (_) {
      return null;
    }
  }

  /// Silent upload for use in background tasks (no UI interaction).
  static Future<bool> silentBackup() async {
    try {
      // Silently sign in (won't show any dialog)
      final account = await _googleSignIn.signInSilently();
      if (account == null) return false;
      final id = await uploadBackup();
      return id != null;
    } catch (_) {
      return false;
    }
  }

  // ── List backups ────────────────────────────────────────────────────────────

  static Future<List<drive.File>> listBackups() async {
    try {
      final api = await _getApi();
      if (api == null) return [];

      final folderId = await _getOrCreateFolder(api);
      if (folderId == null) return [];

      final resp = await api.files.list(
        q: "'$folderId' in parents and trashed=false",
        orderBy: 'createdTime desc',
        $fields: 'files(id,name,size,createdTime)',
      );
      return resp.files ?? [];
    } catch (_) {
      return [];
    }
  }

  // ── Download / Restore ──────────────────────────────────────────────────────

  /// Downloads a Drive file to [localPath] for restore.
  static Future<bool> downloadBackup(
      String fileId, String localPath) async {
    try {
      final api = await _getApi();
      if (api == null) return false;

      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final sink = File(localPath).openWrite();
      await media.stream.pipe(sink);
      await sink.flush();
      await sink.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Preferences ─────────────────────────────────────────────────────────────

  static Future<DateTime?> lastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefLastBackupKey);
    if (s == null) return null;
    return DateTime.tryParse(s);
  }

  static Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoBackupKey) ?? false;
  }

  static Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoBackupKey, enabled);
  }
}
