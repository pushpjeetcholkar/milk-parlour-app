import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _defaultRate = 9.0;
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    _loadRate();
  }

  Future<void> _loadRate() async {
    final r = await SettingsService.getDefaultRate();
    if (mounted) setState(() => _defaultRate = r);
  }

  Future<void> _editDefaultRate() async {
    final ctrl = TextEditingController(text: _defaultRate.toStringAsFixed(2));
    final saved = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Default Rate per FAT'),
        content: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Rate (INR per FAT%)',
            border: OutlineInputBorder(),
            prefixText: 'INR ',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != null) {
      await SettingsService.setDefaultRate(saved);
      if (mounted) setState(() => _defaultRate = saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Default rate set to INR ${saved.toStringAsFixed(2)}'),
          ),
        );
      }
    }
  }

  // ── Dummy Data Seeder ──────────────────────────────────────────────────────
  Future<void> _confirmSeedDummyData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Demo Data'),
        content: const Text(
          'This will add 20 demo farmers with 30 days of milk entries '
          'so you can explore the analytics and reports.\n\n'
          'Existing real data will NOT be deleted.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add Demo Data'),
          ),
        ],
      ),
    );
    if (ok == true) await _seedDummyData();
  }

  Future<void> _seedDummyData() async {
    setState(() => _seeding = true);
    try {
      final db = await DatabaseHelper().database;
      final rng = Random(42); // Fixed seed for reproducibility
      final now = DateTime.now();

      // 20 demo farmer profiles: [name, mobile, minQty, maxQty, minFat, maxFat, attendance]
      final profiles = [
        ['Ramesh Kumar',    '9876543210', 10.0, 16.0, 5.0, 7.5, 0.95],
        ['Suresh Patel',    '9865432101', 8.0,  14.0, 4.5, 7.0, 0.90],
        ['Mahesh Sharma',   '9854321012', 12.0, 18.0, 5.5, 8.0, 0.92],
        ['Dinesh Yadav',    '9843210123', 6.0,  11.0, 4.0, 6.5, 0.85],
        ['Rajesh Verma',    '9832101234', 9.0,  15.0, 5.0, 7.0, 0.88],
        ['Kamlesh Singh',   '9821012345', 5.0,   9.0, 3.5, 5.5, 0.80],
        ['Umesh Tiwari',    '9810123456', 7.0,  12.0, 4.0, 6.0, 0.82],
        ['Lokesh Gupta',    '9801234567', 4.0,   8.0, 3.5, 5.0, 0.75],
        ['Amit Mishra',     '9712345678', 11.0, 17.0, 5.5, 7.5, 0.93],
        ['Bharat Patel',    '9723456789', 3.0,   7.0, 3.0, 5.0, 0.70],
        ['Chetan Kumar',    '9734567890', 8.0,  13.0, 4.5, 6.5, 0.87],
        ['Devendra Rao',    '9745678901', 5.0,   9.0, 4.0, 6.0, 0.78],
        ['Ganesh Yadav',    '9756789012', 10.0, 16.0, 5.0, 7.0, 0.91],
        ['Harish Sharma',   '9767890123', 2.5,   5.0, 3.0, 4.5, 0.65],
        ['Inder Singh',     '9778901234', 6.0,  10.0, 3.5, 5.5, 0.76],
        ['Jagdish Patel',   '9789012345', 9.0,  15.0, 5.0, 7.0, 0.89],
        ['Kailash Verma',   '9790123456', 4.0,   8.0, 3.5, 5.5, 0.72],
        ['Laxman Kumar',    '9601234567', 7.0,  13.0, 4.5, 6.5, 0.84],
        ['Mohan Bhaiya',    '9612345678', 8.0,  14.0, 4.0, 6.0, 0.81],
        ['Naresh Sharma',   '9623456789', 5.0,  10.0, 3.5, 5.5, 0.77],
      ];

      final rate = await SettingsService.getDefaultRate();

      for (final profile in profiles) {
        final name       = profile[0] as String;
        final mobile     = profile[1] as String;
        final minQty     = profile[2] as double;
        final maxQty     = profile[3] as double;
        final minFat     = profile[4] as double;
        final maxFat     = profile[5] as double;
        final attendance = profile[6] as double;

        // Insert customer
        final custId = await db.insert('customers', {
          'name':       name,
          'mobile':     mobile,
          'address':    'Village, Khargone MP',
          'created_at': now.toIso8601String(),
        });

        // Insert 30 days of entries (morning + evening some days)
        for (int d = 29; d >= 0; d--) {
          final date = now.subtract(Duration(days: d));

          // Morning shift
          if (rng.nextDouble() < attendance) {
            final qty = minQty + rng.nextDouble() * (maxQty - minQty);
            final fat = minFat + rng.nextDouble() * (maxFat - minFat);
            final kgfat = (qty * fat) / 100.0;
            final amount = qty * fat * rate;
            await db.insert('milk_entries', {
              'customer_id': custId,
              'date':        date.toIso8601String(),
              'quantity':    double.parse(qty.toStringAsFixed(2)),
              'clr':         _randomClr(rng),
              'fat':         double.parse(fat.toStringAsFixed(2)),
              'rate':        rate,
              'kgfat':       double.parse(kgfat.toStringAsFixed(4)),
              'amount':      double.parse(amount.toStringAsFixed(2)),
              'shift':       'Morning',
              'entry_time':  '0${6 + rng.nextInt(2)}:${(rng.nextInt(4) * 15).toString().padLeft(2, '0')}',
            });
          }

          // Evening shift (70% chance of double-shift)
          if (rng.nextDouble() < attendance * 0.7) {
            final qty = (minQty * 0.8) + rng.nextDouble() * (maxQty * 0.8 - minQty * 0.8);
            final fat = minFat + rng.nextDouble() * (maxFat - minFat);
            final kgfat = (qty * fat) / 100.0;
            final amount = qty * fat * rate;
            await db.insert('milk_entries', {
              'customer_id': custId,
              'date':        date.toIso8601String(),
              'quantity':    double.parse(qty.toStringAsFixed(2)),
              'clr':         _randomClr(rng),
              'fat':         double.parse(fat.toStringAsFixed(2)),
              'rate':        rate,
              'kgfat':       double.parse(kgfat.toStringAsFixed(4)),
              'amount':      double.parse(amount.toStringAsFixed(2)),
              'shift':       'Evening',
              'entry_time':  '${17 + rng.nextInt(2)}:${(rng.nextInt(4) * 15).toString().padLeft(2, '0')}',
            });
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Demo data added — 20 farmers, 30 days'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error seeding data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  double _randomClr(Random rng) =>
      double.parse((26.0 + rng.nextDouble() * 6.0).toStringAsFixed(1));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Milk Entry Defaults ──────────────────────────────────────────
          const _SectionHeader(title: 'Milk Entry Defaults'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.currency_rupee, color: Colors.blue),
              title: const Text('Default Rate per FAT'),
              subtitle: const Text('Pre-filled in every new milk entry'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'INR ${_defaultRate.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, size: 18, color: Colors.blue),
                ],
              ),
              onTap: _editDefaultRate,
            ),
          ),
          const SizedBox(height: 6),
          Card(
            child: ListTile(
              leading: const Icon(Icons.science_outlined,
                  color: Colors.grey),
              title: const Text('CLR Measurement'),
              subtitle: const Text(
                  'CLR is optional — leave blank if not measured'),
              trailing: const Chip(label: Text('Optional')),
            ),
          ),

          const SizedBox(height: 24),
          // ── Business Info ─────────────────────────────────────────────────
          const _SectionHeader(title: 'Business Information'),
          _InfoTile(label: 'Firm Name', value: AppConstants.firmName),
          _InfoTile(label: 'Location', value: AppConstants.firmLocation),
          _InfoTile(label: 'Mobile', value: AppConstants.firmMobile),
          _InfoTile(
              label: 'Invoice Prefix', value: AppConstants.invoicePrefix),

          const SizedBox(height: 24),
          // ── Demo Data ────────────────────────────────────────────────────
          const _SectionHeader(title: 'Demo & Testing'),
          Card(
            child: ListTile(
              leading: _seeding
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.people_alt_outlined,
                      color: Colors.teal),
              title: const Text('Load Demo Farmers'),
              subtitle: const Text(
                  'Adds 20 sample farmers with 30 days of data for analytics'),
              trailing: _seeding
                  ? null
                  : const Icon(Icons.add_circle_outline,
                      color: Colors.teal),
              onTap: _seeding ? null : _confirmSeedDummyData,
            ),
          ),

          const SizedBox(height: 24),
          // ── About ─────────────────────────────────────────────────────────
          const _SectionHeader(title: 'About'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Version'),
              trailing: Text('1.0.0'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.local_drink),
              title: Text('App'),
              trailing: Text('HKMC Milk App'),
            ),
          ),

          const SizedBox(height: 24),
          // ── Database ─────────────────────────────────────────────────────
          const _SectionHeader(title: 'Database'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('Database Type'),
              trailing: const Text('SQLite (Offline)'),
              subtitle: const Text('All data stored locally on device'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(value,
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ),
    );
  }
}
