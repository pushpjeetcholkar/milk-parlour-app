import '../core/database/database_helper.dart';
import '../models/milk_entry.dart';

class MilkEntryRepository {
  final DatabaseHelper _db = DatabaseHelper();

  Future<int> insert(MilkEntry entry) async {
    final db = await _db.database;
    final map = entry.toMap()..remove('id');
    return db.insert('milk_entries', map);
  }

  Future<int> update(MilkEntry entry) async {
    final db = await _db.database;
    return db.update(
      'milk_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('milk_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<MilkEntry>> getAll({int? limit}) async {
    final db = await _db.database;
    final maps = await db.rawQuery('''
      SELECT me.*, c.name AS customer_name
      FROM milk_entries me
      LEFT JOIN customers c ON c.id = me.customer_id
      ORDER BY me.date DESC
      ${limit != null ? 'LIMIT $limit' : ''}
    ''');
    return maps.map(MilkEntry.fromMap).toList();
  }

  Future<List<MilkEntry>> getByCustomer(int customerId) async {
    final db = await _db.database;
    final maps = await db.rawQuery('''
      SELECT me.*, c.name AS customer_name
      FROM milk_entries me
      LEFT JOIN customers c ON c.id = me.customer_id
      WHERE me.customer_id = ?
      ORDER BY me.date DESC
    ''', [customerId]);
    return maps.map(MilkEntry.fromMap).toList();
  }

  Future<List<MilkEntry>> getByDate(DateTime date) async {
    final db = await _db.database;
    final dateStr = date.toIso8601String().substring(0, 10);
    final maps = await db.rawQuery('''
      SELECT me.*, c.name AS customer_name
      FROM milk_entries me
      LEFT JOIN customers c ON c.id = me.customer_id
      WHERE DATE(me.date) = ?
      ORDER BY me.date DESC
    ''', [dateStr]);
    return maps.map(MilkEntry.fromMap).toList();
  }

  Future<List<MilkEntry>> getByDateRange(DateTime from, DateTime to) async {
    final db = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr = to.toIso8601String().substring(0, 10);
    final maps = await db.rawQuery('''
      SELECT me.*, c.name AS customer_name
      FROM milk_entries me
      LEFT JOIN customers c ON c.id = me.customer_id
      WHERE DATE(me.date) BETWEEN ? AND ?
      ORDER BY me.date DESC
    ''', [fromStr, toStr]);
    return maps.map(MilkEntry.fromMap).toList();
  }

  Future<List<MilkEntry>> getByCustomerAndDateRange(
      int customerId, DateTime from, DateTime to, {String? shift}) async {
    final db = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr = to.toIso8601String().substring(0, 10);
    final shiftClause = shift != null ? 'AND me.shift = ?' : '';
    final args = shift != null
        ? [customerId, fromStr, toStr, shift]
        : [customerId, fromStr, toStr];
    final maps = await db.rawQuery('''
      SELECT me.*, c.name AS customer_name
      FROM milk_entries me
      LEFT JOIN customers c ON c.id = me.customer_id
      WHERE me.customer_id = ? AND DATE(me.date) BETWEEN ? AND ?
      $shiftClause
      ORDER BY me.date ASC
    ''', args);
    return maps.map(MilkEntry.fromMap).toList();
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────
  Future<Map<String, double>> getTodayTotals() async {
    final db = await _db.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(quantity), 0) AS total_quantity,
        COALESCE(SUM(amount), 0)   AS total_amount
      FROM milk_entries
      WHERE DATE(date) = ?
    ''', [today]);
    final row = result.first;
    return {
      'total_quantity': (row['total_quantity'] as num).toDouble(),
      'total_amount':   (row['total_amount']   as num).toDouble(),
    };
  }

  // ── Monthly summary per customer (existing) ────────────────────────────────
  Future<List<Map<String, dynamic>>> getMonthlySummary(
      int year, int month) async {
    final db = await _db.database;
    final from = _monthStart(year, month);
    final to   = _monthEnd(year, month);
    return db.rawQuery('''
      SELECT
        c.name AS customer_name,
        SUM(me.quantity) AS total_quantity,
        SUM(me.kgfat)    AS total_kgfat,
        SUM(me.amount)   AS total_amount
      FROM milk_entries me
      LEFT JOIN customers c ON c.id = me.customer_id
      WHERE DATE(me.date) BETWEEN ? AND ?
      GROUP BY me.customer_id
      ORDER BY c.name ASC
    ''', [from, to]);
  }

  // ── Period breakdown queries (new) ─────────────────────────────────────────

  /// Day-by-day totals between two dates
  Future<List<Map<String, dynamic>>> getDailyBreakdown(
      DateTime from, DateTime to) async {
    final db     = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr   = to.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT
        DATE(date)       AS period_label,
        COUNT(*)         AS entry_count,
        SUM(quantity)    AS total_quantity,
        SUM(kgfat)       AS total_kgfat,
        SUM(amount)      AS total_amount
      FROM milk_entries
      WHERE DATE(date) BETWEEN ? AND ?
      GROUP BY DATE(date)
      ORDER BY date ASC
    ''', [fromStr, toStr]);
  }

  /// Week-by-week totals between two dates (ISO week: Mon–Sun)
  Future<List<Map<String, dynamic>>> getWeeklyBreakdown(
      DateTime from, DateTime to) async {
    final db      = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr   = to.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT
        strftime('%Y-W%W', date) AS period_label,
        MIN(DATE(date))          AS week_start,
        MAX(DATE(date))          AS week_end,
        COUNT(*)                 AS entry_count,
        SUM(quantity)            AS total_quantity,
        SUM(kgfat)               AS total_kgfat,
        SUM(amount)              AS total_amount
      FROM milk_entries
      WHERE DATE(date) BETWEEN ? AND ?
      GROUP BY strftime('%Y-%W', date)
      ORDER BY date ASC
    ''', [fromStr, toStr]);
  }

  /// Month-by-month totals between two dates
  Future<List<Map<String, dynamic>>> getMonthlyBreakdown(
      DateTime from, DateTime to) async {
    final db      = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr   = to.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT
        strftime('%Y-%m', date) AS period_label,
        COUNT(*)                AS entry_count,
        SUM(quantity)           AS total_quantity,
        SUM(kgfat)              AS total_kgfat,
        SUM(amount)             AS total_amount
      FROM milk_entries
      WHERE DATE(date) BETWEEN ? AND ?
      GROUP BY strftime('%Y-%m', date)
      ORDER BY date ASC
    ''', [fromStr, toStr]);
  }

