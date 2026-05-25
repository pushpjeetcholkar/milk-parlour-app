import 'dart:io';
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

  // ── Font loader ────────────────────────────────────────────────────────────
  // Noto Sans supports INR (Rupee sign U+20B9) unlike the built-in PDF fonts.
  // PdfGoogleFonts downloads once and caches on-device for offline use.
  static Future<pw.ThemeData> _buildTheme() async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold    = await PdfGoogleFonts.notoSansBold();
    final italic  = await PdfGoogleFonts.notoSansItalic();
    return pw.ThemeData.withFont(
      base:   regular,
      bold:   bold,
      italic: italic,
    );
  }

  // ── Main entry point ───────────────────────────────────────────────────────
  static Future<String> generateInvoicePdf({
    required Invoice invoice,
    required List<MilkEntry> entries,
  }) async {
    final theme = await _buildTheme();
    final pdf   = pw.Document(theme: theme);

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

    final dir      = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/invoice_${invoice.invoiceNumber}.pdf';
    final file     = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return filePath;
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  static pw.Widget _buildHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          AppConstants.firmName,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(AppConstants.firmLocation,
            style: pw.TextStyle(fontSize: 12),
            textAlign: pw.TextAlign.center),
        pw.Text('Mobile: ${AppConstants.firmMobile}',
            style: pw.TextStyle(fontSize: 12),
            textAlign: pw.TextAlign.center),
        pw.Divider(thickness: 1.5),
      ],
    );
  }

  // ── Invoice Info ───────────────────────────────────────────────────────────
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
                'Period: ${_dateFormat.format(invoice.fromDate)}'
                ' - ${_dateFormat.format(invoice.toDate)}',
                style: pw.TextStyle(fontSize: 11)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Invoice #: ${invoice.invoiceNumber}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Date: ${_dateFormat.format(invoice.createdAt)}',
                style: pw.TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }

  // ── Entries Table ──────────────────────────────────────────────────────────
  static pw.Widget _buildEntriesTable(List<MilkEntry> entries) {
    const headers = [
      'Date', 'Shift', 'Qty (L)', 'CLR', 'FAT %', 'Rate', 'KG FAT', 'Amount (INR)'
    ];
    final columnWidths = {
      0: const pw.FlexColumnWidth(2.0),
      1: const pw.FlexColumnWidth(1.3),
      2: const pw.FlexColumnWidth(1.3),
      3: const pw.FlexColumnWidth(1.0),
      4: const pw.FlexColumnWidth(1.0),
      5: const pw.FlexColumnWidth(1.2),
      6: const pw.FlexColumnWidth(1.4),
      7: const pw.FlexColumnWidth(2.0),
    };

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue100),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(
                      h,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 8),
                      textAlign: pw.TextAlign.center,
                    ),
                  ))
              .toList(),
        ),
        // Data rows
        ...entries.map(
          (e) => pw.TableRow(
            children: [
              _cell(_dateFormat.format(e.date)),
              _cell(e.shift),
              _cell(e.quantity.toStringAsFixed(2)),
              _cell(e.clr.toStringAsFixed(2)),
              _cell(e.fat.toStringAsFixed(2)),
              _cell(e.rate.toStringAsFixed(2)),
              _cell(e.kgFat.toStringAsFixed(4)),
              _cell('INR ${_currencyFormat.format(e.amount)}'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _cell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 9),
          textAlign: pw.TextAlign.center,
        ),
      );

  // ── Totals ─────────────────────────────────────────────────────────────────
  static pw.Widget _buildTotals(Invoice invoice) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: PdfColors.blue50,
          border: pw.Border.all(color: PdfColors.blue200),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Total Quantity: ${invoice.totalQuantity.toStringAsFixed(2)} L',
              style: pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Total KG FAT: ${invoice.totalKgFat.toStringAsFixed(4)}',
              style: pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: PdfColors.blue200),
            pw.SizedBox(height: 6),
            pw.Text(
              'Total Payable: INR ${_currencyFormat.format(invoice.totalAmount)}',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Signature Area ─────────────────────────────────────────────────────────
  static pw.Widget _buildSignatureArea() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 48),
            pw.Container(width: 130, height: 1, color: PdfColors.black),
            pw.SizedBox(height: 4),
            pw.Text('Customer Signature',
                style: pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(height: 48),
            pw.Container(width: 130, height: 1, color: PdfColors.black),
            pw.SizedBox(height: 4),
            pw.Text('Authorized Signature',
                style: pw.TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }

  // ── Print & Share ──────────────────────────────────────────────────────────
  static Future<void> printPdf(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static Future<void> sharePdf(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'Invoice from ${AppConstants.firmName}',
    );
  }
}
