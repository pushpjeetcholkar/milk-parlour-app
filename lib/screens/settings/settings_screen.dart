import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Business Info
          const _SectionHeader(title: 'Business Information'),
          _InfoTile(label: 'Firm Name', value: AppConstants.firmName),
          _InfoTile(label: 'Location', value: AppConstants.firmLocation),
          _InfoTile(label: 'Mobile', value: AppConstants.firmMobile),
          _InfoTile(
              label: 'Invoice Prefix', value: AppConstants.invoicePrefix),

          const SizedBox(height: 24),
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
