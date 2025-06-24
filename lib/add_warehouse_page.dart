// Hampir identik dengan AddSupplierPage, hanya beda koleksi
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddWarehousePage extends StatefulWidget {
  const AddWarehousePage({super.key});

  @override
  State<AddWarehousePage> createState() => _AddWarehousePageState();
}

class _AddWarehousePageState extends State<AddWarehousePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  DocumentReference? _storeRef;

  @override
  void initState() {
    super.initState();
    _loadStoreRef();
  }

  Future<void> _loadStoreRef() async {
    final prefs = await SharedPreferences.getInstance();
    final storePath = prefs.getString('store_ref');
    if (storePath != null) {
      setState(() => _storeRef = FirebaseFirestore.instance.doc(storePath));
    }
  }

  Future<void> _saveWarehouse() async {
    if (!_formKey.currentState!.validate() || _storeRef == null) return;

    await FirebaseFirestore.instance.collection('warehouses').add({
      'name': _nameController.text.trim(),
      'store_ref': _storeRef,
      'created_at': DateTime.now(),
    });

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Warehouse")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Warehouse Name"),
                validator: (val) => val!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveWarehouse,
                child: const Text("Save"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
