import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/customer_provider.dart';
import '../../providers/milk_entry_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _currencyFmt = NumberFormat('#,##0.00');
  final _qtyFmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final milkProv = context.read<MilkEntryProvider>();
    final custProv = context.read<CustomerProvider>();
    await Future.wait([
      milkProv.refreshTodayTotals(),
      milkProv.loadRecent(limit: 10),
      custProv.loadAll(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Consumer2<MilkEntryProvider, CustomerProvider>(
          builder: (context, milkProv, custProv, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: "Today's Milk",
                        value: '${_qtyFmt.format(milkProv.todayMilk)} L',
                        icon: Icons.opacity,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        label: "Today's Amount",
                        value: 'INR ${_currencyFmt.format(milkProv.todayAmount)}',
                        icon: Icons.currency_rupee,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<int>(
                  future: custProv.count(),
                  builder: (context, snap) => _SummaryCard(
                    label: 'Total Customers',
                    value: '${snap.data ?? 0}',
                    icon: Icons.people,
                    color: Colors.orange,
                    wide: true,
                  ),
                ),
                const SizedBox(height: 24),

                // Quick Actions
                const Text('Quick Actions',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                  children: [
                    _QuickAction(
                      label: 'Add Milk Entry',
                      icon: Icons.add_circle,
                      color: Colors.blue,
                      onTap: () =>
                          Navigator.pushNamed(context, '/add-milk-entry')
                              .then((_) => _load()),
                    ),
                    _QuickAction(
                      label: 'Customers',
                      icon: Icons.people,
                      color: Colors.purple,
                      onTap: () =>
                          Navigator.pushNamed(context, '/customers'),
                    ),
                    _QuickAction(
                      label: 'Reports',
                      icon: Icons.bar_chart,
                      color: Colors.teal,
                      onTap: () =>
                          Navigator.pushNamed(context, '/reports'),
                    ),
                    _QuickAction(
                      label: 'Backup',
                      icon: Icons.backup,
                      color: Colors.brown,
                      onTap: () =>
                          Navigator.pushNamed(context, '/backup'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Recent Entries
                const Text('Recent Entries',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (milkProv.loading)
                  const Center(child: CircularProgressIndicator())
                else if (milkProv.entries.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No entries yet.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  ...milkProv.entries.map((e) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.opacity, size: 18),
                          ),
                          title: Text(e.customerName ?? '—'),
                          subtitle: Text(
                              DateFormat('dd MMM yyyy').format(e.date)),
                          trailing: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            crossAxisAlignment:
                                CrossAxisAlignment.end,
                            children: [
                              Text('${e.quantity} L',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(
                                'INR ${_currencyFmt.format(e.amount)}',
                                style: const TextStyle(
                                    color: Colors.green, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      )),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.pushNamed(context, '/add-milk-entry').then((_) => _load()),
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue.shade700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.local_drink, color: Colors.white, size: 40),
                const SizedBox(height: 8),
                const Text(AppConstants.firmName,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text(AppConstants.firmLocation,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          _drawerItem(context, Icons.dashboard, 'Dashboard', '/dashboard'),
          _drawerItem(context, Icons.people, 'Customers', '/customers'),
          _drawerItem(context, Icons.add_circle, 'Add Milk Entry', '/add-milk-entry'),
          _drawerItem(context, Icons.receipt_long, 'Invoices', '/invoices'),
          _drawerItem(context, Icons.bar_chart, 'Reports', '/reports'),
          const Divider(),
          _drawerItem(context, Icons.backup, 'Backup & Restore', '/backup'),
          _drawerItem(context, Icons.settings, 'Settings', '/settings'),
        ],
      ),
    );
  }

  ListTile _drawerItem(
      BuildContext context, IconData icon, String label, String route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        if (ModalRoute.of(context)?.settings.name != route) {
          Navigator.pushNamed(context, route);
        }
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool wide;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
                Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
