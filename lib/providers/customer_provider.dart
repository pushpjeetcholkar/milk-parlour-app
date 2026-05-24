import 'package:flutter/foundation.dart';
import '../models/customer.dart';
import '../repositories/customer_repository.dart';

class CustomerProvider extends ChangeNotifier {
  final CustomerRepository _repo = CustomerRepository();

  List<Customer> _customers = [];
  List<Customer> _filtered = [];
  bool _loading = false;
  String? _error;

  List<Customer> get customers => _filtered.isNotEmpty ? _filtered : _customers;
  List<Customer> get allCustomers => _customers;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadAll() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _customers = await _repo.getAll();
      _filtered = [];
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> add(Customer customer) async {
    try {
      final id = await _repo.insert(customer);
      _customers.add(customer.copyWith(id: id));
      _customers.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> edit(Customer customer) async {
    try {
      await _repo.update(customer);
      final idx = _customers.indexWhere((c) => c.id == customer.id);
      if (idx != -1) _customers[idx] = customer;
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
      _customers.removeWhere((c) => c.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void search(String query) {
    if (query.trim().isEmpty) {
      _filtered = [];
    } else {
      _filtered = _customers
          .where((c) =>
              c.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

  void clearSearch() {
    _filtered = [];
    notifyListeners();
  }

  Future<int> count() => _repo.count();
}
