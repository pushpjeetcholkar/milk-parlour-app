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

  final _qtyCtrl = TextEditingController();
  final _clrCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();

  double _kgFat = 0;
  double _amount = 0;
  bool _saving = false;

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
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final fat = double.tryParse(_fatCtrl.text) ?? 0;
    final rate = double.tryParse(_rateCtrl.text) ?? 0;
    setState(() {
      _kgFat = CalculationEngine.calculateKgFat(quantity: qty, fat: fat);
      _amount = CalculationEngine.calculateAmount(
          quantity: qty, fat: fat, rate: rate);
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer')),
      );
      return;
    }

    setState(() => _saving = true);

    final entry = MilkEntry(
      customerId: _selectedCustomer!.id!,
      date: _selectedDate,
      quantity: double.parse(_qtyCtrl.text),
      clr: double.parse(_clrCtrl.text),
      fat: double.parse(_fatCtrl.text),
      rate: double.parse(_rateCtrl.text),
      kgFat: _kgFat,
      amount: _amount,
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
              // Date picker
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

              // Customer dropdown
              Consumer<CustomerProvider>(
                builder: (context, prov, _) => DropdownButtonFormField<Customer>(
                  value: _selectedCustomer,
                  decoration: const InputDecoration(
                    labelText: 'Customer *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  items: prov.allCustomers
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.name),
                          ))
                      .toList(),
                  onChanged: (c) => setState(() => _selectedCustomer = c),
                  validator: (_) => _selectedCustomer == null
                      ? 'Please select a customer'
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              // Quantity
              TextFormField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

              // CLR
              TextFormField(
                controller: _clrCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'CLR *',
                  prefixIcon: Icon(Icons.science),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _recalculate(),
                validator: Validators.validateClr,
              ),
              const SizedBox(height: 12),

              // FAT
              TextFormField(
                controller: _fatCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

              // Rate
              TextFormField(
                controller: _rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Rate per FAT *',
                  prefixIcon: Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _recalculate(),
                validator: Validators.validateRate,
              ),
              const SizedBox(height: 20),

              // Calculated results
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
                              value: '₹ ${_amount.toStringAsFixed(2)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Save button
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
