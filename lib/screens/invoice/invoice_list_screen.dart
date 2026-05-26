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

  Future<void> _generateInvoice() async {
    // Step 1: Select customer
    final custProv = context.read<CustomerProvider>();
    Customer? selectedCustomer;
    DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
    DateTime to = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Generate Invoice'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Customer>(
                value: selectedCustomer,
                decoration: const InputDecoration(
                  labelText: 'Select Customer',
                  border: OutlineInputBorder(),
                ),
                items: custProv.allCustomers
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (c) => setDialogState(() => selectedCustomer = c),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text('From: ${_dateFmt.format(from)}'),
                trailing: const Icon(Icons.calendar_today),
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
                title: Text('To: ${_dateFmt.format(to)}'),
                trailing: const Icon(Icons.calendar_today),
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
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (selectedCustomer == null) return;
                Navigator.pop(ctx);
                await _createInvoice(selectedCustomer!, from, to);
              },
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createInvoice(
      Customer customer, DateTime from, DateTime to) async {
    final milkProv = context.read<MilkEntryProvider>();
    final invProv = context.read<InvoiceProvider>();

    // Fetch entries for the date range
    final List<MilkEntry> entries = await milkProv.getByCustomerAndDateRange(
        customer.id!, from, to);

    if (entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('No milk entries found for the selected period.')),
        );
      }
      return;
    }

    final totalQty =
        entries.fold<double>(0, (sum, e) => sum + e.quantity);
    final totalKgFat =
        entries.fold<double>(0, (sum, e) => sum + e.kgFat);
    final totalAmount =
        entries.fold<double>(0, (sum, e) => sum + e.amount);
    final invoiceNumber = await InvoiceNumberGenerator.next();

    final invoice = Invoice(
      invoiceNumber: invoiceNumber,
      customerId: customer.id!,
      customerName: customer.name,
      fromDate: from,
      toDate: to,
      totalQuantity: totalQty,
      totalKgFat: totalKgFat,
      totalAmount: totalAmount,
      createdAt: DateTime.now(),
    );

    final saved = await invProv.save(invoice);
    if (saved == null || !mounted) return;

    // Navigate to preview
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
                  const Icon(Icons.receipt_long,
                      size: 64, color: Colors.grey),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemBuilder: (context, i) {
              final inv = prov.invoices[i];
              final hasPdf =
                  inv.pdfPath != null && File(inv.pdfPath!).existsSync();

              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    // Tap card to open PDF if available
                    if (hasPdf) OpenFile.open(inv.pdfPath!);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Row 1: Invoice number badge + Amount ──────────
                        Row(
                          children: [
                            // Blue invoice number badge
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
                            // Green amount chip
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

                        // ── Row 2: Customer name ──────────────────────────
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
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // ── Row 3: Date range + KG FAT ───────────────────
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

                        // ── Row 4: PDF action buttons (only if PDF exists) ─
                        if (hasPdf) ...[
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              // PDF file chip
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
                                    Text(
                                      'PDF',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              // Open button
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue.shade700,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Open',
                                    style: TextStyle(fontSize: 13)),
                                onPressed: () => OpenFile.open(inv.pdfPath!),
                              ),
                              const SizedBox(width: 4),
                              // Share button
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
}
