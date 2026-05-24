import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/utils/validators.dart';
import '../../models/customer.dart';
import '../../providers/customer_provider.dart';

class AddCustomerScreen extends StatefulWidget {
  final Customer? customer;

  const AddCustomerScreen({super.key, this.customer});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _addressCtrl;
  bool _saving = false;

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.customer?.name ?? '');
    _mobileCtrl =
        TextEditingController(text: widget.customer?.mobile ?? '');
    _addressCtrl =
        TextEditingController(text: widget.customer?.address ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final prov = context.read<CustomerProvider>();
    bool ok;
    if (_isEditing) {
      ok = await prov.edit(widget.customer!.copyWith(
        name: _nameCtrl.text.trim(),
        mobile: _mobileCtrl.text.trim().isEmpty
            ? null
            : _mobileCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
      ));
    } else {
      ok = await prov.add(Customer(
        name: _nameCtrl.text.trim(),
        mobile: _mobileCtrl.text.trim().isEmpty
            ? null
            : _mobileCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
        createdAt: DateTime.now(),
      ));
    }

    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              _isEditing ? 'Customer updated!' : 'Customer added!'),
        ));
        Navigator.pop(context);
      } else {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to save customer.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Customer' : 'Add Customer'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Customer Name *',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: Validators.validateCustomerName,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number (Optional)',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                validator: Validators.validateMobile,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Address (Optional)',
                  prefixIcon: Icon(Icons.location_on),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),
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
                  label: Text(_isEditing ? 'Update Customer' : 'Save Customer',
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
