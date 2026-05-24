import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../core/constants/app_constants.dart';
import '../models/invoice.dart';
import '../models/milk_entry.dart';

class PdfService {
  static final _dateFormat = DateFormat('dd/MM/yyyy');
  static final _currencyFormat = NumberFormat('#,##0.00');

  static Future<String> generateInvoicePdf({
    required Invoice invoice,
    required List<MilkEntry> entries,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(),
          pw.SizedBox(height: 12),
          _buildInvoiceInfo(invoice),
          pw.SizedBox(height: 12),
          _buildEntriesTable(entries),
          pw.SizedBox(height: 16),
          _buildTotals(invoice),
          pw.SizedBox(height: 32),
          _buildSignatureArea(),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final filePath =
        '${dir.path}/invoice_${invoice.invoiceNumber}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return filePath;
  }

  static pw.Widget _buildHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          AppConstants.firmName,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          AppConstants.firmLocation,
          style: const pw.TextStyle(fontSize: 12),
          textAlign: pw.TextAlign.center,
        ),
        pw.Text(
          'Mobile: ${AppConstants.firmMobile}',
          style: const pw.TextStyle(fontSize: 12),
          textAlign: pw.TextAlign.center,
        ),
        pw.Divider(thickness: 1.5),
      ],
    );
  }

  static pw.Widget _buildInvoiceInfo(Invoice invoice) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Customer: ${invoice.customerName ?? ''}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(
                'Period: ${_dateFormat.format(invoice.fromDate)} - ${_dateFormat.format(invoice.toDate)}'),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Invoice #: ${invoice.invoiceNumber}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Date: ${_dateFormat.format(invoice.createdAt)}'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildEntriesTable(List<MilkEntry> entries) {
    const headers = ['Date', 'Qty (L)', 'CLR', 'FAT %', 'Rate', 'KG FAT', 'Amount'];
    final columnWidths = {
      0: const pw.FlexColumnWidth(2),
      1: const pw.FlexColumnWidth(1.5),
      2: const pw.FlexColumnWidth(1.2),
      3: const pw.FlexColumnWidth(1.2),
      4: const pw.FlexColumnWidth(1.5),
      5: const pw.FlexColumnWidth(1.5),
      6: const pw.FlexColumnWidth(2),
    };

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue100),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(h,
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 10),
                        textAlign: pw.TextAlign.center),
                  ))
              .toList(),
        ),
        // Rows
        ...entries.map(
          (e) => pw.TableRow(
            children: [
              _cell(_dateFormat.format(e.date)),
              _cell(e.quantity.toStringAsFixed(2)),
              _cell(e.clr.toStringAsFixed(2)),
              _cell(e.fat.toStringAsFixed(2)),
              _cell(e.rate.toStringAsFixed(2)),
              _cell(e.kgFat.toStringAsFixed(4)),
              _cell('₹ ${_currencyFormat.format(e.amount)}'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _cell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(text,
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.center),
      );

  static pw.Widget _buildTotals(Invoice invoice) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.blue50,
          border: pw.Border.all(color: PdfColors.blue200),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
                'Total Qty: ${invoice.totalQuantity.toStringAsFixed(2)} L'),
            pw.SizedBox(height: 4),
            pw.Text(
              'Total Payable: ₹ ${_currencyFormat.format(invoice.totalAmount)}',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildSignatureArea() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 40),
            pw.Container(width: 120, height: 1, color: PdfColors.black),
            pw.Text('Customer Signature', style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(height: 40),
            pw.Container(width: 120, height: 1, color: PdfColors.black),
            pw.Text('Authorized Signature', style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }

  /// Print the PDF
  static Future<void> printPdf(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  /// Share via WhatsApp / any app
  static Future<void> sharePdf(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'Invoice from ${AppConstants.firmName}',
    );
  }
}
