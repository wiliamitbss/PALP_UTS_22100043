import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _stockController = TextEditingController(); // Tambahan
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

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate() || _storeRef == null) return;

    final quantity = int.tryParse(_stockController.text.trim()) ?? 0;

    // Simpan produk
    final productRef = await FirebaseFirestore.instance.collection('products').add({
      'name': _nameController.text.trim(),
      'store_ref': _storeRef,
      'created_at': DateTime.now(),
    });

    // Buat receipt dummy untuk stok awal
    final receiptDoc = await FirebaseFirestore.instance.collection('purchaseGoodsReceipts').add({
      'store_ref': _storeRef,
      'no_form': 'INIT-${DateTime.now().millisecondsSinceEpoch}',
      'created_at': DateTime.now(),
    });

    // Tambahkan detail quantity
    await receiptDoc.collection('details').add({
      'product_ref': productRef,
      'quantity': quantity,
    });

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Product")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Product Name"),
                validator: (val) => val!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: "Initial Stock"),
                keyboardType: TextInputType.number,
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveProduct,
                child: const Text("Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
