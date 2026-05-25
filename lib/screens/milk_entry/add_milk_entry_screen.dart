import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/utils/calculation_engine.dart';
import '../../core/utils/validators.dart';
import '../../models/customer.dart';
import '../../models/milk_entry.dart';
import '../../providers/customer_provider.dart';
import '../../providers/milk_entry_provider.dart';

class AddMilkEntryScreen extends StatefulWidget {
  const AddMilkEntryScreen({super.key});

  @override
  State<AddMilkEntryScreen> createState() => _AddMilkEntryScreenState();
}

class _AddMilkEntryScreenState extends State<AddMilkEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  DateTime _selectedDate = DateTime.now();
  Customer? _selectedCustomer;
  String _shift = 'Morning'; // 'Morning' or 'Evening'

  final _qtyCtrl  = TextEditingController();
  final _clrCtrl  = TextEditingController();
  final _fatCtrl  = TextEditingController();
  final _rateCtrl = TextEditingController();

  double _kgFat  = 0;
  double _amount = 0;
  bool   _saving = false;

  final _dateFmt = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _clrCtrl.dispose();
    _fatCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  void _recalculate() {
    final qty  = double.tryParse(_qtyCtrl.text)  ?? 0;
    final fat  = double.tryParse(_fatCtrl.text)  ?? 0;
    final rate = double.tryParse(_rateCtrl.text) ?? 0;
    setState(() {
      _kgFat  = CalculationEngine.calculateKgFat(quantity: qty, fat: fat);
      _amount = CalculationEngine.calculateAmount(quantity: qty, fat: fat, rate: rate);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // ── Searchable customer picker ─────────────────────────────────────────────
  Future<void> _pickCustomer(List<Customer> customers) async {
    final result = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CustomerSearchSheet(customers: customers),
    );
    if (result != null) setState(() => _selectedCustomer = result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer')),
      );
      return;
    }

    setState(() => _saving = true);

    // Capture current time as HH:mm when Save is tapped
    final now = DateTime.now();
    final entryTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final entry = MilkEntry(
      customerId: _selectedCustomer!.id!,
      date:       _selectedDate,
      quantity:   double.parse(_qtyCtrl.text),
      clr:        double.parse(_clrCtrl.text),
      fat:        double.parse(_fatCtrl.text),
      rate:       double.parse(_rateCtrl.text),
      kgFat:      _kgFat,
      amount:     _amount,
      shift:      _shift,
      entryTime:  entryTime,
    );

    final ok = await context.read<MilkEntryProvider>().add(entry);
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Milk entry saved!')),
        );
        Navigator.pop(context);
      } else {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to save entry.'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Milk Entry')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Date picker ──────────────────────────────────────────────
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_today, color: Colors.blue),
                  title: const Text('Date'),
                  subtitle: Text(_dateFmt.format(_selectedDate),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.edit),
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(height: 12),

              // ── Shift selector ───────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.blue),
                      const SizedBox(width: 12),
                      const Text('Shift',
                          style: TextStyle(fontSize: 15)),
                      const Spacer(),
                      _ShiftButton(
                        label: 'Morning',
                        icon: Icons.wb_sunny,
                        selected: _shift == 'Morning',
                        color: Colors.orange,
                        onTap: () => setState(() => _shift = 'Morning'),
                      ),
                      const SizedBox(width: 8),
                      _ShiftButton(
                        label: 'Evening',
                        icon: Icons.nights_stay,
                        selected: _shift == 'Evening',
                        color: Colors.indigo,
                        onTap: () => setState(() => _shift = 'Evening'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Customer searchable picker ───────────────────────────────
              Consumer<CustomerProvider>(
                builder: (context, prov, _) {
                  return GestureDetector(
                    onTap: () => _pickCustomer(prov.allCustomers),
                    child: AbsorbPointer(
                      child: TextFormField(
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Customer *',
                          prefixIcon: const Icon(Icons.person),
                          suffixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          hintText: 'Tap to search customer…',
                        ),
                        controller: TextEditingController(
                            text: _selectedCustomer?.name ?? ''),
                        validator: (_) => _selectedCustomer == null
                            ? 'Please select a customer'
                            : null,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // ── Quantity ─────────────────────────────────────────────────
              TextFormField(
                controller: _qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Quantity (Litres) *',
                  prefixIcon: Icon(Icons.water_drop),
                  border: OutlineInputBorder(),
                  suffixText: 'L',
                ),
                onChanged: (_) => _recalculate(),
                validator: Validators.validateQuantity,
              ),
              const SizedBox(height: 12),

              // ── CLR ──────────────────────────────────────────────────────
              TextFormField(
                controller: _clrCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'CLR *',
                  prefixIcon: Icon(Icons.science),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _recalculate(),
                validator: Validators.validateClr,
              ),
              const SizedBox(height: 12),

              // ── FAT ──────────────────────────────────────────────────────
              TextFormField(
                controller: _fatCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'FAT (%) *',
                  prefixIcon: Icon(Icons.percent),
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
                onChanged: (_) => _recalculate(),
                validator: Validators.validateFat,
              ),
              const SizedBox(height: 12),

              // ── Rate ─────────────────────────────────────────────────────
              TextFormField(
                controller: _rateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Rate per FAT *',
                  prefixIcon: Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _recalculate(),
                validator: Validators.validateRate,
              ),
              const SizedBox(height: 20),

              // ── Calculated results ────────────────────────────────────────
              Card(
                color: Colors.blue.shade50,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('Calculated Values',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _CalcValue(
                              label: 'KG FAT',
                              value: _kgFat.toStringAsFixed(4)),
                          _CalcValue(
                              label: 'Amount',
                              value: 'INR ${_amount.toStringAsFixed(2)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Save button ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: const Text('Save Entry',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shift toggle button ────────────────────────────────────────────────────
class _ShiftButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ShiftButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? color : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? color : Colors.grey.shade600,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Searchable Customer Bottom Sheet ──────────────────────────────────────
class _CustomerSearchSheet extends StatefulWidget {
  final List<Customer> customers;
  const _CustomerSearchSheet({required this.customers});

  @override
  State<_CustomerSearchSheet> createState() => _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends State<_CustomerSearchSheet> {
  final _searchCtrl = TextEditingController();
  List<Customer> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.customers;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = widget.customers
          .where((c) => c.name.toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sheet height: 75% of screen
    final sheetHeight = MediaQuery.of(context).size.height * 0.75;

    return SizedBox(
      height: sheetHeight,
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Select Customer',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          // Search field
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search customer name…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const Divider(height: 1),
          // Customer list
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No customers found',
                        style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final c = _filtered[i];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            c.name.isNotEmpty
                                ? c.name[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(c.name),
                        subtitle: c.mobile != null && c.mobile!.isNotEmpty
                            ? Text(c.mobile!)
                            : null,
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Calc value display ─────────────────────────────────────────────────────
class _CalcValue extends StatelessWidget {
  final String label;
  final String value;

  const _CalcValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue)),
      ],
    );
  }
}
