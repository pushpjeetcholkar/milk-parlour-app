import 'package:flutter/foundation.dart';
import '../models/milk_entry.dart';
import '../repositories/milk_entry_repository.dart';

class MilkEntryProvider extends ChangeNotifier {
  final MilkEntryRepository _repo = MilkEntryRepository();

  List<MilkEntry> _entries = [];
  bool _loading = false;
  String? _error;

  // Dashboard cache
  double _todayMilk = 0;
  double _todayAmount = 0;

  List<MilkEntry> get entries => _entries;
  bool get loading => _loading;
  String? get error => _error;
  double get todayMilk => _todayMilk;
  double get todayAmount => _todayAmount;

  Future<void> loadRecent({int limit = 20}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _entries = await _repo.getAll(limit: limit);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<MilkEntry>> getForCustomer(int customerId) =>
      _repo.getByCustomer(customerId);

  Future<List<MilkEntry>> getByDate(DateTime date) =>
      _repo.getByDate(date);

  Future<List<MilkEntry>> getByDateRange(DateTime from, DateTime to) =>
      _repo.getByDateRange(from, to);

  Future<List<MilkEntry>> getByCustomerAndDateRange(
          int customerId, DateTime from, DateTime to, {String? shift}) =>
      _repo.getByCustomerAndDateRange(customerId, from, to, shift: shift);

  Future<bool> add(MilkEntry entry) async {
    try {
      final id = await _repo.insert(entry);
      final saved = MilkEntry.fromMap({...entry.toMap(), 'id': id});
      _entries.insert(0, saved);
      await refreshTodayTotals();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await _repo.delete(id);
      _entries.removeWhere((e) => e.id == id);
      await refreshTodayTotals();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshTodayTotals() async {
    final totals = await _repo.getTodayTotals();
    _todayMilk = totals['total_quantity'] ?? 0;
    _todayAmount = totals['total_amount'] ?? 0;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getMonthlySummary(
          int year, int month) =>
      _repo.getMonthlySummary(year, month);

  // ── Analytics ──────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getCustomerRangeSummary(
          DateTime from, DateTime to) =>
      _repo.getCustomerRangeSummary(from, to);

  // ── Period breakdown (Reports screen) ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> getDailyBreakdown(
          DateTime from, DateTime to) =>
      _repo.getDailyBreakdown(from, to);

  Future<List<Map<String, dynamic>>> getWeeklyBreakdown(
          DateTime from, DateTime to) =>
      _repo.getWeeklyBreakdown(from, to);

  Future<List<Map<String, dynamic>>> getMonthlyBreakdown(
          DateTime from, DateTime to) =>
      _repo.getMonthlyBreakdown(from, to);

  // ── Shift analysis ─────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getShiftTotals(
          DateTime from, DateTime to) =>
      _repo.getShiftTotals(from, to);

  Future<List<Map<String, dynamic>>> getCustomerShiftSummary(
          DateTime from, DateTime to) =>
      _repo.getCustomerShiftSummary(from, to);

  Future<List<Map<String, dynamic>>> getDailyShiftBreakdown(
          DateTime from, DateTime to) =>
      _repo.getDailyShiftBreakdown(from, to);

  Future<List<Map<String, dynamic>>> getWeeklyShiftBreakdown(
          DateTime from, DateTime to) =>
      _repo.getWeeklyShiftBreakdown(from, to);

  Future<List<Map<String, dynamic>>> getMonthlyShiftBreakdown(
          DateTime from, DateTime to) =>
      _repo.getMonthlyShiftBreakdown(from, to);
}
