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
    final hasAdj = invoice.extraAmount > 0 || invoice.discount > 0;
    final hasNote = invoice.adjustmentNote != null &&
        invoice.adjustmentNote!.trim().isNotEmpty;

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
            // Qty & KG FAT summary
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

            // Milk subtotal (always shown)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('Milk Amount:', style: pw.TextStyle(fontSize: 11)),
                pw.SizedBox(width: 8),
                pw.Text(
                  'INR ${_currencyFormat.format(invoice.milkAmount)}',
                  style: pw.TextStyle(fontSize: 11),
                ),
              ],
            ),

            // Extra amount row (only if > 0)
            if (invoice.extraAmount > 0) ...[
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text('Extra Amount (+):',
                      style: pw.TextStyle(
                          fontSize: 11, color: PdfColors.green700)),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    'INR ${_currencyFormat.format(invoice.extraAmount)}',
                    style: pw.TextStyle(
                        fontSize: 11, color: PdfColors.green700),
                  ),
                ],
              ),
            ],

            // Items Purchased row (only if > 0)
            if (invoice.discount > 0) ...[
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text('Items Purchased (−):',
                      style: pw.TextStyle(
                          fontSize: 11, color: PdfColors.red700)),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    'INR ${_currencyFormat.format(invoice.discount)}',
                    style: pw.TextStyle(
                        fontSize: 11, color: PdfColors.red700),
                  ),
                ],
              ),
            ],

            // Note (only if present)
            if (hasNote) ...[
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text('Note: ',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontStyle: pw.FontStyle.italic,
                          color: PdfColors.grey700)),
                  pw.Text(invoice.adjustmentNote!,
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontStyle: pw.FontStyle.italic,
                          color: PdfColors.grey700)),
                ],
              ),
            ],

            // Divider only if adjustments exist
            if (hasAdj) ...[
              pw.SizedBox(height: 6),
              pw.Divider(color: PdfColors.blue300),
              pw.SizedBox(height: 4),
            ] else ...[
              pw.SizedBox(height: 6),
            ],

            // Net payable — always bold & large
            pw.Text(
              'Net Payable: INR ${_currencyFormat.format(invoice.totalAmount)}',
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

  // ── Report PDF ─────────────────────────────────────────────────────────────
  static Future<String> generateReportPdf({
    required String customerName,
    required DateTime from,
    required DateTime to,
    required List<MilkEntry> entries,
    Invoice? invoice,
  }) async {
    final theme = await _buildTheme();
    final pdf   = pw.Document(theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _buildHeader(),
          pw.SizedBox(height: 10),
          _buildReportInfo(customerName, from, to, invoice),
          pw.SizedBox(height: 10),
          _buildReportTable(entries),
          pw.SizedBox(height: 14),
          _buildReportTotals(entries, invoice),
          pw.SizedBox(height: 28),
          _buildSignatureArea(),
        ],
      ),
    );

    final dir      = await getApplicationDocumentsDirectory();
    final safeName = customerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final dateStr  = DateFormat('yyyy_MM').format(from);
    final filePath = '${dir.path}/report_${safeName}_$dateStr.pdf';
    final file     = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return filePath;
  }

  // ── Report Info ────────────────────────────────────────────────────────────
  static pw.Widget _buildReportInfo(
      String customerName, DateTime from, DateTime to, Invoice? invoice) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Customer: $customerName',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(
                'Period: ${_dateFormat.format(from)} - ${_dateFormat.format(to)}',
                style: pw.TextStyle(fontSize: 11)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Report Date: ${_dateFormat.format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 11)),
            if (invoice != null) ...[
              pw.SizedBox(height: 4),
              pw.Text('Ref: ${invoice.invoiceNumber}',
                  style: pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600)),
            ],
          ],
        ),
      ],
    );
  }

  // ── Report Entries Table (12 columns) ─────────────────────────────────────
  static pw.Widget _buildReportTable(List<MilkEntry> entries) {
    const headers = [
      'Sr.', 'CID', 'Date', 'Shift\n(M/E)', 'Type\n(C/B)',
      'Qty (L)', 'FAT %', 'Rate', 'KG Fat',
      'Item Purchased', 'Deduction', 'Amount',
    ];
    final columnWidths = {
      0:  const pw.FlexColumnWidth(0.45), // Sr.
      1:  const pw.FlexColumnWidth(0.45), // CID
      2:  const pw.FlexColumnWidth(1.55), // Date
      3:  const pw.FlexColumnWidth(0.55), // Shift (M/E)
      4:  const pw.FlexColumnWidth(0.50), // Type (C/B)
      5:  const pw.FlexColumnWidth(0.80), // Qty
      6:  const pw.FlexColumnWidth(0.70), // FAT%
      7:  const pw.FlexColumnWidth(0.70), // Rate
      8:  const pw.FlexColumnWidth(0.90), // KG Fat
      9:  const pw.FlexColumnWidth(1.40), // Item Purchased
      10: const pw.FlexColumnWidth(1.00), // Deduction
      11: const pw.FlexColumnWidth(1.00), // Amount
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
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                      h,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 6.5),
                      textAlign: pw.TextAlign.center,
                    ),
                  ))
              .toList(),
        ),
        // Data rows
        ...entries.asMap().entries.map(
          (entry) {
            final idx = entry.key;
            final e   = entry.value;
            // Abbreviate shift: Morning → M, Evening → E
            final shiftAbbr = e.shift.startsWith('M') ? 'M' : 'E';
            // Abbreviate type: Cow → C, Buffalo → B, others first char
            final typeAbbr  = e.milkType.startsWith('C')
                ? 'C'
                : e.milkType.startsWith('B')
                    ? 'B'
                    : e.milkType.isNotEmpty
                        ? e.milkType[0]
                        : '';
            return pw.TableRow(
              children: [
                _smallCell('${idx + 1}'),
                _smallCell('${e.customerId}'),
                _smallCell(_dateFormat.format(e.date)),
                _smallCell(shiftAbbr),
                _smallCell(typeAbbr),
                _smallCell(e.quantity.toStringAsFixed(2)),
                _smallCell(e.fat.toStringAsFixed(2)),
                _smallCell(e.rate.toStringAsFixed(2)),
                _smallCell(e.kgFat.toStringAsFixed(3)),
                _smallCell(
                    (e.itemName != null && e.itemName!.isNotEmpty)
                        ? e.itemName!
                        : ''),
                _smallCell(
                    e.itemAmount > 0
                        ? _currencyFormat.format(e.itemAmount)
                        : ''),
                _smallCell(_currencyFormat.format(e.amount)),
              ],
            );
          },
        ),
      ],
    );
  }

  static pw.Widget _smallCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
      );

  // ── Report Totals ──────────────────────────────────────────────────────────
  static pw.Widget _buildReportTotals(
      List<MilkEntry> entries, Invoice? invoice) {
    final totalQty =
        entries.fold<double>(0, (s, e) => s + e.quantity);
    final totalKgFat =
        entries.fold<double>(0, (s, e) => s + e.kgFat);
    final totalMilkAmt =
        entries.fold<double>(0, (s, e) => s + e.amount);
    final totalItemsDeducted =
        entries.fold<double>(0, (s, e) => s + e.itemAmount);
    final extraAmount = invoice?.extraAmount ?? 0;
    final extraNote   = invoice?.adjustmentNote;
    final netPayable  =
        (totalMilkAmt + extraAmount - totalItemsDeducted).roundToDouble();
    final hasAdj = totalItemsDeducted > 0 || extraAmount > 0;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── LEFT: entry count + qty + KG FAT ────────────────────────────
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey50,
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Total Entries',
                  style: pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 2),
              pw.Text('${entries.length}',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text('Total Quantity',
                  style: pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 2),
              pw.Text('${totalQty.toStringAsFixed(2)} L',
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text('Total KG FAT',
                  style: pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 2),
              pw.Text(totalKgFat.toStringAsFixed(4),
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800)),
            ],
          ),
        ),

        pw.SizedBox(width: 12),

        // ── RIGHT: financial totals ──────────────────────────────────────
        pw.Expanded(
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
                // Milk subtotal
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Milk Amount:',
                        style: pw.TextStyle(fontSize: 11)),
                    pw.Text(
                      'INR ${_currencyFormat.format(totalMilkAmt)}',
                      style: pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ),

                // Items deducted (only if > 0)
                if (totalItemsDeducted > 0) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Items Deducted (−):',
                          style: pw.TextStyle(
                              fontSize: 11, color: PdfColors.red700)),
                      pw.Text(
                        'INR ${_currencyFormat.format(totalItemsDeducted)}',
                        style: pw.TextStyle(
                            fontSize: 11, color: PdfColors.red700),
                      ),
                    ],
                  ),
                ],

                // Extra amount (only if > 0)
                if (extraAmount > 0) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Extra Amount (+):',
                          style: pw.TextStyle(
                              fontSize: 11, color: PdfColors.green700)),
                      pw.Text(
                        'INR ${_currencyFormat.format(extraAmount)}',
                        style: pw.TextStyle(
                            fontSize: 11, color: PdfColors.green700),
                      ),
                    ],
                  ),
                ],

                // Note (only if present)
                if (extraNote != null && extraNote.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'Note: $extraNote',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontStyle: pw.FontStyle.italic,
                          color: PdfColors.grey700),
                    ),
                  ),
                ],

                if (hasAdj) ...[
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.blue300),
                  pw.SizedBox(height: 4),
                ] else
                  pw.SizedBox(height: 8),

                // Net payable
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Net Payable:',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 13)),
                    pw.Text(
                      'INR ${_currencyFormat.format(netPayable)}',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
              ],
            ),       // end pw.Column
          ),         // end right pw.Container
        ),           // end pw.Expanded
      ],             // end pw.Row children
    );               // end pw.Row
  }

  // ── Collection Report PDF ──────────────────────────────────────────────────
  /// Generates a printable collection report for all entries in a period,
  /// optionally filtered by shift.
  static Future<String> generateCollectionReportPdf({
    required DateTime from,
    required DateTime to,
    required List<MilkEntry> entries,
    String? shiftFilter, // null = all, 'Morning', 'Evening'
  }) async {
    final theme = await _buildTheme();
    final pdf   = pw.Document(theme: theme);

    final totalQty   = entries.fold<double>(0, (s, e) => s + e.quantity);
    final totalKgFat = entries.fold<double>(0, (s, e) => s + e.kgFat);
    final totalAmt   = entries.fold<double>(0, (s, e) => s + e.amount);
    final totalDed   = entries.fold<double>(0, (s, e) => s + e.itemAmount);

    final shiftLabel = shiftFilter ?? 'All Shifts';
    final periodLabel = from == to
        ? _dateFormat.format(from)
        : '${_dateFormat.format(from)} – ${_dateFormat.format(to)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(),
          pw.SizedBox(height: 8),
          // Report title + metadata
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Milk Collection Report',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.SizedBox(height: 2),
                  pw.Text('Period: $periodLabel',
                      style: pw.TextStyle(fontSize: 10)),
                  pw.Text('Shift: $shiftLabel',
                      style: pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                      'Printed: ${_dateFormat.format(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 9)),
                  pw.Text('${entries.length} entries',
                      style: pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          // Table
          _buildReportTable(entries),
          pw.SizedBox(height: 10),
          // Totals row
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.green50,
              border: pw.Border.all(color: PdfColors.green200),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Milk Qty: ${totalQty.toStringAsFixed(2)} L',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 10),
                ),
                pw.Text(
                  'Total KG FAT: ${totalKgFat.toStringAsFixed(4)}',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 10),
                ),
                if (totalDed > 0)
                  pw.Text(
                    'Deductions: ${_currencyFormat.format(totalDed)}',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        color: PdfColors.red700),
                  ),
                pw.Text(
                  'Total Amount: INR ${_currencyFormat.format(totalAmt)}',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          _buildSignatureArea(),
        ],
      ),
    );

    final dir  = await getApplicationDocumentsDirectory();
    final dateStr = DateFormat('yyyy_MM_dd').format(from);
    final shift   = shiftFilter?.toLowerCase() ?? 'all';
    final filePath =
        '${dir.path}/collection_report_${dateStr}_$shift.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return filePath;
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

  static Future<void> shareReportPdf(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'Milk Report from ${AppConstants.firmName}',
    );
  }
}
