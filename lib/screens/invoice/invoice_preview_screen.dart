import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../models/invoice.dart';
import '../../models/milk_entry.dart';
import '../../providers/invoice_provider.dart';
import '../../services/pdf_service.dart';

class InvoicePreviewScreen extends StatefulWidget {
  final Invoice invoice;
  final List<MilkEntry> entries;

  const InvoicePreviewScreen({
    super.key,
    required this.invoice,
    required this.entries,
  });

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  bool _generating = false;
  String? _pdfPath;
  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    setState(() => _generating = true);
    try {
      final path = await PdfService.generateInvoicePdf(
        invoice: widget.invoice,
        entries: widget.entries,
      );
      setState(() => _pdfPath = path);

      if (widget.invoice.id != null && mounted) {
        await context
            .read<InvoiceProvider>()
            .updatePdfPath(widget.invoice.id!, path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _openPdf() async {
    if (_pdfPath == null) return;
    final result = await OpenFile.open(_pdfPath!);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot open PDF: ${result.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice ${widget.invoice.invoiceNumber}'),
        actions: [
          if (_pdfPath != null) ...[
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Open PDF',
              onPressed: _openPdf,
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share / WhatsApp',
              onPressed: () => PdfService.sharePdf(_pdfPath!),
            ),
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print',
              onPressed: () => PdfService.printPdf(_pdfPath!),
            ),
          ],
        ],
      ),
      body: _generating
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating PDF…'),
                ],
              ),
            )
          : _pdfPath != null
              ? PdfPreview(
                  build: (_) => File(_pdfPath!).readAsBytes(),
                  canChangePageFormat: false,
                  allowPrinting: true,
                  allowSharing: true,
                )
              : _buildFallbackView(),
      bottomNavigationBar: _pdfPath != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openPdf,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open PDF'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => PdfService.printPdf(_pdfPath!),
                        icon: const Icon(Icons.print),
                        label: const Text('Print'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => PdfService.sharePdf(_pdfPath!),
                        icon: const Icon(Icons.share),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildFallbackView() {
    final entries = widget.entries;
    final totalKgFat =
        entries.fold<double>(0, (s, e) => s + e.kgFat);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Text('Hemant Kumawat Milk Center',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Text('Khargone, Madhya Pradesh'),
                const Text('Mobile: 9993991979'),
              ],
            ),
          ),
          const Divider(thickness: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Customer: ${widget.invoice.customerName ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Invoice: ${widget.invoice.invoiceNumber}'),
            ],
          ),
          Text(
              'Period: ${_dateFmt.format(widget.invoice.fromDate)} - ${_dateFmt.format(widget.invoice.toDate)}'),
          const SizedBox(height: 12),
          _tableRow(
              ['Date', 'Shift', 'Qty', 'CLR', 'FAT', 'Rate', 'KGFAT', 'Amount'],
              isHeader: true),
          const Divider(),
          ...entries.map((e) => _tableRow([
                _dateFmt.format(e.date),
                e.shift,
                e.quantity.toStringAsFixed(2),
                e.clr.toStringAsFixed(2),
                e.fat.toStringAsFixed(2),
                e.rate.toStringAsFixed(2),
                e.kgFat.toStringAsFixed(4),
                'INR${_currFmt.format(e.amount)}',
              ])),
          const Divider(thickness: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Total KG FAT: ${totalKgFat.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  'Total Payable: INR ${_currFmt.format(widget.invoice.totalAmount)}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(List<String> cells, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: cells
            .map((c) => Expanded(
                  child: Text(
                    c,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isHeader ? FontWeight.bold : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ))
            .toList(),
      ),
    );
  }
}
