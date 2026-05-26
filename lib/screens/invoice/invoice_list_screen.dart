import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../core/utils/invoice_number_generator.dart';
import 'invoice_preview_screen.dart';

// ── Date preset ───────────────────────────────────────────────────────────────
enum _DatePreset { today, yesterday, thisWeek, thisMonth, custom }

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  /// null = "All customers"
  Customer? _filterCustomer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InvoiceProvider>().loadAll();
      context.read<CustomerProvider>().loadAll();
    });
  }

  // ── Filtered invoice list ─────────────────────────────────────────────────

  List<Invoice> _filtered(List<Invoice> all) {
    if (_filterCustomer == null) return all;
    return all.where((inv) => inv.customerId == _filterCustomer!.id).toList();
  }

  // ── Generate Invoice dialog ───────────────────────────────────────────────

  Future<void> _generateInvoice({Customer? preselectedCustomer}) async {
    final custProv = context.read<CustomerProvider>();

    // State held in dialog
    Customer? selectedCustomer = preselectedCustomer;
    _DatePreset preset = _DatePreset.today;
    DateTime from = _today();
    DateTime to   = _today();
    String? shiftFilter; // null = all shifts

    final discountCtrl = TextEditingController(text: '0');
    final extraCtrl    = TextEditingController(text: '0');
    final noteCtrl     = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void applyPreset(_DatePreset p) {
            final now = DateTime.now();
            switch (p) {
              case _DatePreset.today:
                from = to = _today();
              case _DatePreset.yesterday:
                from = to = _today().subtract(const Duration(days: 1));
              case _DatePreset.thisWeek:
                final weekday = now.weekday;
                from = _today().subtract(Duration(days: weekday - 1));
                to   = _today();
              case _DatePreset.thisMonth:
                from = DateTime(now.year, now.month, 1);
                to   = _today();
              case _DatePreset.custom:
                break; // handled by date pickers
            }
            setDialogState(() => preset = p);
          }

          return AlertDialog(
            title: const Text('Generate Invoice'),
            contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.72,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Customer picker ─────────────────────────────────
                      DropdownButtonFormField<Customer>(
                        value: selectedCustomer,
                        decoration: const InputDecoration(
                          labelText: 'Select Customer',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: custProv.allCustomers
                            .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                            .toList(),
                        onChanged: (c) => setDialogState(() => selectedCustomer = c),
                      ),
                      const SizedBox(height: 12),

                      // ── Date preset chips ────────────────────────────────
                      const Text('Date Range',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                              color: Colors.blueGrey)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6, runSpacing: 4,
                        children: [
                          _presetChip(ctx, 'Today',     _DatePreset.today,     preset, applyPreset),
                          _presetChip(ctx, 'Yesterday', _DatePreset.yesterday, preset, applyPreset),
                          _presetChip(ctx, 'This Week', _DatePreset.thisWeek,  preset, applyPreset),
                          _presetChip(ctx, 'This Month',_DatePreset.thisMonth, preset, applyPreset),
                          _presetChip(ctx, 'Custom',    _DatePreset.custom,    preset, applyPreset),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // ── Date pickers (always visible for clarity) ────────
                      Row(
                        children: [
                          Expanded(
                            child: _dateTile(
                              ctx: ctx,
                              label: 'From',
                              date: from,
                              onPicked: (d) => setDialogState(() {
                                from   = d;
                                preset = _DatePreset.custom;
                                if (to.isBefore(from)) to = from;
                              }),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('→'),
                          ),
                          Expanded(
                            child: _dateTile(
                              ctx: ctx,
                              label: 'To',
                              date: to,
                              onPicked: (d) => setDialogState(() {
                                to     = d;
                                preset = _DatePreset.custom;
                                if (from.isAfter(to)) from = to;
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Shift selector ───────────────────────────────────
                      const Text('Shift',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                              color: Colors.blueGrey)),
                      const SizedBox(height: 6),
                      SegmentedButton<String?>(
                        segments: const [
                          ButtonSegment(value: null,       label: Text('All'),     icon: Icon(Icons.all_inclusive, size: 14)),
                          ButtonSegment(value: 'Morning',  label: Text('Morning'), icon: Icon(Icons.wb_sunny, size: 14)),
                          ButtonSegment(value: 'Evening',  label: Text('Evening'), icon: Icon(Icons.nights_stay, size: 14)),
                        ],
                        selected: {shiftFilter},
                        onSelectionChanged: (s) =>
                            setDialogState(() => shiftFilter = s.first),
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(height: 12),

                      const Divider(height: 1),
                      const SizedBox(height: 4),

                      // ── Adjustments / Remarks ────────────────────────────
                      Theme(
                        data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          title: Row(children: [
                            Icon(Icons.tune, size: 17,
                                color: Theme.of(ctx).colorScheme.primary),
                            const SizedBox(width: 6),
                            Text('Adjustments / Remarks',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13,
                                    color: Theme.of(ctx).colorScheme.primary)),
                            const SizedBox(width: 4),
                            Text('(optional)',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          ]),
                          children: [
                            _adjField(
                              controller: extraCtrl,
                              label: 'Extra Amount  (+)',
                              hint: 'Bonus added to total',
                              icon: Icons.add_circle_outline,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(height: 10),
                            _adjField(
                              controller: discountCtrl,
                              label: 'Discount  (−)',
                              hint: 'Deducted from total',
                              icon: Icons.remove_circle_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: noteCtrl,
                              maxLines: 2,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Note / Reason',
                                hintText: 'e.g. Diwali bonus, advance adjusted…',
                                prefixIcon: Icon(Icons.notes, size: 20),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedCustomer == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Please select a customer')));
                    return;
                  }
                  final extra    = double.tryParse(extraCtrl.text) ?? 0;
                  final discount = double.tryParse(discountCtrl.text) ?? 0;
                  final note     = noteCtrl.text.trim();
                  Navigator.pop(ctx);
                  await _createInvoice(
                    selectedCustomer!,
                    from, to,
                    shift: shiftFilter,
                    extraAmount: extra,
                    discount: discount,
                    adjustmentNote: note.isEmpty ? null : note,
                  );
                },
                child: const Text('Generate'),
              ),
            ],
          );
        },
      ),
    );

    discountCtrl.dispose();
    extraCtrl.dispose();
    noteCtrl.dispose();
  }

  // ── Preset chip helper ────────────────────────────────────────────────────

  Widget _presetChip(
    BuildContext ctx,
    String label,
    _DatePreset p,
    _DatePreset current,
    void Function(_DatePreset) onTap,
  ) {
    final selected = current == p;
    return GestureDetector(
      onTap: () => onTap(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Theme.of(ctx).colorScheme.primary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Theme.of(ctx).colorScheme.primary
                : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  // ── Date tile helper ──────────────────────────────────────────────────────

  Widget _dateTile({
    required BuildContext ctx,
    required String label,
    required DateTime date,
    required void Function(DateTime) onPicked,
  }) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: ctx,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (d != null) onPicked(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Text(_dateFmt.format(date),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Adjustment field helper ───────────────────────────────────────────────

  Widget _adjField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12),
        prefixIcon: Icon(icon, size: 20, color: color),
        border: OutlineInputBorder(borderSide: BorderSide(color: color)),
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: color, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  // ── Create & save invoice ─────────────────────────────────────────────────

  Future<void> _createInvoice(
    Customer customer,
    DateTime from,
    DateTime to, {
    String? shift,
    double extraAmount = 0,
    double discount = 0,
    String? adjustmentNote,
  }) async {
    final milkProv = context.read<MilkEntryProvider>();
    final invProv  = context.read<InvoiceProvider>();

    final List<MilkEntry> entries = await milkProv.getByCustomerAndDateRange(
        customer.id!, from, to, shift: shift);

    if (entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(shift != null
              ? 'No $shift entries found for the selected period.'
              : 'No milk entries found for the selected period.'),
        ));
      }
      return;
    }

    final totalQty   = entries.fold<double>(0, (s, e) => s + e.quantity);
    final totalKgFat = entries.fold<double>(0, (s, e) => s + e.kgFat);
    final milkAmount = entries.fold<double>(0, (s, e) => s + e.amount);
    final totalAmount = milkAmount + extraAmount - discount;
    final invoiceNumber = await InvoiceNumberGenerator.next();

    final invoice = Invoice(
      invoiceNumber: invoiceNumber,
      customerId: customer.id!,
      customerName: customer.name,
      fromDate: from,
      toDate: to,
      totalQuantity: totalQty,
      totalKgFat: totalKgFat,
      milkAmount: milkAmount,
      extraAmount: extraAmount,
      discount: discount,
      adjustmentNote: adjustmentNote,
      totalAmount: totalAmount,
      createdAt: DateTime.now(),
    );

    final saved = await invProv.save(invoice);
    if (saved == null || !mounted) return;

    // Refresh pending after saving
    await invProv.refreshPending();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePreviewScreen(invoice: saved, entries: entries),
      ),
    );
  }

  // ── Date helpers ──────────────────────────────────────────────────────────

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: Consumer2<InvoiceProvider, CustomerProvider>(
        builder: (context, invProv, custProv, _) {
          if (invProv.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          final customers   = custProv.allCustomers;
          final allInvoices = invProv.invoices;
          final filtered    = _filtered(allInvoices);
          final pending     = invProv.pendingCustomers;

          return Column(
            children: [
              // ── Customer filter bar ─────────────────────────────────────
              if (customers.isNotEmpty)
                _CustomerFilterBar(
                  customers: customers,
                  selected: _filterCustomer,
                  onSelect: (c) => setState(() => _filterCustomer = c),
                ),

              // ── Pending invoice banner ──────────────────────────────────
              if (pending.isNotEmpty)
                _PendingBanner(
                  pending: pending,
                  customers: customers,
                  onGenerate: (c) => _generateInvoice(preselectedCustomer: c),
                ),

              // ── Invoice list ────────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmpty(allInvoices.isEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) =>
                            _InvoiceCard(inv: filtered[i], currFmt: _currFmt, dateFmt: _dateFmt),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generateInvoice,
        icon: const Icon(Icons.add),
        label: const Text('New Invoice'),
      ),
    );
  }

  Widget _buildEmpty(bool noInvoicesAtAll) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            noInvoicesAtAll
                ? 'No invoices yet.'
                : 'No invoices for ${_filterCustomer?.name ?? 'this customer'}.',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _generateInvoice,
            icon: const Icon(Icons.add),
            label: const Text('Generate Invoice'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Customer filter bar
// ═══════════════════════════════════════════════════════════════════════════

class _CustomerFilterBar extends StatelessWidget {
  final List<Customer> customers;
  final Customer? selected;
  final void Function(Customer?) onSelect;

  const _CustomerFilterBar({
    required this.customers,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: Colors.blue.shade50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: [
          // "All" chip
          _FilterChip(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          ...customers.map((c) => Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _FilterChip(
              label: c.name.split(' ').first,
              selected: selected?.id == c.id,
              onTap: () => onSelect(selected?.id == c.id ? null : c),
            ),
          )),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.blue.shade700 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Pending invoice banner
// ═══════════════════════════════════════════════════════════════════════════

class _PendingBanner extends StatefulWidget {
  final List<Map<String, dynamic>> pending;
  final List<Customer> customers;
  final void Function(Customer?) onGenerate;

  const _PendingBanner({
    required this.pending,
    required this.customers,
    required this.onGenerate,
  });

  @override
  State<_PendingBanner> createState() => _PendingBannerState();
}

class _PendingBannerState extends State<_PendingBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.pending.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.amber.shade300),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$count customer${count > 1 ? 's' : ''} '
                    'ha${count > 1 ? 've' : 's'} entries not yet invoiced',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: Colors.orange.shade700,
                ),
              ]),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ...widget.pending.map((p) {
              final name   = p['customer_name'] as String? ?? '—';
              final lastDt = p['last_entry_date'] as String? ?? '';
              final qty    = (p['pending_qty'] as num?)?.toDouble() ?? 0;
              final count  = p['pending_entries'] as int? ?? 0;

              // Find matching Customer object
              Customer? matchedCustomer;
              try {
                matchedCustomer = widget.customers.firstWhere(
                  (c) => c.name == name,
                );
              } catch (_) {}

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.orange.shade100,
                  child: Text(name[0].toUpperCase(),
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800)),
                ),
                title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '$count entries · ${qty.toStringAsFixed(1)} L · last: $lastDt',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => widget.onGenerate(matchedCustomer),
                  child: const Text('Invoice', style: TextStyle(fontSize: 12)),
                ),
              );
            }),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Invoice card
// ═══════════════════════════════════════════════════════════════════════════

class _InvoiceCard extends StatelessWidget {
  final Invoice inv;
  final NumberFormat currFmt;
  final DateFormat dateFmt;

  const _InvoiceCard({required this.inv, required this.currFmt, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    final hasPdf = inv.pdfPath != null && File(inv.pdfPath!).existsSync();
    final hasAdj = inv.discount > 0 || inv.extraAmount > 0;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () { if (hasPdf) OpenFile.open(inv.pdfPath!); },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: Invoice badge + Amount ─────────────────────────
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.receipt_long, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(inv.invoiceNumber,
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('INR ${currFmt.format(inv.totalAmount)}',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ]),
              const SizedBox(height: 10),

              // ── Row 2: Customer name ──────────────────────────────────
              Row(children: [
                const Icon(Icons.person, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(inv.customerName ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 4),

              // ── Row 3: Date range + KG FAT ────────────────────────────
              Row(children: [
                const Icon(Icons.date_range, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '${dateFmt.format(inv.fromDate)}  →  ${dateFmt.format(inv.toDate)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${inv.totalKgFat.toStringAsFixed(2)} KG FAT',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800),
                  ),
                ),
              ]),

              // ── Row 4: Adjustment chips ───────────────────────────────
              if (hasAdj) ...[
                const SizedBox(height: 6),
                Row(children: [
                  if (inv.extraAmount > 0)
                    _adjChip('+${currFmt.format(inv.extraAmount)}',
                        Colors.green, Icons.add_circle_outline),
                  if (inv.extraAmount > 0 && inv.discount > 0)
                    const SizedBox(width: 6),
                  if (inv.discount > 0)
                    _adjChip('−${currFmt.format(inv.discount)}',
                        Colors.red, Icons.remove_circle_outline),
                  if (inv.adjustmentNote != null && inv.adjustmentNote!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(inv.adjustmentNote!,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ]),
              ],

              // ── Row 5: PDF action buttons ─────────────────────────────
              if (hasPdf) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 6),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.picture_as_pdf, size: 14, color: Colors.red.shade700),
                      const SizedBox(width: 4),
                      Text('PDF', style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                    ]),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open', style: TextStyle(fontSize: 13)),
                    onPressed: () => OpenFile.open(inv.pdfPath!),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.teal.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share', style: TextStyle(fontSize: 13)),
                    onPressed: () => PdfService.sharePdf(inv.pdfPath!),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _adjChip(String label, MaterialColor color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color.shade700),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.bold, color: color.shade700)),
      ]),
    );
  }
}
