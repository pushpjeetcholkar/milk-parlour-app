import '../core/database/database_helper.dart';
import '../models/invoice.dart';

class InvoiceRepository {
  final DatabaseHelper _db = DatabaseHelper();

  Future<int> insert(Invoice invoice) async {
    final db = await _db.database;
    return db.insert('invoices', invoice.toMap()..remove('id'));
  }

  Future<int> updatePdfPath(int id, String pdfPath) async {
    final db = await _db.database;
    return db.update(
      'invoices',
      {'pdf_path': pdfPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Invoice>> getAll() async {
    final db = await _db.database;
    final maps = await db.rawQuery('''
      SELECT inv.*, c.name AS customer_name
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      ORDER BY inv.created_at DESC
    ''');
    return maps.map(Invoice.fromMap).toList();
  }

  Future<List<Invoice>> getByCustomer(int customerId) async {
    final db = await _db.database;
    final maps = await db.rawQuery('''
      SELECT inv.*, c.name AS customer_name
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.customer_id = ?
      ORDER BY inv.created_at DESC
    ''', [customerId]);
    return maps.map(Invoice.fromMap).toList();
  }

  Future<Invoice?> getById(int id) async {
    final db = await _db.database;
    final maps = await db.rawQuery('''
      SELECT inv.*, c.name AS customer_name
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.id = ?
    ''', [id]);
    if (maps.isEmpty) return null;
    return Invoice.fromMap(maps.first);
  }

  /// Returns customers who have milk entries newer than their latest invoice
  /// (or have entries but no invoice at all).
  Future<List<Map<String, dynamic>>> getCustomersWithPendingInvoices() async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT
        c.id,
        c.name            AS customer_name,
        MAX(DATE(me.date)) AS last_entry_date,
        COUNT(*)           AS pending_entries,
        SUM(me.quantity)   AS pending_qty
      FROM milk_entries me
      JOIN customers c ON c.id = me.customer_id
      LEFT JOIN (
        SELECT customer_id, MAX(to_date) AS latest_to
        FROM invoices
        GROUP BY customer_id
      ) li ON li.customer_id = me.customer_id
      WHERE DATE(me.date) > COALESCE(DATE(li.latest_to), '1970-01-01')
      GROUP BY c.id
      ORDER BY last_entry_date DESC
    ''');
  }

  Future<List<Invoice>> searchByNumber(String query) async {
    final db = await _db.database;
    final maps = await db.rawQuery('''
      SELECT inv.*, c.name AS customer_name
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.invoice_number LIKE ?
      ORDER BY inv.created_at DESC
    ''', ['%$query%']);
    return maps.map(Invoice.fromMap).toList();
  }
}
