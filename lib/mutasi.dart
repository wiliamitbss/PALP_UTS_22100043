
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MutasiBarangPage extends StatefulWidget {
  final String? defaultProductId;
  final String? defaultFromWarehouseId;

  const MutasiBarangPage({this.defaultProductId, this.defaultFromWarehouseId});

  @override
  _MutasiBarangPageState createState() => _MutasiBarangPageState();
}

class _MutasiBarangPageState extends State<MutasiBarangPage> {
  String? selectedProductId;
  String? fromWarehouseId;
  String? toWarehouseId;
  final TextEditingController quantityController = TextEditingController();

  Future<List<QueryDocumentSnapshot>> fetchCollection(String name) async {
    final snapshot = await FirebaseFirestore.instance.collection(name).get();
    return snapshot.docs;
  }

  Future<void> submitMutation() async {
    final qty = int.tryParse(quantityController.text);

    if (selectedProductId == null ||
        fromWarehouseId == null ||
        toWarehouseId == null ||
        qty == null ||
        qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua field wajib diisi dengan benar')),
      );
      return;
    }

    if (fromWarehouseId == toWarehouseId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gudang asal dan tujuan tidak boleh sama')),
      );
      return;
    }

    final productRef = FirebaseFirestore.instance.collection('products').doc(selectedProductId!);
    final fromWarehouseRef = FirebaseFirestore.instance.collection('warehouses').doc(fromWarehouseId!);
    final toWarehouseRef = FirebaseFirestore.instance.collection('warehouses').doc(toWarehouseId!);


    final mutationData = {
      'product_ref': productRef,
      'from_warehouse': fromWarehouseRef,
      'to_warehouse': toWarehouseRef,
      'qty': qty,
      'timestamp': FieldValue.serverTimestamp(),
    };

    final batch = FirebaseFirestore.instance.batch();

    final mutationDoc = FirebaseFirestore.instance.collection('mutations').doc();
    batch.set(mutationDoc, mutationData);

    // FROM warehouse
    final fromStockQuery = await FirebaseFirestore.instance
        .collection('stocks')
        .where('product_ref', isEqualTo: productRef)
        .where('warehouse_ref', isEqualTo: fromWarehouseRef)
        .limit(1)
        .get();

    if (fromStockQuery.docs.isNotEmpty) {
      final fromStockDoc = fromStockQuery.docs.first;
      final currentQty = (fromStockDoc['qty'] ?? 0) as int;
    
      if (currentQty < qty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stok tidak mencukupi di gudang asal (tersedia: $currentQty)')),
        );
        return;
      }
    
      batch.update(fromStockDoc.reference, {'qty': FieldValue.increment(-qty)});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok di gudang asal tidak tersedia')),
      );
      return;
    }


    // TO warehouse
    final toStockQuery = await FirebaseFirestore.instance
        .collection('stocks')
        .where('product_ref', isEqualTo: productRef)
        .where('warehouse_ref', isEqualTo: toWarehouseRef)
        .limit(1)
        .get();

    if (toStockQuery.docs.isNotEmpty) {
      final doc = toStockQuery.docs.first.reference;
      batch.update(doc, {'qty': FieldValue.increment(qty)});
    } else {
      final newStockDoc = FirebaseFirestore.instance.collection('stocks').doc();
      batch.set(newStockDoc, {
        'product_ref': productRef,
        'warehouse_ref': toWarehouseRef,
        'qty': qty,
      });
    }

    await batch.commit();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mutasi berhasil disimpan dan stok diperbarui')),
    );

    Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    selectedProductId = widget.defaultProductId;
    fromWarehouseId = widget.defaultFromWarehouseId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mutasi Barang')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FutureBuilder(
          future: Future.wait([
            fetchCollection('products'),
            fetchCollection('warehouses'),
          ]),
          builder: (
            context,
            AsyncSnapshot<List<List<QueryDocumentSnapshot>>> snapshot,
          ) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final products = snapshot.data![0];
            final warehouses = snapshot.data![1];

            return ListView(
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Barang'),
                  value: selectedProductId,
                  items: products.map((doc) {
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text(doc['name']),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => selectedProductId = val),
                  validator: (val) => val == null ? 'Pilih barang' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Gudang Asal'),
                  value: fromWarehouseId,
                  items: warehouses.map((doc) {
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text(doc['name']),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => fromWarehouseId = val),
                  validator: (val) => val == null ? 'Pilih gudang asal' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Gudang Tujuan'),
                  value: toWarehouseId,
                  items: warehouses.map((doc) {
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text(doc['name']),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => toWarehouseId = val),
                  validator: (val) => val == null ? 'Pilih gudang tujuan' : null,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: quantityController,
                  decoration: const InputDecoration(labelText: 'Jumlah'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: submitMutation,
                  child: const Text('Kirim Mutasi'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
