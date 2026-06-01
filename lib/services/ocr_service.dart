import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/scanned_entry.dart';

enum OcrEngine { mlKit, cloudVision }

/// Full OCR result containing the raw text AND the structured blocks
/// (needed for spatial row reconstruction).
class OcrResult {
  final String         rawText;
  final RecognizedText? recognized;
  final OcrEngine      engine;
  final List<CloudVisionBlock> cloudBlocks;
  OcrResult({
    required this.rawText,
    this.recognized,
    this.engine = OcrEngine.mlKit,
    this.cloudBlocks = const [],
  });
}

/// Lightweight bounding-box holder for Cloud Vision text blocks.
class CloudVisionBlock {
  final String text;
  final double top;
  final double left;
  final double width;
  final double height;
  CloudVisionBlock({
    required this.text,
    required this.top,
    required this.left,
    required this.width,
    required this.height,
  });
}

// ─── Internal helper for a single text element with its position ──────────────
class _Elem {
  final String text;
  final double top;
  final double left;
  final double height;
  _Elem({required this.text, required this.top,
         required this.left, required this.height});
}

/// Handles OCR extraction and parsing of handwritten milk register pages.
///
/// Pipeline
/// ─────────
///   1. Run ML Kit on original image → detect tilt angle from block corners
///   2. If tilt > 2.5° → rotate image → re-run ML Kit
///   3. Collect every TextLine with its bounding box
///   4. Group lines by Y-position (same table row = similar Y)
///   5. Within each group sort by X-position (left → right)
///   6. Reconstruct the row string and parse column tokens
///
/// Why spatial reconstruction?
/// ───────────────────────────
/// ML Kit splits a printed table into one TextBlock per cell, not per row.
/// `RecognizedText.text` therefore gives columns, not rows.
/// Using bounding boxes to group by Y restores the correct row order.
class OcrService {

  // ══════════════════════════════════════════════════════════════════════════
  //  Public API
  // ══════════════════════════════════════════════════════════════════════════

