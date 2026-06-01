import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../models/milk_entry.dart';
import '../../providers/customer_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/milk_entry_provider.dart';
import '../../services/pdf_service.dart';
import 'analytics_tab.dart';

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
    _tabController = TabController(length: 4, vsync: this);
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
            Tab(icon: Icon(Icons.person_search), text: 'Customer'),
            Tab(icon: Icon(Icons.print_outlined), text: 'Collection'),
            Tab(icon: Icon(Icons.insights), text: 'Analytics'),
            Tab(icon: Icon(Icons.price_change), text: 'Avg ₹/L'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CustomerReportTab(),
          _CollectionReportTab(),
          AnalyticsTab(),
          _PricePerLiterTab(),
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
  Invoice? _invoice;
  bool _loading = false;
  bool _exportingPdf = false;
  String? _reportPdfPath; // path of the last generated report PDF

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
      _invoice = null;
      _reportPdfPath = null;
    });

    // Capture provider refs BEFORE any await
    final milkProv = context.read<MilkEntryProvider>();
    final invProv  = context.read<InvoiceProvider>();

    final entries = await milkProv.getByCustomerAndDateRange(
        _selectedCustomer!.id!, _from, _to);
    await invProv.loadAll();
    if (!mounted) return;

    // Find invoice for this customer whose period overlaps with selected range
    Invoice? matched;
    for (final inv in invProv.invoices) {
      if (inv.customerId == _selectedCustomer!.id &&
          !inv.toDate.isBefore(_from) &&
          !inv.fromDate.isAfter(_to)) {
        matched = inv;
        break;
      }
    }

    setState(() {
      _results = entries;
      _invoice = matched;
      _loading = false;
    });
  }

  Future<void> _exportPdf() async {
    final entries  = _results;
    final customer = _selectedCustomer;
    if (entries == null || entries.isEmpty || customer == null) return;

    setState(() => _exportingPdf = true);
    try {
      final path = await PdfService.generateReportPdf(
        customerName: customer.name,
        from: _from,
        to: _to,
        entries: entries,
        invoice: _invoice,
      );
      if (!mounted) return;
      setState(() => _reportPdfPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report PDF ready — tap Open or Share below')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
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
      _reportPdfPath = null;
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
    final entries          = _results!;
    final totalQty         = entries.fold<double>(0, (s, e) => s + e.quantity);
    final totalKgF         = entries.fold<double>(0, (s, e) => s + e.kgFat);
    final totalMilkAmt     = entries.fold<double>(0, (s, e) => s + e.amount);
    final totalItemsDed    = entries.fold<double>(0, (s, e) => s + e.itemAmount);
    final extraAmt         = _invoice?.extraAmount ?? 0;
    final netPayable       =
        (totalMilkAmt + extraAmt - totalItemsDed).roundToDouble();

    return Column(
      children: [
        // ── Summary strip ─────────────────────────────────────────────
        Container(
          color: Colors.blue.shade700,
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MiniStat(
                  label: 'KG FAT',
                  value: totalKgF.toStringAsFixed(3)),
              _MiniStat(
                  label: 'Milk Amt',
                  value: 'INR ${_currFmt.format(totalMilkAmt)}'),
              _MiniStat(
                  label: 'Total Milk Qty',
                  value: '${totalQty.toStringAsFixed(2)} L'),
            ],
          ),
        ),

        // ── Action bar ────────────────────────────────────────────────
        Container(
          color: Colors.grey.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              // Edit Invoice button (only when invoice found)
              if (_invoice != null) ...[
                OutlinedButton.icon(
                  onPressed: _exportingPdf
                      ? null
                      : () => _showEditInvoiceDialog(_invoice!),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit Invoice',
                      style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade700,
                    side: BorderSide(color: Colors.orange.shade400),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),

              // Once PDF is generated: Open + Share buttons
              if (_reportPdfPath != null &&
                  File(_reportPdfPath!).existsSync()) ...[
                OutlinedButton.icon(
                  onPressed: () => OpenFile.open(_reportPdfPath!),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                    side: BorderSide(color: Colors.blue.shade400),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () =>
                      PdfService.shareReportPdf(_reportPdfPath!),
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Share', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal.shade700,
                    side: BorderSide(color: Colors.teal.shade400),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
              ],

              // Export / Regenerate PDF button
              ElevatedButton.icon(
                onPressed: _exportingPdf ? null : _exportPdf,
                icon: _exportingPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf, size: 18),
                label: Text(
                  _exportingPdf
                      ? 'Generating…'
                      : _reportPdfPath != null
                          ? 'Regenerate'
                          : 'Export PDF',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Entries list ──────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              final shiftIcon = e.shift == 'Morning'
                  ? Icons.wb_sunny
                  : Icons.nights_stay;
              final shiftColor =
                  e.shift == 'Morning' ? Colors.orange : Colors.indigo;

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
                          // Date + shift + time
                          Row(
                            children: [
                              Text(_dateFmt.format(e.date),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Icon(shiftIcon,
                                  size: 14, color: shiftColor),
                              const SizedBox(width: 2),
                              Text(
                                e.shift,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: shiftColor,
                                    fontWeight: FontWeight.w600),
                              ),
                              if (e.entryTime != null) ...[
                                const SizedBox(width: 6),
                                Text('• ${e.entryTime}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey)),
                              ],
                            ],
                          ),
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
                              'KG FAT: ${e.kgFat.toStringAsFixed(3)}',
                              faint: true),
                          _EntryChip(
                              'Qty: ${e.quantity.toStringAsFixed(2)} L'),
                          _EntryChip(
                              'FAT: ${e.fat.toStringAsFixed(2)}%'),
                          _EntryChip(
                              'Rate: ${e.rate.toStringAsFixed(2)}'),
                          _EntryChip(
                              'CLR: ${e.clr.toStringAsFixed(2)}',
                              faint: true),
                          if (e.milkType != 'Cow')
                            _EntryChip(e.milkType, color: Colors.brown),
                          if (e.itemName != null && e.itemName!.isNotEmpty)
                            _EntryChip(
                                '${e.itemName}: −₹${e.itemAmount.toStringAsFixed(0)}',
                                color: Colors.amber.shade700),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // ── Footer totals ─────────────────────────────────────────────
        Container(
          color: Colors.green.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('KG FAT',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      Text(totalKgF.toStringAsFixed(4),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.blue.shade700)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Total Milk Quantity',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      Text('${totalQty.toStringAsFixed(2)} L',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.blue.shade800)),
                    ],
                  ),
                ],
              ),
              if (totalItemsDed > 0 || extraAmt > 0) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Net Payable',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('INR ${_currFmt.format(netPayable)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.green)),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('INR ${_currFmt.format(netPayable)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.green)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showEditInvoiceDialog(Invoice invoice) {
    showDialog<Invoice?>(
      context: context,
      builder: (_) => _ReportEditInvoiceDialog(invoice: invoice),
    ).then((updated) {
      if (updated != null && mounted) {
        setState(() => _invoice = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice updated!')),
        );
      }
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TAB 2 — Collection Report (printable day/shift/week/month/custom)
// ═══════════════════════════════════════════════════════════════════════════

enum _CollectionPeriod { today, week, month, custom }

class _CollectionReportTab extends StatefulWidget {
  const _CollectionReportTab();

  @override
  State<_CollectionReportTab> createState() => _CollectionReportTabState();
}

class _CollectionReportTabState extends State<_CollectionReportTab> {
  _CollectionPeriod _period = _CollectionPeriod.today;
  DateTime _from = DateTime.now();
  DateTime _to   = DateTime.now();
  String? _shiftFilter; // null = all, 'Morning', 'Evening'
  List<MilkEntry>? _results;
  bool _loading     = false;
  bool _exporting   = false;
  String? _pdfPath;

  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  void _applyPeriod(_CollectionPeriod p) {
    final now = DateTime.now();
    setState(() {
      _period  = p;
      _results = null;
      _pdfPath = null;
      switch (p) {
        case _CollectionPeriod.today:
          _from = _to = DateTime(now.year, now.month, now.day);
          break;
        case _CollectionPeriod.week:
          _from = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          _to = now;
          break;
        case _CollectionPeriod.month:
          _from = DateTime(now.year, now.month, 1);
          _to   = now;
          break;
        case _CollectionPeriod.custom:
          break;
      }
    });
  }

  Future<void> _generate() async {
    if (!mounted) return;
    setState(() { _loading = true; _results = null; _pdfPath = null; });
    final prov = context.read<MilkEntryProvider>();
    var entries = await prov.getByDateRange(_from, _to);
    // Apply shift filter in memory
    if (_shiftFilter != null) {
      entries = entries.where((e) => e.shift == _shiftFilter).toList();
    }
    // Sort by date → shift → CID
    entries.sort((a, b) {
      final dc = a.date.compareTo(b.date);
      if (dc != 0) return dc;
      final sc = a.shift.compareTo(b.shift);
      if (sc != 0) return sc;
      return a.customerId.compareTo(b.customerId);
    });
    if (!mounted) return;
    setState(() { _results = entries; _loading = false; });
  }

  Future<void> _exportPdf() async {
    if (_results == null || _results!.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final path = await PdfService.generateCollectionReportPdf(
        from: _from,
        to: _to,
        entries: _results!,
        shiftFilter: _shiftFilter,
      );
      if (!mounted) return;
      setState(() => _pdfPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collection report PDF ready')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printPdf() async {
    if (_pdfPath == null) {
      // Generate first, then print
      await _exportPdf();
    }
    if (_pdfPath != null && File(_pdfPath!).existsSync()) {
      await PdfService.printPdf(_pdfPath!);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
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
        if (_period == _CollectionPeriod.today) _from = picked;
        else if (_from.isAfter(_to)) _from = _to;
      }
      _results = null;
      _pdfPath = null;
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Period:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _PeriodChip(
                    label: 'Today',
                    selected: _period == _CollectionPeriod.today,
                    onTap: () => _applyPeriod(_CollectionPeriod.today),
                  ),
                  _PeriodChip(
                    label: 'This Week',
                    selected: _period == _CollectionPeriod.week,
                    onTap: () => _applyPeriod(_CollectionPeriod.week),
                  ),
                  _PeriodChip(
                    label: 'This Month',
                    selected: _period == _CollectionPeriod.month,
                    onTap: () => _applyPeriod(_CollectionPeriod.month),
                  ),
                  _PeriodChip(
                    label: 'Custom Range',
                    selected: _period == _CollectionPeriod.custom,
                    onTap: () => _applyPeriod(_CollectionPeriod.custom),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Shift filter
              Row(
                children: [
                  const Text('Shift:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SegmentedButton<String?>(
                      segments: const [
                        ButtonSegment(
                          value: null,
                          label: Text('All'),
                          icon: Icon(Icons.all_inclusive, size: 14),
                        ),
                        ButtonSegment(
                          value: 'Morning',
                          label: Text('Morning'),
                          icon: Icon(Icons.wb_sunny, size: 14),
                        ),
                        ButtonSegment(
                          value: 'Evening',
                          label: Text('Evening'),
                          icon: Icon(Icons.nights_stay, size: 14),
                        ),
                      ],
                      selected: {_shiftFilter},
                      onSelectionChanged: (s) =>
                          setState(() { _shiftFilter = s.first; _results = null; _pdfPath = null; }),
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Date pickers
              Row(children: [
                Expanded(
                  child: _DateCard(
                    label: 'From',
                    date: _from,
                    dateFmt: _dateFmt,
                    disabled: _period == _CollectionPeriod.today,
                    onTap: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateCard(
                    label: _period == _CollectionPeriod.today ? 'Date' : 'To',
                    date: _to,
                    dateFmt: _dateFmt,
                    onTap: () => _pickDate(false),
                  ),
                ),
              ]),
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
                        'Select period and shift, then tap Generate.',
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
                      : _buildCollectionResults(),
        ),
      ],
    );
  }

  Widget _buildCollectionResults() {
    final entries  = _results!;
    final totalQty = entries.fold<double>(0, (s, e) => s + e.quantity);
    final totalKgF = entries.fold<double>(0, (s, e) => s + e.kgFat);
    final totalAmt = entries.fold<double>(0, (s, e) => s + e.amount);
    final totalDed = entries.fold<double>(0, (s, e) => s + e.itemAmount);

    return Column(
      children: [
        // ── Summary strip ─────────────────────────────────────────────
        Container(
          color: Colors.blue.shade700,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MiniStat(
                  label: 'Total Milk Qty',
                  value: '${totalQty.toStringAsFixed(2)} L'),
              _MiniStat(
                  label: 'KG FAT',
                  value: totalKgF.toStringAsFixed(3)),
              _MiniStat(
                  label: 'Total Amount',
                  value: 'INR ${_currFmt.format(totalAmt)}'),
            ],
          ),
        ),

        // ── Action bar (Print / Export PDF / Share) ───────────────────
        Container(
          color: Colors.grey.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              // Print button
              OutlinedButton.icon(
                onPressed: _exporting ? null : _printPdf,
                icon: const Icon(Icons.print, size: 16),
                label: const Text('Print', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade700,
                  side: BorderSide(color: Colors.blue.shade400),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const Spacer(),

              if (_pdfPath != null && File(_pdfPath!).existsSync()) ...[
                OutlinedButton.icon(
                  onPressed: () => OpenFile.open(_pdfPath!),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                    side: BorderSide(color: Colors.blue.shade400),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () =>
                      PdfService.shareReportPdf(_pdfPath!),
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Share', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal.shade700,
                    side: BorderSide(color: Colors.teal.shade400),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
              ],

              ElevatedButton.icon(
                onPressed: _exporting ? null : _exportPdf,
                icon: _exporting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf, size: 18),
                label: Text(
                  _exporting ? 'Generating…'
                      : _pdfPath != null ? 'Regenerate' : 'Export PDF',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Entries list ──────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              final shiftIcon = e.shift == 'Morning'
                  ? Icons.wb_sunny
                  : Icons.nights_stay;
              final shiftColor =
                  e.shift == 'Morning' ? Colors.orange : Colors.indigo;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Text('CID: ${e.customerId}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 10),
                            Text(_dateFmt.format(e.date),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700)),
                            const SizedBox(width: 8),
                            Icon(shiftIcon, size: 14, color: shiftColor),
                            const SizedBox(width: 2),
                            Text(e.shift,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: shiftColor,
                                    fontWeight: FontWeight.w600)),
                          ]),
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
                          _EntryChip(
                              'FAT: ${e.fat.toStringAsFixed(2)}%'),
                          _EntryChip(
                              'Rate: ${e.rate.toStringAsFixed(2)}'),
                          _EntryChip(
                              'KG FAT: ${e.kgFat.toStringAsFixed(3)}',
                              faint: true),
                          if (e.milkType != 'Cow')
                            _EntryChip(e.milkType, color: Colors.brown),
                          if (e.itemName != null && e.itemName!.isNotEmpty)
                            _EntryChip(
                                '${e.itemName}: −₹${e.itemAmount.toStringAsFixed(0)}',
                                color: Colors.amber.shade700),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // ── Footer totals ─────────────────────────────────────────────
        Container(
          color: Colors.green.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KG FAT: ${totalKgF.toStringAsFixed(4)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700),
                  ),
                  if (totalDed > 0)
                    Text(
                      'Deductions: −INR ${_currFmt.format(totalDed)}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.red.shade600),
                    ),
                  Text('Total: INR ${_currFmt.format(totalAmt)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.green)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total Milk Quantity',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text('${totalQty.toStringAsFixed(2)} L',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blue.shade800)),
                ],
              ),
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

// ═══════════════════════════════════════════════════════════════════════════
//  TAB 4 — Average Price per Litre
// ═══════════════════════════════════════════════════════════════════════════

enum _PricePeriod { today, thisWeek, thisMonth, last30, custom }

class _PricePerLiterTab extends StatefulWidget {
  const _PricePerLiterTab();

  @override
  State<_PricePerLiterTab> createState() => _PricePerLiterTabState();
}

class _PricePerLiterTabState extends State<_PricePerLiterTab> {
  _PricePeriod _period = _PricePeriod.thisMonth;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to   = DateTime.now();
  List<Map<String, dynamic>>? _results;
  bool _loading  = false;

  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  // No auto-load in initState — the tab fires async DB work even when not visible,
  // which can corrupt the widget tree when navigation is in progress.
  // The user explicitly taps a period chip or "Generate" to load data.

  void _applyPeriod(_PricePeriod p) {
    final now = DateTime.now();
    setState(() {
      _period = p;
      _results = null;
      switch (p) {
        case _PricePeriod.today:
          _from = _to = DateTime(now.year, now.month, now.day);
          break;
        case _PricePeriod.thisWeek:
          _from = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          _to = now;
          break;
        case _PricePeriod.thisMonth:
          _from = DateTime(now.year, now.month, 1);
          _to   = now;
          break;
        case _PricePeriod.last30:
          _from = now.subtract(const Duration(days: 29));
          _to   = now;
          break;
        case _PricePeriod.custom:
          break;
      }
    });
  }

  Future<void> _generate() async {
    if (!mounted) return;
    setState(() { _loading = true; _results = null; });
    // Capture provider ref BEFORE the await so context is never used post-async
    final prov = context.read<MilkEntryProvider>();
    final data = await prov.getCustomerPriceReport(_from, _to);
    if (!mounted) return;
    setState(() { _results = data; _loading = false; });
  }

  Future<void> _pickDate(bool isFrom) async {
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
      _period  = _PricePeriod.custom;
      _results = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filter panel ────────────────────────────────────────────────
        Container(
          color: Colors.blue.shade50,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Period quick-select chips
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _PeriodChip(label: 'Today',
                      selected: _period == _PricePeriod.today,
                      onTap: () { _applyPeriod(_PricePeriod.today); _generate(); }),
                  _PeriodChip(label: 'This Week',
                      selected: _period == _PricePeriod.thisWeek,
                      onTap: () { _applyPeriod(_PricePeriod.thisWeek); _generate(); }),
                  _PeriodChip(label: 'This Month',
                      selected: _period == _PricePeriod.thisMonth,
                      onTap: () { _applyPeriod(_PricePeriod.thisMonth); _generate(); }),
                  _PeriodChip(label: 'Last 30 Days',
                      selected: _period == _PricePeriod.last30,
                      onTap: () { _applyPeriod(_PricePeriod.last30); _generate(); }),
                  _PeriodChip(label: 'Custom',
                      selected: _period == _PricePeriod.custom,
                      onTap: () => setState(() => _period = _PricePeriod.custom)),
                ],
              ),
              const SizedBox(height: 10),
              // Date pickers
              Row(children: [
                Expanded(
                  child: _DateCard(
                    label: 'From',
                    date: _from,
                    dateFmt: _dateFmt,
                    onTap: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateCard(
                    label: 'To',
                    date: _to,
                    dateFmt: _dateFmt,
                    onTap: () => _pickDate(false),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _generate,
                  icon: const Icon(Icons.price_change),
                  label: const Text('Generate Price Report',
                      style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),

        // ── Results ──────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _results == null
                  ? const Center(
                      child: Text(
                        'Select a period and tap Generate.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : _results!.isEmpty
                      ? const Center(
                          child: Text(
                            'No milk entries in this period.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : _buildResults(),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final rows    = _results!;
    final grandQty = rows.fold<double>(
        0, (s, r) => s + (r['total_quantity'] as num).toDouble());
    final grandAmt = rows.fold<double>(
        0, (s, r) => s + (r['total_amount'] as num).toDouble());
    final overallAvg =
        grandQty > 0 ? (grandAmt / grandQty) : 0.0;

    return Column(
      children: [
        // Grand summary strip
        Container(
          color: Colors.blue.shade700,
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MiniStat(
                  label: 'Farmers', value: '${rows.length}'),
              _MiniStat(
                  label: 'Total Qty',
                  value: '${grandQty.toStringAsFixed(2)} L'),
              _MiniStat(
                  label: 'Total Paid',
                  value: 'INR ${_currFmt.format(grandAmt)}'),
              // Highlighted Avg ₹/L badge
              Column(
                children: [
                  const Text('Avg ₹/L',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade400,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '₹${overallAvg.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Column header
        Container(
          color: Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Expanded(
                flex: 3,
                child: Text('Farmer',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),
              Expanded(
                flex: 2,
                child: Text('Qty (L)',
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.bold, color: Colors.grey),
                    textAlign: TextAlign.right),
              ),
              Expanded(
                flex: 2,
                child: Text('Amount',
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.bold, color: Colors.grey),
                    textAlign: TextAlign.right),
              ),
              Expanded(
                flex: 2,
                child: Text('Avg ₹/L',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade700),
                    textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Farmer rows
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r    = rows[i];
              final name = (r['customer_name'] as String?) ?? '—';
              final qty  = (r['total_quantity'] as num).toDouble();
              final amt  = (r['total_amount'] as num).toDouble();
              final avgP = (r['avg_price_per_litre'] as num).toDouble();
              final days = (r['days_count'] as int?) ?? 0;
              final ents = (r['entry_count'] as int?) ?? 0;

              // Colour-code avg price relative to grand avg
              final isHigh = avgP > overallAvg * 1.05;
              final isLow  = avgP < overallAvg * 0.95;
              final priceColor = isHigh
                  ? Colors.red.shade700   // paying more than avg
                  : isLow
                      ? Colors.green.shade700  // paying less than avg
                      : Colors.teal.shade700;  // near avg

              return ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.blue.shade800),
                  ),
                ),
                title: Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                // qty + amount on line 1, days + entries on line 2
                subtitle: Text(
                  '${qty.toStringAsFixed(2)} L · INR ${_currFmt.format(amt)}\n'
                  '$days days · $ents entries',
                  style: const TextStyle(fontSize: 11),
                ),
                isThreeLine: true,
                // trailing is ONLY the badge — no Column, no overflow
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: priceColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: priceColor.withValues(alpha: 0.5),
                        width: 1.2),
                  ),
                  child: Text(
                    '₹${avgP.toStringAsFixed(2)}/L',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: priceColor),
                  ),
                ),
              );
            },
          ),
        ),

        // Footer note
        Container(
          color: Colors.teal.shade50,
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 14, color: Colors.teal.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Overall avg: ₹${overallAvg.toStringAsFixed(2)}/L  '
                  '· 🔴 above avg  · 🟢 below avg  · 🔵 near avg',
                  style: TextStyle(
                      fontSize: 11, color: Colors.teal.shade700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Edit Invoice Dialog (used from Reports Customer tab)
//  Proper StatefulWidget — avoids StatefulBuilder context corruption crash
// ═══════════════════════════════════════════════════════════════════════════

class _ReportEditInvoiceDialog extends StatefulWidget {
  final Invoice invoice;
  const _ReportEditInvoiceDialog({required this.invoice});

  @override
  State<_ReportEditInvoiceDialog> createState() =>
      _ReportEditInvoiceDialogState();
}

class _ReportEditInvoiceDialogState
    extends State<_ReportEditInvoiceDialog> {
  late final TextEditingController _extraCtrl;
  late final TextEditingController _noteCtrl;
  bool _saving = false;

  final _currFmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _extraCtrl = TextEditingController(
        text: widget.invoice.extraAmount == 0
            ? ''
            : widget.invoice.extraAmount.toStringAsFixed(2));
    _noteCtrl =
        TextEditingController(text: widget.invoice.adjustmentNote ?? '');
  }

  @override
  void dispose() {
    _extraCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _newExtra => double.tryParse(_extraCtrl.text.trim()) ?? 0.0;

  double get _newTotal =>
      (widget.invoice.milkAmount - widget.invoice.discount + _newExtra)
          .roundToDouble();

  Future<void> _save() async {
    setState(() => _saving = true);
    // Read context.read() BEFORE any await
    final invProv = context.read<InvoiceProvider>();
    // updateAdjustments reads milk_amount + discount fresh from DB —
    // the auto-computed discount is never overwritten by stale in-memory data.
    final ok = await invProv.updateAdjustments(
      id: widget.invoice.id!,
      extraAmount: _newExtra,
      adjustmentNote:
          _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) await invProv.silentLoadAll(); // no spinner → card states preserved
    if (!mounted) return;

    // Find the freshly-loaded invoice so the caller can update its local state
    Invoice? updated;
    if (ok) {
      try {
        updated = invProv.invoices
            .firstWhere((inv) => inv.id == widget.invoice.id);
      } catch (_) {}
    }

    Navigator.of(context).pop(updated);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to update invoice.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.edit, size: 20),
        SizedBox(width: 8),
        Text('Edit Invoice', style: TextStyle(fontSize: 17)),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Read-only summary
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(children: [
                  _infoRow('Invoice', inv.invoiceNumber, Colors.blueGrey),
                  const SizedBox(height: 4),
                  _infoRow(
                    'Milk Amount',
                    'INR ${_currFmt.format(inv.milkAmount)}',
                    Colors.blue.shade700,
                  ),
                  if (inv.discount > 0) ...[
                    const SizedBox(height: 4),
                    _infoRow(
                      'Items Deduction',
                      '−INR ${_currFmt.format(inv.discount)}',
                      Colors.red.shade700,
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 14),

              // Editable: Extra Amount
              TextField(
                controller: _extraCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Extra Amount (+)',
                  labelStyle: TextStyle(color: Colors.green.shade700),
                  hintText: 'Bonus added to total',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: Icon(Icons.add_circle_outline,
                      size: 20, color: Colors.green.shade700),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),

              // Editable: Note
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note / Reason',
                  hintText: 'e.g. Adjustment reason…',
                  prefixIcon: Icon(Icons.notes, size: 20),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),

              // Recalculated total preview
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('New Total',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800)),
                    Text(
                      'INR ${_currFmt.format(_newTotal)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.green.shade800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }

  static Widget _infoRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EntryChip extends StatelessWidget {
  final String text;
  final bool faint;
  final Color? color;
  const _EntryChip(this.text, {this.faint = false, this.color});

  @override
  Widget build(BuildContext context) {
    final bgColor = color != null
        ? color!.withValues(alpha: 0.12)
        : faint
            ? Colors.grey.shade100
            : Colors.blue.shade50;
    final textColor = color != null
        ? color!
        : faint
            ? Colors.grey.shade500
            : Colors.blue.shade800;

    return Container(
      margin: const EdgeInsets.only(right: 4, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              color: textColor,
              fontWeight: color != null ? FontWeight.w600 : FontWeight.normal)),
    );
  }
}
