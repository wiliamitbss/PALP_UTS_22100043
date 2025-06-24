import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeleteReceiptPage extends StatefulWidget {
  const DeleteReceiptPage({super.key});

  @override
  State<DeleteReceiptPage> createState() => _DeleteReceiptPageState();
}

class _DeleteReceiptPageState extends State<DeleteReceiptPage> {
  DocumentReference? _storeRef;
  List<DocumentSnapshot> _receipts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    final prefs = await SharedPreferences.getInstance();
    final storeRefPath = prefs.getString('store_ref');
    if (storeRefPath == null) return;

    _storeRef = FirebaseFirestore.instance.doc(storeRefPath);
    final snapshot =
        await FirebaseFirestore.instance
            .collection('purchaseGoodsReceipts')
            .where('store_ref', isEqualTo: _storeRef)
            .get();

    setState(() {
      _receipts = snapshot.docs;
      _loading = false;
    });
  }

  Future<void> _deleteReceipt(DocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Delete Receipt"),
            content: Text("Are you sure you want to delete ${doc['no_form']}?"),
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
      final details = await doc.reference.collection('details').get();
      for (var d in details.docs) {
        await d.reference.delete();
      }
      await doc.reference.delete();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Receipt deleted.")));
      _loadReceipts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete Receipts'),
        backgroundColor: Colors.red,
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _receipts.isEmpty
              ? const Center(child: Text('No receipts found.'))
              : ListView.builder(
                itemCount: _receipts.length,
                itemBuilder: (context, index) {
                  final data = _receipts[index].data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(data['no_form']),
                    subtitle: Text("Grand Total: ${data['grandtotal']}"),
                    trailing: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => _deleteReceipt(_receipts[index]),
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                    ),
                  );
                },
              ),
    );
  }
}
