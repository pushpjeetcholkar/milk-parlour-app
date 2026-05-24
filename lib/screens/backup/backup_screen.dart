import 'package:flutter/material.dart';
import '../../services/backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  Future<void> _backup() async {
    setState(() => _busy = true);
    final path = await BackupService.backup();
    setState(() => _busy = false);
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup saved to:\n$path')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Backup failed.'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Backup'),
        content: const Text(
            'This will replace all current data with the backup. Are you sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final ok = await BackupService.restore();
    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(ok ? 'Data restored successfully!' : 'Restore failed.'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Backup Data',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'Creates a copy of your SQLite database saved to your device storage.',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _backup,
                        icon: const Icon(Icons.backup),
                        label: const Text('Create Backup'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Restore Data',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'Select a previously saved backup file to restore your data. Current data will be replaced.',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _restore,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore from Backup'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            if (_busy)
              const Center(child: CircularProgressIndicator()),
            const Spacer(),
            const Text(
              '⚠️ Tip: Take regular backups and store them in Google Drive or WhatsApp for safety.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