  // ── Shift analysis queries ─────────────────────────────────────────────────

  /// Total qty/kgfat/amount split by shift for a date range.
  Future<List<Map<String, dynamic>>> getShiftTotals(
      DateTime from, DateTime to) async {
    final db = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr = to.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT
        shift,
        COUNT(*)         AS entry_count,
        SUM(quantity)    AS total_quantity,
        SUM(kgfat)       AS total_kgfat,
        SUM(amount)      AS total_amount
      FROM milk_entries
      WHERE DATE(date) BETWEEN ? AND ?
      GROUP BY shift
      ORDER BY shift ASC
    ''', [fromStr, toStr]);
  }

  /// Per-customer per-shift totals for a date range.
  Future<List<Map<String, dynamic>>> getCustomerShiftSummary(
      DateTime from, DateTime to) async {
    final db = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr = to.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT
        c.id              AS customer_id,
        c.name            AS customer_name,
        me.shift,
        SUM(me.quantity)  AS total_quantity,
        SUM(me.kgfat)     AS total_kgfat,
        SUM(me.amount)    AS total_amount
      FROM milk_entries me
      LEFT JOIN customers c ON c.id = me.customer_id
      WHERE DATE(me.date) BETWEEN ? AND ?
      GROUP BY me.customer_id, me.shift
      ORDER BY c.name ASC, me.shift ASC
    ''', [fromStr, toStr]);
  }

  /// Day-by-day qty/kgfat split by shift.
  Future<List<Map<String, dynamic>>> getDailyShiftBreakdown(
      DateTime from, DateTime to) async {
    final db = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr = to.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT
        DATE(date)    AS period_label,
        shift,
        SUM(quantity) AS total_quantity,
        SUM(kgfat)    AS total_kgfat,
        SUM(amount)   AS total_amount
      FROM milk_entries
      WHERE DATE(date) BETWEEN ? AND ?
      GROUP BY DATE(date), shift
      ORDER BY date ASC, shift ASC
    ''', [fromStr, toStr]);
  }

  /// Week-by-week qty/kgfat split by shift.
  Future<List<Map<String, dynamic>>> getWeeklyShiftBreakdown(
      DateTime from, DateTime to) async {
    final db = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr = to.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT
        strftime('%Y-W%W', date) AS period_label,
        MIN(DATE(date))          AS week_start,
        shift,
        SUM(quantity)            AS total_quantity,
        SUM(kgfat)               AS total_kgfat,
        SUM(amount)              AS total_amount
      FROM milk_entries
      WHERE DATE(date) BETWEEN ? AND ?
      GROUP BY strftime('%Y-%W', date), shift
      ORDER BY date ASC, shift ASC
    ''', [fromStr, toStr]);
  }

  /// Month-by-month qty/kgfat split by shift.
  Future<List<Map<String, dynamic>>> getMonthlyShiftBreakdown(
      DateTime from, DateTime to) async {
    final db = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr = to.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT
        strftime('%Y-%m', date) AS period_label,
        shift,
        SUM(quantity)           AS total_quantity,
        SUM(kgfat)              AS total_kgfat,
        SUM(amount)             AS total_amount
      FROM milk_entries
      WHERE DATE(date) BETWEEN ? AND ?
      GROUP BY strftime('%Y-%m', date), shift
      ORDER BY date ASC, shift ASC
    ''', [fromStr, toStr]);
  }

  // ── Analytics: per-customer aggregate stats for a date range ──────────────
  Future<List<Map<String, dynamic>>> getCustomerRangeSummary(
      DateTime from, DateTime to) async {
    final db      = await _db.database;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr   = to.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT
        c.id                        AS customer_id,
        c.name                      AS customer_name,
        COUNT(*)                    AS entry_count,
        COUNT(DISTINCT DATE(me.date)) AS days_present,
        SUM(me.quantity)            AS total_quantity,
        AVG(me.fat)                 AS avg_fat,
        SUM(me.kgfat)               AS total_kgfat,
        SUM(me.amount)              AS total_amount
      FROM milk_entries me
      LEFT JOIN customers c ON c.id = me.customer_id
      WHERE DATE(me.date) BETWEEN ? AND ?
      GROUP BY me.customer_id
      ORDER BY total_quantity DESC
    ''', [fromStr, toStr]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static String _monthStart(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01';

  static String _monthEnd(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${lastDay.toString().padLeft(2, '0')}';
  }
}
