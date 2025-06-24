import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddSupplierPage extends StatefulWidget {
  const AddSupplierPage({super.key});

  @override
  State<AddSupplierPage> createState() => _AddSupplierPageState();
}

class _AddSupplierPageState extends State<AddSupplierPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  DocumentReference? _storeRef;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStoreRef();
  }

  Future<void> _loadStoreRef() async {
    final prefs = await SharedPreferences.getInstance();
    final storePath = prefs.getString('store_ref');
    if (storePath != null) {
      setState(() {
        _storeRef = FirebaseFirestore.instance.doc(storePath);
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
      });
      // Bisa tambahkan notif atau dialog kalau store belum dipilih
    }
  }

  Future<void> _saveSupplier() async {
    if (!_formKey.currentState!.validate() || _storeRef == null) return;

    try {
      await FirebaseFirestore.instance.collection('suppliers').add({
        'name': _nameController.text.trim(),
        'store_ref': _storeRef,
        'created_at': DateTime.now(),
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Tangani error simpan data
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving supplier: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_storeRef == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Store belum dipilih, mohon pilih store terlebih dahulu.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Add Supplier")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Supplier Name"),
                validator:
                    (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveSupplier,
                child: const Text("Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
