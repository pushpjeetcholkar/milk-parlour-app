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
