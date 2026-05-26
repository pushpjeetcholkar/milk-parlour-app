import 'dart:io';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import '../../core/database/database_helper.dart';
import '../../main.dart' show registerDailyBackupTask, cancelDailyBackupTask;
import '../../services/backup_service.dart';
import '../../services/google_drive_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  bool _driveSignedIn = false;
  bool _autoBackupEnabled = false;
  String? _userEmail;
  DateTime? _lastDriveBackup;
  List<drive.File> _driveFiles = [];
  bool _loadingDriveFiles = false;

  final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _loadDriveState();
  }

  Future<void> _loadDriveState() async {
    final signedIn = await GoogleDriveService.isSignedIn();
    final autoEnabled = await GoogleDriveService.isAutoBackupEnabled();
    final lastBackup = await GoogleDriveService.lastBackupTime();
    final user = await GoogleDriveService.currentUser();
    if (mounted) {
      setState(() {
        _driveSignedIn = signedIn;
        _autoBackupEnabled = autoEnabled;
        _lastDriveBackup = lastBackup;
        _userEmail = user?.email;
      });
    }
    if (signedIn) _loadDriveFiles();
  }

  Future<void> _loadDriveFiles() async {
    if (!mounted) return;
    setState(() => _loadingDriveFiles = true);
    final files = await GoogleDriveService.listBackups();
    if (mounted) setState(() { _driveFiles = files; _loadingDriveFiles = false; });
  }

  // ── Local backup ─────────────────────────────────────────────────────────────
  Future<void> _backup() async {
    setState(() => _busy = true);
    final path = await BackupService.backup();
    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path != null ? 'Backup saved to:\n$path' : 'Backup failed.'),
      backgroundColor: path != null ? null : Colors.red,
    ));
  }

  Future<void> _restore() async {
    final confirmed = await _confirmDialog(
      title: 'Restore Backup',
      content:
          'This will replace ALL current data with the backup. Are you sure?',
      destructive: true,
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final ok = await BackupService.restore();
    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Data restored successfully!' : 'Restore failed.'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  // ── Google Drive ──────────────────────────────────────────────────────────────
  Future<void> _driveSignIn() async {
    setState(() => _busy = true);
    final ok = await GoogleDriveService.signIn();
    setState(() => _busy = false);
    if (!mounted) return;
    if (ok) {
      await _loadDriveState();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Signed in to Google Drive!'),
        backgroundColor: Colors.green,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sign-in failed. See setup instructions.'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  Future<void> _driveSignOut() async {
    final ok = await _confirmDialog(
        title: 'Sign Out', content: 'Sign out from Google Drive?');
    if (ok != true) return;
    await GoogleDriveService.signOut();
    await GoogleDriveService.setAutoBackupEnabled(false);
    await cancelDailyBackupTask();
    if (mounted) {
      setState(() {
        _driveSignedIn = false;
        _autoBackupEnabled = false;
        _userEmail = null;
        _driveFiles = [];
      });
    }
  }

  Future<void> _driveBackupNow() async {
    setState(() => _busy = true);
    final id = await GoogleDriveService.uploadBackup();
    final lastBackup = await GoogleDriveService.lastBackupTime();
    setState(() { _busy = false; _lastDriveBackup = lastBackup; });
    if (!mounted) return;
    if (id != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Backup uploaded to Google Drive!'),
        backgroundColor: Colors.green,
      ));
      _loadDriveFiles();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Upload failed. Check internet connection.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _toggleAutoBackup(bool value) async {
    await GoogleDriveService.setAutoBackupEnabled(value);
    if (value) {
      await registerDailyBackupTask();
    } else {
      await cancelDailyBackupTask();
    }
    if (mounted) setState(() => _autoBackupEnabled = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value
          ? '⏰ Auto-backup enabled — runs daily at midnight'
          : 'Auto-backup disabled'),
    ));
  }

  Future<void> _restoreFromDrive(drive.File driveFile) async {
    final confirmed = await _confirmDialog(
      title: 'Restore from Drive',
      content: 'Restore "${driveFile.name}"?\nAll current data will be replaced.',
      destructive: true,
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    // Download to temp path then restore
    final db = DatabaseHelper();
    final dbPath = await db.getDatabasePath();
    final tempPath = '${dbPath}_drive_restore_tmp.db';

    final ok = await GoogleDriveService.downloadBackup(
        driveFile.id!, tempPath);
    if (!ok) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Download failed.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    final restored = await () async {
      try {
        await db.restoreFrom(tempPath);
        try { File(tempPath).deleteSync(); } catch (_) {}
        return true;
      } catch (_) {
        return false;
      }
    }();

    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(restored
          ? '✅ Data restored from Google Drive!'
          : 'Restore failed.'),
      backgroundColor: restored ? Colors.green : Colors.red,
    ));
  }

  Future<bool?> _confirmDialog(
      {required String title,
      required String content,
      bool destructive = false}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              destructive ? 'Yes, Replace' : 'Confirm',
              style: TextStyle(
                  color: destructive ? Colors.red : Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Local backup ─────────────────────────────────────────────────
          _sectionHeader('📱 Local Backup', Colors.blue),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Save a copy of your database to device storage.',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _backup,
                        icon: const Icon(Icons.backup),
                        label: const Text('Create Backup'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _restore,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Google Drive backup ──────────────────────────────────────────
          _sectionHeader('☁️ Google Drive Backup', Colors.green),
          _driveSignedIn ? _buildDriveSignedInCard() : _buildDriveSignInCard(),

          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],

          const SizedBox(height: 24),
          // Setup instructions
          _buildSetupNote(),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: color)),
    );
  }

  // ── Drive signed-out card ────────────────────────────────────────────────
  Widget _buildDriveSignInCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.cloud_off, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              const Text('Not connected to Google Drive',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Sign in to automatically back up your data every night '
              'at midnight and access backups from any device.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _driveSignIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign In with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  side: const BorderSide(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Drive signed-in card ─────────────────────────────────────────────────
  Widget _buildDriveSignedInCard() {
    return Column(
      children: [
        // Status card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                // User info row
                Row(children: [
                  CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child:
                        const Icon(Icons.cloud_done, color: Colors.green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Connected',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                        Text(_userEmail ?? '',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  TextButton(
                      onPressed: _driveSignOut,
                      child: const Text('Sign Out',
                          style: TextStyle(color: Colors.red))),
                ]),

                const Divider(height: 20),

                // Last backup time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Last backup',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey)),
                        Text(
                          _lastDriveBackup != null
                              ? _dateFmt.format(_lastDriveBackup!)
                              : 'Never',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _driveBackupNow,
                      icon: const Icon(Icons.cloud_upload, size: 18),
                      label: const Text('Backup Now'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                    ),
                  ],
                ),

                const Divider(height: 20),

                // Auto-backup toggle
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 20,
                        color: Colors.blue),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Auto-backup at midnight',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600)),
                          Text('Runs daily when connected to internet',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _autoBackupEnabled,
                      onChanged: _busy ? null : _toggleAutoBackup,
                      activeThumbColor: Colors.blue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Drive backups list
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud, color: Colors.blue),
                title: const Text('Drive Backups',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadDriveFiles,
                ),
              ),
              const Divider(height: 1),
              _loadingDriveFiles
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )
                  : _driveFiles.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No backups on Drive yet.',
                              style: TextStyle(color: Colors.grey)),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _driveFiles.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final f = _driveFiles[i];
                            final size = f.size != null
                                ? '${(int.parse(f.size!) / 1024).toStringAsFixed(1)} KB'
                                : '';
                            final created = f.createdTime != null
                                ? _dateFmt.format(f.createdTime!)
                                : '';
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.storage,
                                  color: Colors.blue, size: 20),
                              title: Text(f.name ?? '',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text('$created  $size',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: IconButton(
                                icon: const Icon(Icons.restore,
                                    size: 20, color: Colors.orange),
                                tooltip: 'Restore this backup',
                                onPressed: () =>
                                    _restoreFromDrive(f),
                              ),
                            );
                          },
                        ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Setup instructions ────────────────────────────────────────────────────
  Widget _buildSetupNote() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.info_outline,
                  color: Colors.amber, size: 18),
              const SizedBox(width: 6),
              const Text('Google Drive Setup (One-Time)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
            const SizedBox(height: 8),
            const Text(
              'If sign-in fails, you need to register the app in Google Cloud:\n\n'
              '1. Go to console.cloud.google.com\n'
              '2. Create a project & enable "Google Drive API"\n'
              '3. Credentials → Create → OAuth 2.0 Android Client\n'
              '   Package: com.hkmc.milk_parlour\n'
              '   SHA-1: run keytool command (see code comments)\n'
              '4. Download google-services.json → android/app/\n'
              '5. Rebuild the app',
              style: TextStyle(fontSize: 11, color: Colors.brown),
            ),
          ],
        ),
      ),
    );
  }
}
