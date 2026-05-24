import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/milk_entry.dart';
import '../../providers/milk_entry_provider.dart';
import '../../providers/customer_provider.dart';
import '../../models/customer.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Daily report
  DateTime _dailyDate = DateTime.now();

  // Monthly report
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.today), text: 'Daily'),
            Tab(icon: Icon(Icons.calendar_month), text: 'Monthly'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DailyReport(
            date: _dailyDate,
            dateFmt: _dateFmt,
            currFmt: _currFmt,
            onDateChanged: (d) => setState(() => _dailyDate = d),
          ),
          _MonthlyReport(
            month: _selectedMonth,
            year: _selectedYear,
            currFmt: _currFmt,
            onMonthChanged: (m, y) =>
                setState(() {
                  _selectedMonth = m;
                  _selectedYear = y;
                }),
          ),
        ],
      ),
    );
  }
}

// ── Daily Report ─────────────────────────────────────────────────────────────

class _DailyReport extends StatelessWidget {
  final DateTime date;
  final DateFormat dateFmt;
  final NumberFormat currFmt;
  final ValueChanged<DateTime> onDateChanged;

  const _DailyReport({
    required this.date,
    required this.dateFmt,
    required this.currFmt,
    required this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Date selector
        Card(
          margin: const EdgeInsets.all(12),
          child: ListTile(
            leading: const Icon(Icons.calendar_today, color: Colors.blue),
            title: Text('Date: ${dateFmt.format(date)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.edit),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (d != null) onDateChanged(d);
            },
          ),
        ),

        FutureBuilder<List<MilkEntry>>(
          future:
              context.read<MilkEntryProvider>().getByDate(date),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Expanded(
                  child: Center(child: CircularProgressIndicator()));
            }
            final entries = snap.data ?? [];
            if (entries.isEmpty) {
              return const Expanded(
                child: Center(
                    child: Text('No entries for this date.',
                        style: TextStyle(color: Colors.grey))),
              );
            }

            final totalQty =
                entries.fold<double>(0, (s, e) => s + e.quantity);
            final totalAmount =
                entries.fold<double>(0, (s, e) => s + e.amount);

            return Expanded(
              child: Column(
                children: [
                  // Summary
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Total Milk',
                            value:
                                '${totalQty.toStringAsFixed(2)} L',
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Total Amount',
                            value:
                                '₹ ${currFmt.format(totalAmount)}',
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Customer-wise Summary',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return Card(
                          child: ListTile(
                            title: Text(e.customerName ?? '—'),
                            subtitle: Text(
                                'FAT: ${e.fat} | CLR: ${e.clr} | KG FAT: ${e.kgFat.toStringAsFixed(4)}'),
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
                                    '₹ ${currFmt.format(e.amount)}',
                                    style: const TextStyle(
                                        color: Colors.green,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Monthly Report ────────────────────────────────────────────────────────────

class _MonthlyReport extends StatelessWidget {
  final int month;
  final int year;
  final NumberFormat currFmt;
  final void Function(int month, int year) onMonthChanged;

  const _MonthlyReport({
    required this.month,
    required this.year,
    required this.currFmt,
    required this.onMonthChanged,
  });

  static const _months = [
    'January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Month selector
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    final prevMonth = month == 1 ? 12 : month - 1;
                    final prevYear = month == 1 ? year - 1 : year;
                    onMonthChanged(prevMonth, prevYear);
                  },
                ),
                Text(
                  '${_months[month - 1]} $year',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    final nextMonth = month == 12 ? 1 : month + 1;
                    final nextYear = month == 12 ? year + 1 : year;
                    if (nextYear > DateTime.now().year ||
                        (nextYear == DateTime.now().year &&
                            nextMonth > DateTime.now().month)) return;
                    onMonthChanged(nextMonth, nextYear);
                  },
                ),
              ],
            ),
          ),
        ),

        FutureBuilder<List<Map<String, dynamic>>>(
          future: context
              .read<MilkEntryProvider>()
              .getMonthlySummary(year, month),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Expanded(
                  child: Center(child: CircularProgressIndicator()));
            }
            final data = snap.data ?? [];
            if (data.isEmpty) {
              return const Expanded(
                child: Center(
                    child: Text('No data for this month.',
                        style: TextStyle(color: Colors.grey))),
              );
            }

            final totalQty = data.fold<double>(
                0, (s, r) => s + (r['total_quantity'] as num).toDouble());
            final totalAmount = data.fold<double>(
                0, (s, r) => s + (r['total_amount'] as num).toDouble());

            return Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Total Milk',
                            value:
                                '${totalQty.toStringAsFixed(2)} L',
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Total Amount',
                            value:
                                '₹ ${currFmt.format(totalAmount)}',
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: data.length,
                      itemBuilder: (context, i) {
                        final r = data[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                  (r['customer_name'] as String)[0]
                                      .toUpperCase()),
                            ),
                            title: Text(r['customer_name'] as String),
                            subtitle: Text(
                                'Avg FAT: ${(r['avg_fat'] as num).toStringAsFixed(2)}%'),
                            trailing: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                Text(
                                    '${(r['total_quantity'] as num).toStringAsFixed(2)} L',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(
                                    '₹ ${currFmt.format(r['total_amount'])}',
                                    style: const TextStyle(
                                        color: Colors.green,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }
}
