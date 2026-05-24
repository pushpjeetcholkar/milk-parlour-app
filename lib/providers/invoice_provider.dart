import 'package:flutter/foundation.dart';
import '../models/invoice.dart';
import '../repositories/invoice_repository.dart';

class InvoiceProvider extends ChangeNotifier {
  final InvoiceRepository _repo = InvoiceRepository();

  List<Invoice> _invoices = [];
  bool _loading = false;
  String? _error;

  List<Invoice> get invoices => _invoices;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadAll() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _invoices = await _repo.getAll();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Invoice?> save(Invoice invoice) async {
    try {
      final id = await _repo.insert(invoice);
      final saved = Invoice(
        id: id,
        invoiceNumber: invoice.invoiceNumber,
        customerId: invoice.customerId,
        customerName: invoice.customerName,
        fromDate: invoice.fromDate,
        toDate: invoice.toDate,
        totalQuantity: invoice.totalQuantity,
        totalAmount: invoice.totalAmount,
        pdfPath: invoice.pdfPath,
        createdAt: invoice.createdAt,
      );
      _invoices.insert(0, saved);
      notifyListeners();
      return saved;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> updatePdfPath(int id, String pdfPath) async {
    await _repo.updatePdfPath(id, pdfPath);
    final idx = _invoices.indexWhere((inv) => inv.id == id);
    if (idx != -1) {
      _invoices[idx] = _invoices[idx].copyWith(pdfPath: pdfPath);
      notifyListeners();
    }
  }

  Future<bool> remove(int id) async {
    try {
      await _repo.delete(id);
      _invoices.removeWhere((inv) => inv.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<List<Invoice>> getForCustomer(int customerId) =>
      _repo.getByCustomer(customerId);

  Future<List<Invoice>> searchByNumber(String query) =>
      _repo.searchByNumber(query);
}
