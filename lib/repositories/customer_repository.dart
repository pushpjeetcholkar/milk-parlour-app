import '../core/database/database_helper.dart';
import '../models/customer.dart';

class CustomerRepository {
  final DatabaseHelper _db = DatabaseHelper();

  Future<int> insert(Customer customer) async {
    final db = await _db.database;
    return db.insert('customers', customer.toMap()..remove('id'));
  }

  Future<int> update(Customer customer) async {
    final db = await _db.database;
    return db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Customer>> getAll() async {
    final db = await _db.database;
    final maps = await db.query('customers', orderBy: 'name ASC');
    return maps.map(Customer.fromMap).toList();
  }

  Future<Customer?> getById(int id) async {
    final db = await _db.database;
    final maps =
        await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Customer.fromMap(maps.first);
  }

  Future<List<Customer>> search(String query) async {
    final db = await _db.database;
    final maps = await db.query(
      'customers',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
    );
    return maps.map(Customer.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _db.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM customers');
    return (result.first['cnt'] as int?) ?? 0;
  }
}