  /// Run OCR with automatic tilt correction. Returns both raw text and the
  /// structured RecognizedText needed for spatial row reconstruction.
  static Future<OcrResult> extractStructured(File imageFile) async {
    final recognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input1  = InputImage.fromFilePath(imageFile.path);
      final result1 = await recognizer.processImage(input1);

      final angle = _detectTiltDegrees(result1.blocks);

      RecognizedText best = result1;
      if (angle.abs() > 2.5) {
        final rotated = await _rotateImage(imageFile, -angle);
        final input2  = InputImage.fromFilePath(rotated.path);
        final result2 = await recognizer.processImage(input2);
        best = result2.text.length >= result1.text.length ? result2 : result1;
      }

      return OcrResult(rawText: best.text, recognized: best);
    } finally {
      await recognizer.close();
    }
  }

  /// Convenience: extract text only (for backward compat / raw display).
  static Future<String> extractText(File imageFile) async {
    final r = await extractStructured(imageFile);
    return r.rawText;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Google Cloud Vision API (handwriting support)
  // ══════════════════════════════════════════════════════════════════════════

  /// Calls Google Cloud Vision DOCUMENT_TEXT_DETECTION for handwriting OCR.
  /// Returns an OcrResult with cloud-sourced blocks for spatial reconstruction.
  static Future<OcrResult> extractWithCloudVision(
      File imageFile, String apiKey) async {
    final bytes   = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final uri = Uri.parse(
        'https://vision.googleapis.com/v1/images:annotate?key=$apiKey');

    final body = jsonEncode({
      'requests': [
        {
          'image': {'content': base64Image},
          'features': [
            {'type': 'DOCUMENT_TEXT_DETECTION', 'maxResults': 1}
          ],
          'imageContext': {
            'languageHints': ['en'],
          },
        }
      ]
    });

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Cloud Vision API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final responses = json['responses'] as List<dynamic>?;
    if (responses == null || responses.isEmpty) {
      return OcrResult(rawText: '', engine: OcrEngine.cloudVision);
    }

    final result = responses[0] as Map<String, dynamic>;

    if (result.containsKey('error')) {
      final err = result['error'] as Map<String, dynamic>;
      throw Exception('Cloud Vision: ${err['message'] ?? err}');
    }

    final fullAnnotation =
        result['fullTextAnnotation'] as Map<String, dynamic>?;
    final rawText = fullAnnotation?['text'] as String? ?? '';

    final cloudBlocks = <CloudVisionBlock>[];
    final annotations =
        result['textAnnotations'] as List<dynamic>? ?? [];

    // Skip the first annotation (it's the full text), process individual words
    for (int i = 1; i < annotations.length; i++) {
      final ann = annotations[i] as Map<String, dynamic>;
      final desc = ann['description'] as String? ?? '';
      final bp = ann['boundingPoly']?['vertices'] as List<dynamic>?;
      if (bp == null || bp.length < 4 || desc.trim().isEmpty) continue;

      final xs = bp.map((v) => (v['x'] as num?)?.toDouble() ?? 0.0).toList();
      final ys = bp.map((v) => (v['y'] as num?)?.toDouble() ?? 0.0).toList();
      final minX = xs.reduce(min);
      final minY = ys.reduce(min);
      final maxX = xs.reduce(max);
      final maxY = ys.reduce(max);

      cloudBlocks.add(CloudVisionBlock(
        text:   desc.trim(),
        left:   minX,
        top:    minY,
        width:  maxX - minX,
        height: maxY - minY,
      ));
    }

    return OcrResult(
      rawText:     rawText,
      engine:      OcrEngine.cloudVision,
      cloudBlocks: cloudBlocks,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Row reconstruction + parsing
  // ══════════════════════════════════════════════════════════════════════════

  /// Main entry point: spatially reconstruct rows → parse → return entries.
  static List<ScannedEntry> parseOcrResult(
      OcrResult result, {double defaultRate = 9.0}) {

    // 1. Collect every TextLine element with its bounding box
    final elems = <_Elem>[];

    if (result.engine == OcrEngine.cloudVision) {
      // Cloud Vision: use word-level annotations
      for (final cb in result.cloudBlocks) {
        final cleaned = _cleanText(cb.text);
        if (cleaned.isEmpty) continue;
        elems.add(_Elem(
          text:   cleaned,
          top:    cb.top,
          left:   cb.left,
          height: cb.height,
        ));
      }
    } else if (result.recognized != null) {
      for (final block in result.recognized!.blocks) {
        for (final line in block.lines) {
          final bb = line.boundingBox;
          final cleaned = _cleanText(line.text);
          if (cleaned.isEmpty) continue;
          elems.add(_Elem(
            text:   cleaned,
            top:    bb.top.toDouble(),
            left:   bb.left.toDouble(),
            height: bb.height.toDouble(),
          ));
        }
      }
    }

    // 2. If ML Kit returned nothing meaningful, fall back to raw text parsing
    if (elems.isEmpty) {
      return _parseRawText(result.rawText, defaultRate: defaultRate);
    }

    // 3. Use CENTER-Y for each element (more stable than top across cell sizes)
    double cy(_Elem e) => e.top + e.height / 2;

    elems.sort((a, b) => cy(a).compareTo(cy(b)));

    // Threshold = 1.5× median height — generous enough to catch hand-written
    // cells whose baselines shift within the same row (e.g. ±20–30 px)
    final heights = elems.map((e) => e.height).toList()..sort();
    final medH    = heights[heights.length ~/ 2];
    final thresh  = medH * 1.5;

    // 4. Group elements into rows by center-Y proximity.
    //    Track the RUNNING average center-Y of the current row so late-joining
    //    cells are compared against the group centroid, not just the first cell.
    final rows = <List<_Elem>>[];
    var   cur        = <_Elem>[elems.first];
    var   curAvgCY   = cy(elems.first);

    for (int i = 1; i < elems.length; i++) {
      final elemCY = cy(elems[i]);
      if ((elemCY - curAvgCY).abs() <= thresh) {
        cur.add(elems[i]);
        // Update running average
        curAvgCY = cur.map(cy).reduce((a, b) => a + b) / cur.length;
      } else {
        rows.add(cur);
        cur      = [elems[i]];
        curAvgCY = elemCY;
      }
    }
    rows.add(cur);

    // 5. Within each row sort by X (left → right) and join
    final rowStrings = rows
        .map((row) {
          row.sort((a, b) => a.left.compareTo(b.left));
          return row.map((e) => e.text).join(' ');
        })
        .toList();

    // 6. Parse each reconstructed row
    return _parseRows(rowStrings, defaultRate: defaultRate);
  }

  /// Legacy entry point (uses raw text with newline splitting).
  /// Still useful as a fallback.
  static List<ScannedEntry> parseOcrText(
      String text, {double defaultRate = 9.0}) =>
      _parseRawText(text, defaultRate: defaultRate);

  // ══════════════════════════════════════════════════════════════════════════
  //  Internal parsing
  // ══════════════════════════════════════════════════════════════════════════

  static List<ScannedEntry> _parseRawText(
      String text, {required double defaultRate}) {
    final lines = text
        .split(RegExp(r'[\n\|]'))
        .map(_cleanText)
        .where((l) => l.length >= 2)
        .toList();
    return _parseRows(lines, defaultRate: defaultRate);
  }

  static List<ScannedEntry> _parseRows(
      List<String> rows, {required double defaultRate}) {
    final entries = <ScannedEntry>[];
    for (final row in rows) {
      if (_isHeaderRow(row)) continue;
      if (_isEmptyRow(row))  continue;

      final entry = _parseLine(row);
      // Accept if at least 1 meaningful field was extracted.
      // The review screen lets the user fill in anything OCR missed.
      if (_meaningfulCount(entry) >= 1) {
        entry.calculate(defaultRate);
        entry.validate();
        entries.add(entry);
      }
    }
    return entries;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Text cleaning
  // ══════════════════════════════════════════════════════════════════════════

  static String _cleanText(String s) => s
      // Decimal comma/dot OCR variants → real decimal point
      .replaceAllMapped(RegExp(r'(\d)[,·•](\d)'), (m) => '${m[1]}.${m[2]}')
      // Common OCR letter↔digit substitutions in numeric context
      .replaceAllMapped(RegExp(r'(?<=[0-9])O(?=[0-9])'), (_) => '0')
      .replaceAllMapped(RegExp(r'(?<=[0-9])l(?=[0-9])'), (_) => '1')
      // Strip table-drawing characters
      .replaceAll(RegExp(r'[─│┤├┼┬┴╔╗╚╝═║\|]'), ' ')
      // Collapse whitespace
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // ══════════════════════════════════════════════════════════════════════════
  //  Header / empty row detection
  // ══════════════════════════════════════════════════════════════════════════

  static bool _isHeaderRow(String line) {
    final l = line.toLowerCase();
    int hits = 0;
    for (final kw in [
      'sr', 'cid', 'shift', 'date', 'qty', 'fat',
      'rate', 'item', 'deduction', 'amount', 'type', 'kgfat', 'kgf'
    ]) {
      if (l.contains(kw)) hits++;
    }
    return hits >= 2; // needs 2+ header keywords
  }

  static bool _isEmptyRow(String line) {
    // Row of dashes / underscores / dots / spaces only
    return line.replaceAll(RegExp(r'[-_.=\s0]'), '').length < 2;
  }

  static int _meaningfulCount(ScannedEntry e) {
    int n = 0;
    if (e.customerId != null) n++;
    if (e.date       != null) n++;
    if (e.shift      != null) n++;
    if (e.milkType   != null) n++;
    if (e.quantity   != null) n++;
    if (e.fat        != null) n++;
    if (e.rate       != null) n++;
    return n;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Line → ScannedEntry parser
  // ══════════════════════════════════════════════════════════════════════════

  static ScannedEntry _parseLine(String line) {
    final entry  = ScannedEntry(rawLine: line);
    // Work on a mutable token list so we can remove matched tokens
    final tokens = line.split(RegExp(r'\s+'))
        .map(_normaliseToken)
        .where((t) => t.isNotEmpty)
        .toList();

    if (tokens.isEmpty) return entry;

    // ── Sr. (optional leading integer when a date follows within 2 tokens) ──
    if (tokens.length >= 3 &&
        _isInt(tokens[0]) &&
        _isInt(tokens[1]) &&
        _isDate(tokens[2])) {
      entry.sr = int.parse(tokens.removeAt(0));
    } else if (tokens.length >= 2 &&
        _isInt(tokens[0]) &&
        (_isDate(tokens[1]) || _isShift(tokens[1]))) {
      // Sr present but CID appears merged with date somehow → skip sr
      entry.sr = int.parse(tokens.removeAt(0));
    }

    // ── CID ───────────────────────────────────────────────────────────────
    if (tokens.isNotEmpty && _isInt(tokens[0])) {
      entry.customerId = int.parse(tokens.removeAt(0));
    }

    // ── Date ──────────────────────────────────────────────────────────────
    final dateIdx = tokens.indexWhere(_isDate);
    if (dateIdx >= 0) {
      entry.date = _parseDate(tokens.removeAt(dateIdx));
    }

    // ── Shift (M/E) — search anywhere in remaining tokens ─────────────────
    final shiftIdx = tokens.indexWhere(_isShift);
    if (shiftIdx >= 0) {
      entry.shift =
          tokens.removeAt(shiftIdx).toUpperCase() == 'M' ? 'Morning' : 'Evening';
    }

    // ── Type (C/B) ────────────────────────────────────────────────────────
    final typeIdx = tokens.indexWhere(_isType);
    if (typeIdx >= 0) {
      entry.milkType =
          tokens.removeAt(typeIdx).toUpperCase() == 'C' ? 'Cow' : 'Buffalo';
    }

    // ── Qty, FAT%, Rate — next three consecutive numbers ──────────────────
    int numCount = 0;
    while (tokens.isNotEmpty && numCount < 3) {
      if (_isNumber(tokens[0])) {
        final v = double.parse(tokens.removeAt(0));
        switch (numCount) {
          case 0: entry.quantity = v; break;
          case 1: entry.fat      = v; break;
          case 2: entry.rate     = v; break;
        }
        numCount++;
      } else {
        break; // stop on first non-number
      }
    }

    // ── Remaining: kgfat? item? deduction? amount? ─────────────────────────
    _parseRemaining(entry, tokens);
    return entry;
  }

  /// Fixes common OCR digit/letter substitutions only when the token looks
  /// like a number (otherwise leaves the token untouched).
  static String _normaliseToken(String t) {
    // Try numeric substitutions: O→0, l→1, I→1, S→5
    final candidate = t
        .replaceAll('O', '0')
        .replaceAll('l', '1')
        .replaceAll('I', '1')
        .replaceAll('S', '5');
    // Accept substituted version only if it's a valid number or date
    if (double.tryParse(candidate) != null || _isDate(candidate)) {
      return candidate;
    }
    return t; // keep original for text tokens (names, shift letters, etc.)
  }

  /// Assigns remaining tokens after Qty/FAT/Rate to KG Fat, Item, Deduction, Amount.
  static void _parseRemaining(ScannedEntry entry, List<String> tokens) {
    final numbers   = <double>[];
    final textParts = <String>[];

    for (final t in tokens) {
      if (_isNumber(t))   { numbers.add(double.parse(t)); }
      else if (_isWord(t)) { textParts.add(t); }
    }

    if (textParts.isNotEmpty) entry.itemName = textParts.join(' ');

    final qty = entry.quantity;
    final fat = entry.fat;
    final expKg = (qty != null && fat != null) ? qty * fat / 100 : null;

    if (entry.itemName != null) {
      if (numbers.length == 1) entry.itemAmount = numbers[0];
      if (numbers.length >= 2) {
        entry.itemAmount = numbers[0];
        entry.amount     = numbers[1];
      }
    } else {
      if (numbers.length == 1) {
        final n = numbers[0];
        if (expKg != null && (n - expKg).abs() < expKg * 0.6) {
          entry.kgFat = n;
        } else {
          entry.amount = n;
        }
      } else if (numbers.length >= 2) {
        entry.kgFat  = numbers[0];
        entry.amount = numbers[1];
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Token helpers
  // ══════════════════════════════════════════════════════════════════════════

  static bool _isInt(String t) {
    final n = int.tryParse(t);
    return n != null && n > 0 && n < 100000;
  }

  static bool _isNumber(String t) => double.tryParse(t) != null;

  /// Matches all common handwritten date formats:
  ///   dd/mm  dd/m  d/m  dd-mm  dd.mm  dd/mm/yy  dd/mm/yyyy
  ///   30/5  30/05  1/6  01-06  30.5.26  30/5/2026
  ///   Also handles OCR noise like spaces around separators: "30 / 5"
  static bool _isDate(String t) {
    final cleaned = t.replaceAll(' ', ''); // "30 / 5" → "30/5"
    return RegExp(r'^\d{1,2}[\/\-\.]\d{1,2}([\/\-\.]\d{2,4})?$')
        .hasMatch(cleaned);
  }

  static bool _isShift(String t) => RegExp(r'^[MmEe]$').hasMatch(t);
  static bool _isType(String t)  => RegExp(r'^[CcBb]$').hasMatch(t);
  static bool _isWord(String t)  => RegExp(r'^[a-zA-Z]{2,}$').hasMatch(t);

  // ── Date parsing ────────────────────────────────────────────────────────────
  //
  // Handles all real-world handwritten date formats:
  //   dd/mm       → 30/5       → 30 May current-year
  //   dd/m        → 30/5       → same
  //   d/m         → 1/6        → 01 Jun current-year
  //   dd-mm       → 30-05      → 30 May current-year
  //   dd.mm       → 30.5       → 30 May current-year
  //   dd/mm/yy    → 30/5/26    → 30 May 2026
  //   dd/mm/yyyy  → 30/05/2026 → 30 May 2026
  //   dd-mm-yy    → 30-05-26   → 30 May 2026
  //   dd mm       → "30 5"     → 30 May current-year (OCR may miss separator)
  //   ddmm        → "3005"     → 30 May current-year (4-digit, no separator)
  //
  // If day > 12 and month ≤ 12 → dd/mm (Indian format, always assumed).
  // If both ≤ 12 → dd/mm (Indian format assumed, never mm/dd).

  static DateTime? _parseDate(String t) {
    try {
      // Strip spaces around separators: "30 / 5" → "30/5"
      final cleaned = t.replaceAll(' ', '');

      // Try splitting on / - .
      var parts = cleaned.split(RegExp(r'[\/\-\.]'));

      // Handle "3005" — 4 digits no separator → dd=30, mm=05
      if (parts.length == 1 && cleaned.length == 4 &&
          RegExp(r'^\d{4}$').hasMatch(cleaned)) {
        parts = [cleaned.substring(0, 2), cleaned.substring(2, 4)];
      }

      // Handle "30526" — 5 digits → dd=30, mm=5, yy=26
      if (parts.length == 1 && cleaned.length >= 5 &&
          RegExp(r'^\d{5,8}$').hasMatch(cleaned)) {
        // Try dd(2) mm(1-2) yy(2-4)
        final day2  = int.tryParse(cleaned.substring(0, 2));
        if (day2 != null && day2 >= 1 && day2 <= 31) {
          // Remaining is month + optional year
          final rest = cleaned.substring(2);
          if (rest.length >= 3) {
            // Try 1-digit month + 2-digit year
            final m1 = int.tryParse(rest.substring(0, 1));
            final y1 = rest.substring(1);
            if (m1 != null && m1 >= 1 && m1 <= 9) {
              parts = [cleaned.substring(0, 2), rest.substring(0, 1), y1];
            } else {
              // Try 2-digit month + rest as year
              parts = [cleaned.substring(0, 2), rest.substring(0, 2),
                       if (rest.length > 2) rest.substring(2)];
            }
          } else {
            parts = [cleaned.substring(0, 2), rest];
          }
        }
      }

      if (parts.length < 2) return null;

      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (day == null || month == null) return null;

      int year;
      if (parts.length >= 3 && parts[2].isNotEmpty) {
        final yPart = int.tryParse(parts[2]);
        if (yPart == null) return null;
        year = yPart < 100 ? 2000 + yPart : yPart;  // 26 → 2026
      } else {
        year = DateTime.now().year;
      }

      // Validate
      if (day < 1 || day > 31) return null;
      if (month < 1 || month > 12) return null;
      if (year < 2020 || year > 2099) return null;

      return DateTime(year, month, day);
    } catch (_) { return null; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Tilt detection & image rotation
  // ══════════════════════════════════════════════════════════════════════════

  static double _detectTiltDegrees(List<TextBlock> blocks) {
    if (blocks.isEmpty) return 0.0;
    final angles = <double>[];
    for (final block in blocks) {
      if (block.cornerPoints.length < 2) continue;
      final tl = block.cornerPoints[0];
      final tr = block.cornerPoints[1];
      final dx = (tr.x - tl.x).toDouble();
      final dy = (tr.y - tl.y).toDouble();
      if (dx.abs() < 5) continue;
      final angle = atan2(dy, dx) * 180.0 / pi;
      if (angle.abs() < 45) angles.add(angle);
    }
    if (angles.isEmpty) return 0.0;
    angles.sort();
    return angles[angles.length ~/ 2];
  }

  static Future<File> _rotateImage(File imageFile, double degrees) async {
    try {
      final bytes    = await imageFile.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return imageFile;
      final rotated  = img.copyRotate(original, angle: degrees);
      final dir      = await getTemporaryDirectory();
      final out = File(
          '${dir.path}/corrected_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(img.encodeJpg(rotated, quality: 92));
      return out;
    } catch (_) { return imageFile; }
  }
}

