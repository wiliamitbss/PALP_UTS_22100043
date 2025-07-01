// ✅ Full cleaned code without product dropdown
// The `_buildProductSection` is still shown, as it summarizes stock per product.

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
  List<DocumentSnapshot> _stocks = [];

  Map<String, Map<String, int>> _warehouseStocks = {};
  Map<String, List<Map<String, dynamic>>> _stocksByWarehouse = {};

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

    final supplierSnap = await FirebaseFirestore.instance
        .collection('suppliers')
        .where('store_ref', isEqualTo: storeRef)
        .get();

    final warehouseSnap =
        await FirebaseFirestore.instance.collection('warehouses').get();

    final productSnap = await FirebaseFirestore.instance
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
    await _loadStocksPerWarehouse();
  }

  Future<void> _calculateWarehouseStocks() async {
    if (_storeRef == null) return;

    Map<String, Map<String, int>> stockMap = {};

    final receiptSnap = await FirebaseFirestore.instance
        .collection('purchaseGoodsReceipts')
        .where('store_ref', isEqualTo: _storeRef)
        .get();

    for (var receiptDoc in receiptSnap.docs) {
      final receiptData = receiptDoc.data();
      final warehouseRef = receiptData['warehouse_ref'] as DocumentReference?;
      final warehouseId = warehouseRef?.id;
      if (warehouseId == null) continue;

      final detailsSnap =
          await receiptDoc.reference.collection('details').get();
      for (var detailDoc in detailsSnap.docs) {
        final detailData = detailDoc.data();
        final productRef = detailData['product_ref'] as DocumentReference?;
        final productId = productRef?.id;
        final qty = detailData['qty'] ?? 0;

        if (productId == null) continue;

        stockMap[productId] ??= {};
        stockMap[productId]![warehouseId] =
            (stockMap[productId]![warehouseId] ?? 0) +
                (qty is int ? qty : (qty as num).toInt());
      }
    }

    final mutationSnap = await FirebaseFirestore.instance
        .collection('mutations')
        .where('product_ref.store_ref', isEqualTo: _storeRef)
        .get();

    for (var mutationDoc in mutationSnap.docs) {
      final mutationData = mutationDoc.data();
      final productRef = mutationData['product_ref'] as DocumentReference?;
      final fromWarehouseRef =
          mutationData['from_warehouse'] as DocumentReference?;
      final toWarehouseRef =
          mutationData['to_warehouse'] as DocumentReference?;
      final qty = mutationData['qty'] ?? 0;

      final productId = productRef?.id;
      final fromWarehouseId = fromWarehouseRef?.id;
      final toWarehouseId = toWarehouseRef?.id;

      if (productId == null ||
          fromWarehouseId == null ||
          toWarehouseId == null) continue;

      stockMap[productId] ??= {};
      final intQty = qty is int ? qty : (qty as num).toInt();

      stockMap[productId]![fromWarehouseId] =
          (stockMap[productId]![fromWarehouseId] ?? 0) - intQty;
      stockMap[productId]![toWarehouseId] =
          (stockMap[productId]![toWarehouseId] ?? 0) + intQty;
    }

    setState(() {
      _warehouseStocks = stockMap;
    });
  }

  Future<void> _loadStocksPerWarehouse() async {
    final stocksSnap =
        await FirebaseFirestore.instance.collection('stocks').get();
    _stocks = stocksSnap.docs;

    final productRefs = _stocks
        .map((s) {
          final ref = s['product_ref'];
          if (ref is DocumentReference) {
            return ref;
          } else if (ref is String) {
            return FirebaseFirestore.instance.doc(ref);
          }
          return null;
        })
        .whereType<DocumentReference>()
        .toSet()
        .toList();

    final productIds = productRefs.map((e) => e.id).take(10).toList();
    if (productIds.isEmpty) {
      setState(() {
        _stocksByWarehouse = {};
        _loading = false;
      });
      return;
    }

    final productDocs = await FirebaseFirestore.instance
        .collection('products')
        .where(FieldPath.documentId, whereIn: productIds)
        .get();

    final productMap = {for (var d in productDocs.docs) d.reference.path: d};

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var stock in _stocks) {
      final productRef = stock['product_ref'];
      final warehouseRef = stock['warehouse_ref'];
      final qty = stock['qty'] ?? 0;

      DocumentReference? productRefObj;
      if (productRef is DocumentReference) {
        productRefObj = productRef;
      } else if (productRef is String) {
        productRefObj = FirebaseFirestore.instance.doc(productRef);
      }

      DocumentReference? warehouseRefObj;
      if (warehouseRef is DocumentReference) {
        warehouseRefObj = warehouseRef;
      } else if (warehouseRef is String) {
        warehouseRefObj = FirebaseFirestore.instance.doc(warehouseRef);
      }

      if (productRefObj == null || warehouseRefObj == null) continue;

      final warehouseId = warehouseRefObj.id;
      final productName =
          productMap[productRefObj.path]?['name'] ?? 'Unknown Product';

      grouped[warehouseId] ??= [];
      grouped[warehouseId]!.add({
        'productName': productName,
        'qty': qty,
      });
    }

    setState(() {
      _stocksByWarehouse = grouped;
      _loading = false;
    });
  }

  Future<void> _deleteDocument(DocumentReference ref) async {
    await ref.delete();
    await _loadStoreAndData();
  }

  Future<void> _showEditDialog(
      DocumentReference docRef, String currentName) async {
    final controller = TextEditingController(text: currentName);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
      children: docs.map((doc) {
        final id = doc.id;
        final name = doc['name'] ?? '';
        final stockByWarehouse = _warehouseStocks[id] ?? {};
        final totalStock = stockByWarehouse.values.fold(0, (a, b) => a + b);

        return ExpansionTile(
          title: Text(name),
          subtitle: Text('Total Stok: ${totalStock < 0 ? 0 : totalStock}'),
          children: stockByWarehouse.entries.map((entry) {
            final warehouseId = entry.key;
            final qty = entry.value;

            DocumentSnapshot? warehouseDoc;
            try {
              warehouseDoc = _warehouses
                  .firstWhere((w) => w.reference.id == warehouseId);
            } catch (e) {
              warehouseDoc = null;
            }

            final warehouseName = warehouseDoc != null
                ? (warehouseDoc['name'] ?? warehouseId)
                : 'Unknown Warehouse';

            return ListTile(
              title: Text('Gudang: $warehouseName'),
              subtitle: Text('Stok: ${qty < 0 ? 0 : qty}'),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _buildWarehouseWithStocksSection() {
    return ExpansionTile(
      title:
          const Text('Warehouses', style: TextStyle(fontWeight: FontWeight.bold)),
      children: _warehouses.map((warehouseDoc) {
        final warehouseId = warehouseDoc.id;
        final warehouseName = warehouseDoc['name'] ?? warehouseId;
        final stocks = _stocksByWarehouse[warehouseId] ?? [];

        return ExpansionTile(
          title: Text(warehouseName),
          subtitle: Text('Jumlah Produk: ${stocks.length}'),
          children: stocks.map((stock) {
            final productName = stock['productName'];
            final qty = stock['qty'];
            return ListTile(
              title: Text('Produk: $productName'),
              subtitle: Text('Qty: $qty'),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _storeRef == null
              ? const Center(child: Text('No store selected'))
              : ListView(
                  children: [
                    _buildSection('Suppliers', _suppliers),
                    _buildWarehouseWithStocksSection(),
                    _buildProductSection('Products', _products),
                  ],
                ),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton(
          heroTag: 'filteredDataFAB',
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
