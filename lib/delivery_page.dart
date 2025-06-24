import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CrudDeliveryPage extends StatefulWidget {
  const CrudDeliveryPage({super.key});

  @override
  State<CrudDeliveryPage> createState() => _CrudDeliveryPageState();
}

class _CrudDeliveryPageState extends State<CrudDeliveryPage> {
  DocumentReference? _storeRef;
  List<DocumentSnapshot> _deliveries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDeliveries();
  }

  Future<void> _loadDeliveries() async {
    final prefs = await SharedPreferences.getInstance();
    final storeRefPath = prefs.getString('store_ref');

    if (storeRefPath == null || storeRefPath.isEmpty) {
      setState(() {
        _loading = false;
        _storeRef = null;
      });
      return;
    }

    final storeRef = FirebaseFirestore.instance.doc(storeRefPath);
    final snapshot = await FirebaseFirestore.instance
        .collection('deliveries')
        .where('store_ref', isEqualTo: storeRef)
        .get();

    setState(() {
      _storeRef = storeRef;
      _deliveries = snapshot.docs;
      _loading = false;
    });
  }

  void _openAddForm() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryFormPage(storeRef: _storeRef!),
      ),
    );
    if (result == true) await _loadDeliveries();
  }

  void _openEditForm(DocumentSnapshot doc) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryFormPage(storeRef: _storeRef!, deliveryDoc: doc),
      ),
    );
    if (result == true) await _loadDeliveries();
  }

  void _selectStore() async {
    final stores = await FirebaseFirestore.instance.collection('stores').get();
    DocumentReference? selected;

    await showDialog(
      context: context,
      builder: (context) {
        DocumentReference? temp;
        return AlertDialog(
          title: const Text("Select Store"),
          content: DropdownButtonFormField<DocumentReference>(
            items: stores.docs.map((doc) {
              return DropdownMenuItem(
                value: doc.reference,
                child: Text(doc['name']),
              );
            }).toList(),
            onChanged: (value) => temp = value,
            decoration: const InputDecoration(labelText: "Store"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                selected = temp;
                Navigator.pop(context);
              },
              child: const Text("Select"),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('store_ref', selected!.path);
      await _loadDeliveries();
    }
  }

  void _deleteDelivery(DocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: const Text("Delete this delivery?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  
    if (confirm == true) {
      final batch = FirebaseFirestore.instance.batch();
      final detailsSnap = await doc.reference.collection('details').get();
      final data = doc.data() as Map<String, dynamic>;
      final warehouseRef = data['warehouse_ref'] as DocumentReference?;
  
      for (var detailDoc in detailsSnap.docs) {
        final detail = detailDoc.data();
        final qty = detail['qty'] ?? 0;
        final productRef = detail['product_ref'] as DocumentReference?;
  
        // Restore product stock
        if (productRef != null) {
          batch.update(productRef, {'qty': FieldValue.increment(qty)});
        }
  
        // Restore warehouse stock
        if (productRef != null && warehouseRef != null) {
          final stockQuery = await FirebaseFirestore.instance
              .collection('stocks')
              .where('product_ref', isEqualTo: productRef)
              .where('warehouse_ref', isEqualTo: warehouseRef)
              .limit(1)
              .get();
  
          if (stockQuery.docs.isNotEmpty) {
            final stockDoc = stockQuery.docs.first.reference;
            batch.update(stockDoc, {'qty': FieldValue.increment(qty)});
          }
        }
  
        batch.delete(detailDoc.reference);
      }
  
      batch.delete(doc.reference);
  
      await batch.commit();
      await _loadDeliveries();
  
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery deleted')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries'),
        backgroundColor: Colors.teal,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _storeRef == null
              ? Center(
                  child: ElevatedButton.icon(
                    onPressed: _selectStore,
                    icon: const Icon(Icons.store),
                    label: const Text("Select Store"),
                  ),
                )
              : _deliveries.isEmpty
                  ? const Center(child: Text('No deliveries yet.'))
                  : ListView.builder(
                      itemCount: _deliveries.length,
                      itemBuilder: (context, index) {
                        final data = _deliveries[index].data() as Map<String, dynamic>;
                        final doc = _deliveries[index];
                        return Card(
                          color: Colors.teal.shade50,
                          margin: const EdgeInsets.all(10),
                          child: ListTile(
                            title: Text(
                              "No. Form: ${data['no_form'] ?? '-'}",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Grand Total: ${data['grandtotal'] ?? 0}"),
                                Text("Item Total: ${data['item_total'] ?? 0}"),
                                Text("Posted: ${data['post_date'] ?? '-'}"),
                              ],
                            ),
                            onTap: () => _openEditForm(doc),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteDelivery(doc),
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: _openAddForm,
        child: const Icon(Icons.add),
        tooltip: 'Add Delivery',
      ),
    );
  }
}

class DeliveryFormPage extends StatefulWidget {
  final DocumentReference storeRef;
  final DocumentSnapshot? deliveryDoc;

  const DeliveryFormPage({
    super.key,
    required this.storeRef,
    this.deliveryDoc,
  });

  @override
  State<DeliveryFormPage> createState() => _DeliveryFormPageState();
}

class _DeliveryFormPageState extends State<DeliveryFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _formNumberController = TextEditingController();
  DocumentReference? _destinationStore, _warehouse;
  List<DocumentSnapshot> _stores = [], _warehouses = [], _products = [];
  final List<_DetailItem> _details = [];
  bool _loading = true;

  int get itemTotal => _details.fold(0, (sum, item) => sum + item.qty);
  int get grandTotal => _details.fold(0, (sum, item) => sum + item.subtotal);
  bool get isEditing => widget.deliveryDoc != null;

  @override
  void initState() {
    super.initState();
    _fetchDropdowns();
  }

  Future<void> _fetchDropdowns() async {
    final prefs = await SharedPreferences.getInstance();
    final storeRefPath = prefs.getString('store_ref');

    if (storeRefPath == null || storeRefPath.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    final storeRef = FirebaseFirestore.instance.doc(storeRefPath);

    final storeSnap = await FirebaseFirestore.instance
        .collection('stores')
        .where(FieldPath.documentId, isNotEqualTo: storeRef.id)
        .get();

    final warehouseSnap = await FirebaseFirestore.instance
        .collection('warehouses')
        .where('store_ref', isEqualTo: storeRef)
        .get();

    final productSnap = await FirebaseFirestore.instance
        .collection('products')
        .where('store_ref', isEqualTo: storeRef)
        .get();

    if (isEditing) {
      final data = widget.deliveryDoc!.data() as Map<String, dynamic>;
      _formNumberController.text = data['no_form'];
      _destinationStore = data['destination_store_ref'] as DocumentReference?;
      _warehouse = data['warehouse_ref'] as DocumentReference?;

      final detailsSnap = await widget.deliveryDoc!.reference.collection('details').get();
      for (var doc in detailsSnap.docs) {
        _details.add(_DetailItem.fromMap(doc.data(), productSnap.docs, doc.reference));
      }
    }

    setState(() {
      _stores = storeSnap.docs;
      _warehouses = warehouseSnap.docs;
      _products = productSnap.docs;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _details.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();

    // 1. Check stock availability
    for (var item in _details) {
      final stockQuery = await FirebaseFirestore.instance
          .collection('stocks')
          .where('product_ref', isEqualTo: item.productRef)
          .where('warehouse_ref', isEqualTo: _warehouse)
          .limit(1)
          .get();

      final availableQty = stockQuery.docs.isNotEmpty ? (stockQuery.docs.first['qty'] ?? 0) : 0;

      if (availableQty < item.qty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stok tidak cukup untuk produk: ${_getProductName(item.productRef)}')),
        );
        return;
      }
    }

    final data = {
      'no_form': _formNumberController.text.trim(),
      'grandtotal': grandTotal,
      'item_total': itemTotal,
      'post_date': DateTime.now().toIso8601String(),
      'store_ref': widget.storeRef,
      'destination_store_ref': _destinationStore,
      'warehouse_ref': _warehouse,
      'synced': true,
    };

    if (isEditing) {
      final ref = widget.deliveryDoc!.reference;
      await ref.update(data);

      // Revert previous stock changes
      final existingDetails = await ref.collection('details').get();
      for (var doc in existingDetails.docs) {
        final d = doc.data();
        final prevProductRef = d['product_ref'] as DocumentReference;
        final prevQty = d['qty'] ?? 0;

        // Revert product stock
        batch.update(prevProductRef, {'qty': FieldValue.increment(prevQty)});

        // Revert warehouse stock
        final prevStockQuery = await FirebaseFirestore.instance
            .collection('stocks')
            .where('product_ref', isEqualTo: prevProductRef)
            .where('warehouse_ref', isEqualTo: _warehouse)
            .limit(1)
            .get();

        if (prevStockQuery.docs.isNotEmpty) {
          final stockDoc = prevStockQuery.docs.first.reference;
          batch.update(stockDoc, {'qty': FieldValue.increment(prevQty)});
        }
      }

      // Delete old detail docs
      for (var doc in existingDetails.docs) {
        batch.delete(doc.reference);
      }

      // Add updated details and subtract stock
      for (var item in _details) {
        final detailRef = ref.collection('details').doc();
        batch.set(detailRef, item.toMap());

        // Decrement product stock
        batch.update(item.productRef!, {'qty': FieldValue.increment(-item.qty)});

        // Decrement warehouse stock
        final stockQuery = await FirebaseFirestore.instance
            .collection('stocks')
            .where('product_ref', isEqualTo: item.productRef)
            .where('warehouse_ref', isEqualTo: _warehouse)
            .limit(1)
            .get();

        if (stockQuery.docs.isNotEmpty) {
          final stockDoc = stockQuery.docs.first.reference;
          batch.update(stockDoc, {'qty': FieldValue.increment(-item.qty)});
        }
      }
    } else {
      // New delivery
      data['created_at'] = DateTime.now();
      final ref = FirebaseFirestore.instance.collection('deliveries').doc();
      batch.set(ref, data);

      for (var item in _details) {
        final detailRef = ref.collection('details').doc();
        batch.set(detailRef, item.toMap());

        // Decrement product stock
        batch.update(item.productRef!, {'qty': FieldValue.increment(-item.qty)});

        // Decrement warehouse stock
        final stockQuery = await FirebaseFirestore.instance
            .collection('stocks')
            .where('product_ref', isEqualTo: item.productRef)
            .where('warehouse_ref', isEqualTo: _warehouse)
            .limit(1)
            .get();

        if (stockQuery.docs.isNotEmpty) {
          final stockDoc = stockQuery.docs.first.reference;
          batch.update(stockDoc, {'qty': FieldValue.increment(-item.qty)});
        }
      }
    }

    // Finally commit all changes
    await batch.commit();
    if (mounted) Navigator.pop(context, true);
  }


  String _getProductName(DocumentReference? ref) {
    final doc = _products.cast<DocumentSnapshot<Map<String, dynamic>>>()
        .where((e) => e.reference == ref)
        .cast<DocumentSnapshot<Map<String, dynamic>>>()
        .firstOrNull;
  
    return doc != null ? doc['name'] ?? '-' : '-';
  }

  void _addDetail() => setState(() => _details.add(_DetailItem(products: _products)));

  void _removeDetail(int index) => setState(() => _details.removeAt(index));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isEditing ? Colors.deepOrange : Colors.teal,
        title: Text(isEditing ? 'Edit Delivery' : 'Add Delivery'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(
                      controller: _formNumberController,
                      decoration: const InputDecoration(labelText: 'No. Form'),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    DropdownButtonFormField<DocumentReference>(
                      value: _destinationStore,
                      items: _stores.map((doc) {
                        return DropdownMenuItem(
                          value: doc.reference,
                          child: Text(doc['name']),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _destinationStore = v),
                      decoration: const InputDecoration(labelText: 'Destination Store'),
                    ),
                    DropdownButtonFormField<DocumentReference>(
                      value: _warehouse,
                      items: _warehouses.map((doc) {
                        return DropdownMenuItem(
                          value: doc.reference,
                          child: Text(doc['name']),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _warehouse = v),
                      decoration: const InputDecoration(labelText: 'Warehouse'),
                    ),
                    const SizedBox(height: 16),
                    const Text("Details", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._details.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return Card(
                        color: Colors.grey.shade100,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              DropdownButtonFormField<DocumentReference>(
                                value: item.productRef,
                                items: _products.map((doc) {
                                  return DropdownMenuItem(
                                    value: doc.reference,
                                    child: Text(doc['name']),
                                  );
                                }).toList(),
                                onChanged: (v) => setState(() {
                                  item.productRef = v;
                                  item.unitName = 'unit';
                                }),
                                decoration: const InputDecoration(labelText: 'Product'),
                              ),
                              TextFormField(
                                initialValue: item.price.toString(),
                                decoration: const InputDecoration(labelText: 'Price'),
                                keyboardType: TextInputType.number,
                                onChanged: (val) => setState(() => item.price = int.tryParse(val) ?? 0),
                              ),
                              TextFormField(
                                initialValue: item.qty.toString(),
                                decoration: const InputDecoration(labelText: 'Qty'),
                                keyboardType: TextInputType.number,
                                onChanged: (val) => setState(() => item.qty = int.tryParse(val) ?? 1),
                              ),
                              Text("Unit: ${item.unitName}"),
                              Text("Subtotal: ${item.subtotal}"),
                              TextButton.icon(
                                onPressed: () => _removeDetail(index),
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                label: const Text("Remove"),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text("Add Detail"),
                      onPressed: _addDetail,
                    ),
                    const SizedBox(height: 16),
                    Text("Item Total: $itemTotal"),
                    Text("Grand Total: $grandTotal"),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _save,
                      child: Text(isEditing ? 'Update' : 'Save'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _DetailItem {
  DocumentReference? productRef;
  int price;
  int qty;
  String unitName;
  final List<DocumentSnapshot> products;
  final DocumentReference? ref;

  _DetailItem({
    this.productRef,
    this.price = 0,
    this.qty = 1,
    this.unitName = 'unit',
    required this.products,
    this.ref,
  });

  factory _DetailItem.fromMap(
    Map<String, dynamic> data,
    List<DocumentSnapshot> products,
    DocumentReference ref,
  ) {
    return _DetailItem(
      productRef: data['product_ref'] as DocumentReference?,
      price: data['price'] ?? 0,
      qty: data['qty'] ?? 1,
      unitName: data['unit_name'] ?? 'unit',
      products: products,
      ref: ref,
    );
  }

  int get subtotal => price * qty;

  Map<String, dynamic> toMap() => {
        'product_ref': productRef,
        'price': price,
        'qty': qty,
        'unit_name': unitName,
        'subtotal': subtotal,
      };
}