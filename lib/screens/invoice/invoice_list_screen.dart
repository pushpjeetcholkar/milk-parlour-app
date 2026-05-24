import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
    final entries = await milkProv.getByCustomerAndDateRange(
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
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, i) {
              final inv = prov.invoices[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.receipt, size: 20),
                  ),
                  title: Text(inv.invoiceNumber,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      '${inv.customerName ?? '—'}\n${_dateFmt.format(inv.fromDate)} - ${_dateFmt.format(inv.toDate)}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹ ${_currFmt.format(inv.totalAmount)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                            fontSize: 15),
                      ),
                      if (inv.pdfPath != null &&
                          File(inv.pdfPath!).existsSync())
                        IconButton(
                          icon: const Icon(Icons.share, size: 20),
                          onPressed: () =>
                              PdfService.sharePdf(inv.pdfPath!),
                          tooltip: 'Share PDF',
                        ),
                    ],
                  ),
                  isThreeLine: true,
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
