import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../constants/app_constants.dart';

class InvoiceNumberGenerator {
  /// Returns next invoice number like HKMC-2026-0001
  static Future<String> next() async {
    final db = await DatabaseHelper().database;
    final year = DateTime.now().year;

    return db.transaction((txn) async {
      final rows = await txn.query(
        'invoice_counter',
        where: 'id = 1',
      );

      if (rows.isEmpty) {
        await txn.insert('invoice_counter', {
          'id': 1,
          'year': year,
          'counter': 1,
        });
        return _format(year, 1);
      }

      final row = rows.first;
      final storedYear = row['year'] as int;
      int counter = (row['counter'] as int);

      if (storedYear != year) {
        counter = 1;
      } else {
        counter += 1;
      }

      await txn.update(
        'invoice_counter',
        {'year': year, 'counter': counter},
        where: 'id = 1',
      );

      return _format(year, counter);
    });
  }

  static String _format(int year, int counter) {
    return '${AppConstants.invoicePrefix}-$year-${counter.toString().padLeft(4, '0')}';
  }
}
