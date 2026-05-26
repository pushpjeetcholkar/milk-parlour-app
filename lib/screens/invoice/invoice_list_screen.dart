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

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InvoiceProvider>().loadAll();
      context.read<CustomerProvider>().loadAll();
    });
  }

  // ── Generate Invoice dialog ────────────────────────────────────────────────
  Future<void> _generateInvoice() async {
    final custProv = context.read<CustomerProvider>();
    Customer? selectedCustomer;
    DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
    DateTime to = DateTime.now();

    // Adjustment controllers
    final discountCtrl = TextEditingController(text: '0');
    final extraCtrl    = TextEditingController(text: '0');
    final noteCtrl     = TextEditingController();
    bool showAdj       = false; // controls ExpansionTile open state

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Generate Invoice'),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Customer picker ───────────────────────────────────────
                DropdownButtonFormField<Customer>(
                  value: selectedCustomer,
                  decoration: const InputDecoration(
                    labelText: 'Select Customer',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: custProv.allCustomers
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c.name)))
                      .toList(),
                  onChanged: (c) =>
                      setDialogState(() => selectedCustomer = c),
                ),
                const SizedBox(height: 10),

                // ── Date pickers ──────────────────────────────────────────
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('From: ${_dateFmt.format(from)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: from,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setDialogState(() => from = d);
                  },
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('To: ${_dateFmt.format(to)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: to,
                      firstDate: from,
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setDialogState(() => to = d);
                  },
                ),

                const Divider(height: 20),

                // ── Adjustments (expandable) ──────────────────────────────
                Theme(
                  // Remove default indent so it aligns with the rest
                  data: Theme.of(ctx)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: showAdj,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: Row(
                      children: [
                        Icon(Icons.tune,
                            size: 18,
                            color: Theme.of(ctx).colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Adjustments / Remarks',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(optional)',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    onExpansionChanged: (v) =>
                        setDialogState(() => showAdj = v),
                    children: [
                      // Extra amount field (bonus to add)
                      _adjField(
                        controller: extraCtrl,
                        label: 'Extra Amount  (+)',
                        hint: 'e.g. 50 (bonus added to total)',
                        icon: Icons.add_circle_outline,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(height: 10),

                      // Discount field (deduction)
                      _adjField(
                        controller: discountCtrl,
                        label: 'Discount  (−)',
                        hint: 'e.g. 20 (deducted from total)',
                        icon: Icons.remove_circle_outline,
                        color: Colors.red.shade700,
                      ),
                      const SizedBox(height: 10),

                      // Note / comment field
                      TextField(
                        controller: noteCtrl,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Note / Reason',
                          hintText: 'e.g. Diwali bonus, advance adjusted…',
                          prefixIcon: const Icon(Icons.notes, size: 20),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedCustomer == null) return;
                final extra    = double.tryParse(extraCtrl.text) ?? 0;
                final discount = double.tryParse(discountCtrl.text) ?? 0;
                final note     = noteCtrl.text.trim();
                Navigator.pop(ctx);
                await _createInvoice(
                  selectedCustomer!,
                  from,
                  to,
                  extraAmount: extra,
                  discount: discount,
                  adjustmentNote: note.isEmpty ? null : note,
                );
              },
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );

    discountCtrl.dispose();
    extraCtrl.dispose();
    noteCtrl.dispose();
  }

  /// A labelled number-input for the adjustments section.
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
        border: OutlineInputBorder(
          borderSide: BorderSide(color: color),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: color, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  // ── Create & save invoice ──────────────────────────────────────────────────
  Future<void> _createInvoice(
    Customer customer,
    DateTime from,
    DateTime to, {
    double extraAmount = 0,
    double discount = 0,
    String? adjustmentNote,
  }) async {
    final milkProv = context.read<MilkEntryProvider>();
    final invProv  = context.read<InvoiceProvider>();

    final List<MilkEntry> entries =
        await milkProv.getByCustomerAndDateRange(customer.id!, from, to);

    if (entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No milk entries found for the selected period.')),
        );
      }
      return;
    }

    final totalQty    = entries.fold<double>(0, (s, e) => s + e.quantity);
    final totalKgFat  = entries.fold<double>(0, (s, e) => s + e.kgFat);
    final milkAmount  = entries.fold<double>(0, (s, e) => s + e.amount);
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

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePreviewScreen(
          invoice: saved,
          entries: entries,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: Consumer<InvoiceProvider>(
        builder: (context, prov, _) {
          if (prov.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (prov.invoices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No invoices yet.',
                      style: TextStyle(color: Colors.grey)),
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
          return ListView.builder(
            itemCount: prov.invoices.length,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemBuilder: (context, i) {
              final inv    = prov.invoices[i];
              final hasPdf =
                  inv.pdfPath != null && File(inv.pdfPath!).existsSync();
              final hasAdj =
                  inv.discount > 0 || inv.extraAmount > 0;

              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (hasPdf) OpenFile.open(inv.pdfPath!);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Row 1: Invoice badge + Final amount ────────────
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.receipt_long,
                                      size: 14, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    inv.invoiceNumber,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'INR ${_currFmt.format(inv.totalAmount)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // ── Row 2: Customer name ───────────────────────────
                        Row(
                          children: [
                            const Icon(Icons.person,
                                size: 16, color: Colors.blueGrey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                inv.customerName ?? '—',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // ── Row 3: Date range + KG FAT ─────────────────────
                        Row(
                          children: [
                            const Icon(Icons.date_range,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${_dateFmt.format(inv.fromDate)}  →  ${_dateFmt.format(inv.toDate)}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                border: Border.all(
                                    color: Colors.orange.shade300),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${inv.totalKgFat.toStringAsFixed(2)} KG FAT',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── Row 4: Adjustment summary (only if any adj) ────
                        if (hasAdj) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (inv.extraAmount > 0)
                                _adjChip(
                                  '+${_currFmt.format(inv.extraAmount)}',
                                  Colors.green,
                                  Icons.add_circle_outline,
                                ),
                              if (inv.extraAmount > 0 && inv.discount > 0)
                                const SizedBox(width: 6),
                              if (inv.discount > 0)
                                _adjChip(
                                  '−${_currFmt.format(inv.discount)}',
                                  Colors.red,
                                  Icons.remove_circle_outline,
                                ),
                              if (inv.adjustmentNote != null &&
                                  inv.adjustmentNote!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    inv.adjustmentNote!,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],

                        // ── Row 5: PDF action buttons ──────────────────────
                        if (hasPdf) ...[
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  border: Border.all(
                                      color: Colors.red.shade300),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.picture_as_pdf,
                                        size: 14,
                                        color: Colors.red.shade700),
                                    const SizedBox(width: 4),
                                    Text('PDF',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade700,
                                        )),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue.shade700,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon:
                                    const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Open',
                                    style: TextStyle(fontSize: 13)),
                                onPressed: () =>
                                    OpenFile.open(inv.pdfPath!),
                              ),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.teal.shade700,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.share, size: 16),
                                label: const Text('Share',
                                    style: TextStyle(fontSize: 13)),
                                onPressed: () =>
                                    PdfService.sharePdf(inv.pdfPath!),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
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

  Widget _adjChip(String label, MaterialColor color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.shade700),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color.shade700),
          ),
        ],
      ),
    );
  }
}
