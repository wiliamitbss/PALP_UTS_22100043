import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FilteredDataPage extends StatefulWidget {
  const FilteredDataPage({super.key});

  @override
  State<FilteredDataPage> createState() => _FilteredDataPageState();
}

class _FilteredDataPageState extends State<FilteredDataPage> {
  DocumentReference? _storeRef;
  bool _loading = true;
  List<DocumentSnapshot> _suppliers = [];
  List<DocumentSnapshot> _warehouses = [];
  List<DocumentSnapshot> _products = [];
  Map<String, Map<String, int>> _warehouseStocks =
      {}; // productId -> { warehouseId -> qty }

  @override
  void initState() {
    super.initState();
    _loadStoreAndData();
  }

  Future<void> _loadStoreAndData() async {
    final prefs = await SharedPreferences.getInstance();
    final storeRefPath = prefs.getString('store_ref');
    if (storeRefPath == null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    final storeRef = FirebaseFirestore.instance.doc(storeRefPath);

    final supplierSnap =
        await FirebaseFirestore.instance
            .collection('suppliers')
            .where('store_ref', isEqualTo: storeRef)
            .get();

    final warehouseSnap =
        await FirebaseFirestore.instance
            .collection('warehouses')
            .where('store_ref', isEqualTo: storeRef)
            .get();

    final productSnap =
        await FirebaseFirestore.instance
            .collection('products')
            .where('store_ref', isEqualTo: storeRef)
            .get();

    setState(() {
      _storeRef = storeRef;
      _suppliers = supplierSnap.docs;
      _warehouses = warehouseSnap.docs;
      _products = productSnap.docs;
    });

    await _calculateWarehouseStocks();
  }

  Future<void> _calculateWarehouseStocks() async {
    if (_storeRef == null) return;

    final stocksSnapshot = await FirebaseFirestore.instance
        .collection('stocks')
        .get();

    Map<String, Map<String, int>> stockMap = {}; // productId -> { warehouseId -> qty }

    for (var doc in stocksSnapshot.docs) {
      final data = doc.data();
      final productRef = data['product_ref'] as DocumentReference?;
      final warehouseRef = data['warehouse_ref'] as DocumentReference?;
      final qty = data['qty'] ?? 0;

      if (productRef != null && warehouseRef != null) {
        final productId = productRef.id;
        final warehouseId = warehouseRef.id;

        stockMap[productId] ??= {};
        stockMap[productId]![warehouseId] = (qty is int ? qty : (qty as num).toInt());
      }
    }

    setState(() {
      _warehouseStocks = stockMap;
      _loading = false;
    });
  }


  Future<void> _deleteDocument(DocumentReference ref) async {
    await ref.delete();
    await _loadStoreAndData();
  }

  Future<void> _showEditDialog(
    DocumentReference docRef,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Edit Name'),
            content: TextField(controller: controller),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await docRef.update({'name': controller.text.trim()});
                  Navigator.pop(context);
                  await _loadStoreAndData();
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }

  Widget _buildListTile(DocumentSnapshot doc) {
    final docRef = doc.reference;
    final name = doc['name'] ?? '';
    return ListTile(
      title: Text(name),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue),
            onPressed: () => _showEditDialog(docRef, name),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteDocument(docRef),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSection(String title, List<DocumentSnapshot> docs) {
    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      children:
          docs.map((doc) {
            final id = doc.id;
            final name = doc['name'] ?? '';
            final stockByWarehouse = _warehouseStocks[id] ?? {};

            return ExpansionTile(
              title: Text(name),
              subtitle: Text(
                'Total Stok: ${stockByWarehouse.values.fold(0, (a, b) => a + b)}',
              ),
              children:
                  stockByWarehouse.entries.map((entry) {
                    final warehouseId = entry.key;
                    final qty = entry.value;

                    DocumentSnapshot? warehouseDoc;
                    try {
                      warehouseDoc = _warehouses.firstWhere(
                        (w) => w.reference.id == warehouseId,
                      );
                    } catch (e) {
                      warehouseDoc = null;
                    }

                    final warehouseName =
                        warehouseDoc != null
                            ? (warehouseDoc['name'] ?? warehouseId)
                            : 'Unknown Warehouse';

                    return ListTile(
                      title: Text('Gudang: $warehouseName'),
                      subtitle: Text('Stok: $qty'),
                    );
                  }).toList(),
            );
          }).toList(),
    );
  }

  Widget _buildSection(String title, List<DocumentSnapshot> docs) {
    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      children: docs.map(_buildListTile).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Store WS')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _storeRef == null
              ? const Center(child: Text('No store selected'))
              : ListView(
                children: [
                  _buildSection('Suppliers', _suppliers),
                  _buildSection('Warehouses', _warehouses),
                  _buildProductSection('Products', _products),
                ],
              ),
      floatingActionButton: Builder(
        builder:
            (context) => FloatingActionButton(
              heroTag: 'filteredDataFAB',
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
      ),
    );
  }
}
