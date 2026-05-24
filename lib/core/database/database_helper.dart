import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../constants/app_constants.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);
    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        mobile TEXT,
        address TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE milk_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        quantity REAL NOT NULL,
        clr REAL NOT NULL,
        fat REAL NOT NULL,
        rate REAL NOT NULL,
        kgfat REAL NOT NULL,
        amount REAL NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER NOT NULL,
        from_date TEXT NOT NULL,
        to_date TEXT NOT NULL,
        total_quantity REAL NOT NULL,
        total_amount REAL NOT NULL,
        pdf_path TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_counter (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        year INTEGER NOT NULL,
        counter INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Enable foreign keys
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future migrations here
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // ── Backup / Restore ──────────────────────────────────────────────────
  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, AppConstants.dbName);
  }

  Future<void> copyDatabaseTo(String destinationPath) async {
    final dbPath = await getDatabasePath();
    final source = File(dbPath);
    await source.copy(destinationPath);
  }

  Future<void> restoreFrom(String sourcePath) async {
    await close();
    final dbPath = await getDatabasePath();
    final source = File(sourcePath);
    await source.copy(dbPath);
    _database = await _initDB();
  }
}
