import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReceiptFormPage extends StatefulWidget {
  final String? receiptId;

  const ReceiptFormPage({this.receiptId});

  @override
  State<ReceiptFormPage> createState() => _ReceiptFormPageState();
}

class _ReceiptFormPageState extends State<ReceiptFormPage> {
  final _formKey = GlobalKey<FormState>();
  bool isEdit = false;
  List<Map<String, dynamic>> details = [];

  String? selectedStoreName;
  String? selectedSupplierId;
  String? selectedWarehouseId;

  String? selectedSupplierName;
  String? selectedWarehouseName;

  double grandTotal = 0;
  double itemTotal = 0;

  @override
  void initState() {
    super.initState();
    isEdit = widget.receiptId != null;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    selectedStoreName = prefs.getString('store_name');

    if (isEdit) {
      final doc = await FirebaseFirestore.instance
          .collection('purchaseGoodsReceipts')
          .doc(widget.receiptId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        selectedSupplierId = data['supplier_ref'].id;
        selectedWarehouseId = data['warehouse_ref'].id;

        // Ambil nama supplier dan warehouse
        final supplierDoc = await data['supplier_ref'].get();
        selectedSupplierName = supplierDoc['name'];

        final warehouseDoc = await data['warehouse_ref'].get();
        selectedWarehouseName = warehouseDoc['name'];

        // Ambil detail produk
        final detailSnap = await doc.reference.collection('details').get();
        details = detailSnap.docs.map((e) => e.data()).toList();

        // Hitung ulang total
        _calculateTotals();
        setState(() {});
      }
    } else {
      setState(() {});
    }
  }

  void _calculateTotals() {
    itemTotal = details.fold(0, (sum, item) => sum + item['qty']);
    grandTotal = details.fold(0, (sum, item) => sum + item['subtotal']);
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      if (details.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Daftar produk tidak boleh kosong")),
        );
        return;
      }

      final storeRef = FirebaseFirestore.instance
          .collection('stores')
          .where('name', isEqualTo: selectedStoreName)
          .limit(1);
      final storeSnap = await storeRef.get();
      final storeDoc = storeSnap.docs.first;

      final receiptData = {
        'store_ref': storeDoc.reference,
        'supplier_ref': FirebaseFirestore.instance.collection('suppliers').doc(selectedSupplierId),
        'warehouse_ref': FirebaseFirestore.instance.collection('warehouses').doc(selectedWarehouseId),
        'grandtotal': grandTotal,
        'item_total': itemTotal,
        'created_at': FieldValue.serverTimestamp(),
        'post_date': DateTime.now(),
        'synced': false,
      };

      if (isEdit) {
        final receiptRef = FirebaseFirestore.instance.collection('purchaseGoodsReceipts').doc(widget.receiptId);
        await receiptRef.update(receiptData);

        // Hapus dan tulis ulang details
        final oldDetails = await receiptRef.collection('details').get();
        for (var doc in oldDetails.docs) {
          await doc.reference.delete();
        }
        for (var item in details) {
          await receiptRef.collection('details').add(item);
        }
      } else {
        final receiptRef = await FirebaseFirestore.instance.collection('purchaseGoodsReceipts').add(receiptData);
        for (var item in details) {
          await receiptRef.collection('details').add(item);
        }
      }

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Receipt' : 'Tambah Receipt')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Store (readonly dari SharedPreferences)
              TextFormField(
                readOnly: true,
                initialValue: selectedStoreName ?? '',
                decoration: InputDecoration(labelText: 'Toko'),
              ),

              // Supplier
              isEdit
                  ? TextFormField(
                      readOnly: true,
                      initialValue: selectedSupplierName ?? '',
                      decoration: InputDecoration(labelText: 'Supplier'),
                    )
                  : FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance.collection('suppliers').get(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return CircularProgressIndicator();
                        final suppliers = snapshot.data!.docs;
                        return DropdownButtonFormField<String>(
                          value: selectedSupplierId,
                          items: suppliers.map((e) {
                            return DropdownMenuItem(
                              value: e.id,
                              child: Text(e['name']),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedSupplierId = value!;
                            });
                          },
                          decoration: InputDecoration(labelText: 'Supplier'),
                          validator: (value) => value == null ? 'Pilih supplier' : null,
                        );
                      },
                    ),

              // Warehouse
              isEdit
                  ? TextFormField(
                      readOnly: true,
                      initialValue: selectedWarehouseName ?? '',
                      decoration: InputDecoration(labelText: 'Gudang'),
                    )
                  : FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance.collection('warehouses').get(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return CircularProgressIndicator();
                        final warehouses = snapshot.data!.docs;
                        return DropdownButtonFormField<String>(
                          value: selectedWarehouseId,
                          items: warehouses.map((e) {
                            return DropdownMenuItem(
                              value: e.id,
                              child: Text(e['name']),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedWarehouseId = value!;
                            });
                          },
                          decoration: InputDecoration(labelText: 'Gudang'),
                          validator: (value) => value == null ? 'Pilih gudang' : null,
                        );
                      },
                    ),

              const SizedBox(height: 20),

              // Tombol tambah produk
              ElevatedButton(
                onPressed: () {
                  // Tambah produk ke details (implementasi sendiri)
                },
                child: Text('Tambah Produk'),
              ),

              const SizedBox(height: 20),

              // Tombol simpan
              ElevatedButton(
                onPressed: _submit,
                child: Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
