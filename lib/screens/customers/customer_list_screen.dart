import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer.dart';
import '../../providers/customer_provider.dart';
import 'add_customer_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search customer…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          context.read<CustomerProvider>().clearSearch();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (q) =>
                  context.read<CustomerProvider>().search(q),
            ),
          ),

          // List
          Expanded(
            child: Consumer<CustomerProvider>(
              builder: (context, prov, _) {
                if (prov.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (prov.customers.isEmpty) {
                  return const Center(
                    child: Text('No customers found.',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  itemCount: prov.customers.length,
                  itemBuilder: (context, i) {
                    final c = prov.customers[i];
                    return _CustomerTile(customer: c);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AddCustomerScreen()),
        ).then((_) => context.read<CustomerProvider>().loadAll()),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Customer'),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final Customer customer;

  const _CustomerTile({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(customer.name[0].toUpperCase()),
        ),
        title: Text(customer.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: customer.mobile != null && customer.mobile!.isNotEmpty
            ? Text(customer.mobile!)
            : const Text('No mobile number'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        AddCustomerScreen(customer: customer)),
              );
              if (context.mounted) {
                context.read<CustomerProvider>().loadAll();
              }
            } else if (value == 'delete') {
              _confirmDelete(context);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red))),
          ],
        ),
        onTap: () {
          // Could navigate to customer detail/history
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text(
            'Delete ${customer.name}? All their milk entries will also be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<CustomerProvider>().remove(customer.id!);
    }
  }
}
