import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/customer.dart';
import '../../models/milk_entry.dart';
import '../../providers/customer_provider.dart';
import '../../providers/milk_entry_provider.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
            Tab(icon: Icon(Icons.person_search), text: 'Customer Report'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Period Summary'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CustomerReportTab(),
          _PeriodSummaryTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TAB 1 — Customer Report
// ═══════════════════════════════════════════════════════════════════════════

class _CustomerReportTab extends StatefulWidget {
  const _CustomerReportTab();

  @override
  State<_CustomerReportTab> createState() => _CustomerReportTabState();
}

class _CustomerReportTabState extends State<_CustomerReportTab> {
  Customer? _selectedCustomer;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  List<MilkEntry>? _results;
  bool _loading = false;

  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  Future<void> _generate() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _results = null;
    });
    final entries = await context
        .read<MilkEntryProvider>()
        .getByCustomerAndDateRange(_selectedCustomer!.id!, _from, _to);
    setState(() {
      _results = entries;
      _loading = false;
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
      _results = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filter panel ──────────────────────────────────────────────────
        Container(
          color: Colors.blue.shade50,
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Consumer<CustomerProvider>(
                builder: (context, prov, _) =>
                    DropdownButtonFormField<Customer>(
                  value: _selectedCustomer,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select Customer',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: prov.allCustomers
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c.name)))
                      .toList(),
                  onChanged: (c) => setState(() {
                    _selectedCustomer = c;
                    _results = null;
                  }),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _DateCard(
                      label: 'From',
                      date: _from,
                      dateFmt: _dateFmt,
                      onTap: () => _pickDate(isFrom: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateCard(
                      label: 'To',
                      date: _to,
                      dateFmt: _dateFmt,
                      onTap: () => _pickDate(isFrom: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _generate,
                  icon: const Icon(Icons.search),
                  label: const Text('Generate Report',
                      style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),

        // ── Results ───────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _results == null
                  ? const Center(
                      child: Text(
                        'Select a customer and date range,\nthen tap Generate.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : _results!.isEmpty
                      ? const Center(
                          child: Text(
                            'No entries found for this period.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : _buildCustomerResults(),
        ),
      ],
    );
  }

  Widget _buildCustomerResults() {
    final entries = _results!;
    final totalQty = entries.fold<double>(0, (s, e) => s + e.quantity);
    final totalAmt = entries.fold<double>(0, (s, e) => s + e.amount);
    final avgFat =
        entries.fold<double>(0, (s, e) => s + e.fat) / entries.length;

    return Column(
      children: [
        // Summary strip
        Container(
          color: Colors.blue.shade700,
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MiniStat(label: 'Entries', value: '${entries.length}'),
              _MiniStat(
                  label: 'Total Qty',
                  value: '${totalQty.toStringAsFixed(2)} L'),
              _MiniStat(
                  label: 'Avg FAT',
                  value: '${avgFat.toStringAsFixed(2)}%'),
              _MiniStat(
                  label: 'Total',
                  value: 'INR ${_currFmt.format(totalAmt)}'),
            ],
          ),
        ),
        // Entries list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_dateFmt.format(e.date),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          Text('INR ${_currFmt.format(e.amount)}',
                              style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _EntryChip(
                              'Qty: ${e.quantity.toStringAsFixed(2)} L'),
                          _EntryChip('CLR: ${e.clr.toStringAsFixed(2)}'),
                          _EntryChip(
                              'FAT: ${e.fat.toStringAsFixed(2)}%'),
                          _EntryChip(
                              'Rate: ${e.rate.toStringAsFixed(2)}'),
                          _EntryChip(
                              'KG FAT: ${e.kgFat.toStringAsFixed(4)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Footer total
        Container(
          color: Colors.green.shade50,
          padding: const EdgeInsets.all(14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total (${entries.length} entries)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('INR ${_currFmt.format(totalAmt)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green)),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TAB 2 — Period Summary
// ═══════════════════════════════════════════════════════════════════════════

enum _PeriodType { daily, weekly, monthly, custom }

class _PeriodSummaryTab extends StatefulWidget {
  const _PeriodSummaryTab();

  @override
  State<_PeriodSummaryTab> createState() => _PeriodSummaryTabState();
}

class _PeriodSummaryTabState extends State<_PeriodSummaryTab> {
  _PeriodType _period = _PeriodType.daily;
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to = DateTime.now();
  List<Map<String, dynamic>>? _results;
  bool _loading = false;

  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _results = null;
    });
    final prov = context.read<MilkEntryProvider>();
    List<Map<String, dynamic>> data;
    switch (_period) {
      case _PeriodType.daily:
      case _PeriodType.custom:
        data = await prov.getDailyBreakdown(_from, _to);
        break;
      case _PeriodType.weekly:
        data = await prov.getWeeklyBreakdown(_from, _to);
        break;
      case _PeriodType.monthly:
        data = await prov.getMonthlyBreakdown(_from, _to);
        break;
    }
    setState(() {
      _results = data;
      _loading = false;
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    // Daily mode: From is locked — only the single "Date" picker is active
    if (isFrom && _period == _PeriodType.daily) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        // In daily mode keep From in sync with To (single day query)
        if (_period == _PeriodType.daily) {
          _from = picked;
        } else if (_from.isAfter(_to)) {
          _from = _to;
        }
      }
      _results = null;
    });
  }

  void _onPeriodChanged(_PeriodType p) {
    final now = DateTime.now();
    setState(() {
      _period = p;
      _results = null;
      switch (p) {
        case _PeriodType.daily:
          // Single date — From is locked to same as To
          _to   = now;
          _from = now;
          break;
        case _PeriodType.weekly:
          _from = now.subtract(const Duration(days: 27));
          _to   = now;
          break;
        case _PeriodType.monthly:
          _from = DateTime(now.year, 1, 1);
          _to   = now;
          break;
        case _PeriodType.custom:
          break;
      }
    });
  }

  String _periodLabel(Map<String, dynamic> row) {
    final label = (row['period_label'] as String?) ?? '';
    switch (_period) {
      case _PeriodType.daily:
      case _PeriodType.custom:
        try {
          return _dateFmt.format(DateTime.parse(label));
        } catch (_) {
          return label;
        }
      case _PeriodType.weekly:
        final start = (row['week_start'] as String?) ?? '';
        final end = (row['week_end'] as String?) ?? '';
        try {
          return '${_dateFmt.format(DateTime.parse(start))}'
              ' – ${_dateFmt.format(DateTime.parse(end))}';
        } catch (_) {
          return label;
        }
      case _PeriodType.monthly:
        try {
          final parts = label.split('-');
          final d =
              DateTime(int.parse(parts[0]), int.parse(parts[1]));
          return DateFormat('MMMM yyyy').format(d);
        } catch (_) {
          return label;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filter panel ──────────────────────────────────────────────────
        Container(
          color: Colors.blue.shade50,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Group by:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _PeriodChip(
                    label: 'Daily',
                    selected: _period == _PeriodType.daily,
                    onTap: () => _onPeriodChanged(_PeriodType.daily),
                  ),
                  _PeriodChip(
                    label: 'Weekly',
                    selected: _period == _PeriodType.weekly,
                    onTap: () => _onPeriodChanged(_PeriodType.weekly),
                  ),
                  _PeriodChip(
                    label: 'Monthly',
                    selected: _period == _PeriodType.monthly,
                    onTap: () => _onPeriodChanged(_PeriodType.monthly),
                  ),
                  _PeriodChip(
                    label: 'Custom Range',
                    selected: _period == _PeriodType.custom,
                    onTap: () => _onPeriodChanged(_PeriodType.custom),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _DateCard(
                      label: 'From',
                      date: _from,
                      dateFmt: _dateFmt,
                      // Grayed out when Daily — single date mode
                      disabled: _period == _PeriodType.daily,
                      onTap: () => _pickDate(isFrom: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateCard(
                      // Relabel as "Date" when Daily
                      label: _period == _PeriodType.daily ? 'Date' : 'To',
                      date: _to,
                      dateFmt: _dateFmt,
                      onTap: () => _pickDate(isFrom: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _generate,
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Generate Summary',
                      style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),

        // ── Results ───────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _results == null
                  ? const Center(
                      child: Text(
                        'Select period type and date range,\nthen tap Generate.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : _results!.isEmpty
                      ? const Center(
                          child: Text(
                            'No data found for this period.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : _buildSummaryResults(),
        ),
      ],
    );
  }

  Widget _buildSummaryResults() {
    final rows = _results!;
    final grandQty = rows.fold<double>(
        0, (s, r) => s + (r['total_quantity'] as num).toDouble());
    final grandAmt = rows.fold<double>(
        0, (s, r) => s + (r['total_amount'] as num).toDouble());

    return Column(
      children: [
        // Grand total strip
        Container(
          color: Colors.blue.shade700,
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MiniStat(label: 'Periods', value: '${rows.length}'),
              _MiniStat(
                  label: 'Total Qty',
                  value: '${grandQty.toStringAsFixed(2)} L'),
              _MiniStat(
                  label: 'Grand Total',
                  value: 'INR ${_currFmt.format(grandAmt)}'),
            ],
          ),
        ),
        // Period rows
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              final qty =
                  (r['total_quantity'] as num).toDouble();
              final amt = (r['total_amount'] as num).toDouble();
              final entryCount = r['entry_count'] as int;
              final pct = grandAmt > 0 ? (amt / grandAmt * 100) : 0.0;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              _periodLabel(r),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                          ),
                          Text(
                            'INR ${_currFmt.format(amt)}',
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Progress bar showing % of grand total
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.blue.shade400),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _EntryChip(
                              '${qty.toStringAsFixed(2)} L'),
                          _EntryChip('$entryCount entries'),
                          _EntryChip(
                              '${pct.toStringAsFixed(1)}% of total'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Footer
        Container(
          color: Colors.green.shade50,
          padding: const EdgeInsets.all(14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Grand Total (${rows.length} periods)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('INR ${_currFmt.format(grandAmt)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green)),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shared Small Widgets
// ═══════════════════════════════════════════════════════════════════════════

class _DateCard extends StatelessWidget {
  final String label;
  final DateTime date;
  final DateFormat dateFmt;
  final VoidCallback onTap;
  final bool disabled;

  const _DateCard({
    required this.label,
    required this.date,
    required this.dateFmt,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          // Gray background when disabled
          color: disabled ? Colors.grey.shade200 : Colors.white,
          border: Border.all(
            color: disabled
                ? Colors.grey.shade300
                : Colors.grey.shade400,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 16,
                color: disabled ? Colors.grey.shade400 : Colors.blue),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: disabled
                            ? Colors.grey.shade400
                            : Colors.grey)),
                Text(
                  dateFmt.format(date),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: disabled
                        ? Colors.grey.shade400
                        : Colors.black87,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Colors.blue.shade700
                : Colors.grey.shade400,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade700,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style:
                const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ],
    );
  }
}

class _EntryChip extends StatelessWidget {
  final String text;
  const _EntryChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: Colors.blue.shade800)),
    );
  }
}
