import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Generic CRUD operations
  Future<List<Map<String, dynamic>>> select(String table, {String? where}) async {
    try {
      Query<Map<String, dynamic>> query = _firestore.collection(table);
      
      // Simple where clause support (format: "field=value")
      if (where != null && where.contains('=')) {
        final parts = where.split('=');
        final field = parts[0].trim();
        final value = parts[1].trim();
        query = query.where(field, isEqualTo: value);
      }
      
      final querySnapshot = await query.get();
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Add document ID
        return data;
      }).toList();
    } catch (e) {
      if (kDebugMode) print('Database select error: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>?> selectById(String table, String id) async {
    try {
      final docSnapshot = await _firestore.collection(table).doc(id).get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;
        data['id'] = docSnapshot.id;
        return data;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('Database selectById error: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> insert(String table, Map<String, dynamic> data) async {
    try {
      // Add timestamps
      data['created_at'] = FieldValue.serverTimestamp();
      data['updated_at'] = FieldValue.serverTimestamp();
      
      final docRef = await _firestore.collection(table).add(data);
      final docSnapshot = await docRef.get();
      final result = docSnapshot.data()!;
      result['id'] = docRef.id;
      
      notifyListeners();
      return result;
    } catch (e) {
      if (kDebugMode) print('Database insert error: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> update(String table, String id, Map<String, dynamic> data) async {
    try {
      // Update timestamp
      data['updated_at'] = FieldValue.serverTimestamp();
      
      await _firestore.collection(table).doc(id).update(data);
      
      // Fetch updated document
      final docSnapshot = await _firestore.collection(table).doc(id).get();
      final result = docSnapshot.data()!;
      result['id'] = id;
      
      notifyListeners();
      return result;
    } catch (e) {
      if (kDebugMode) print('Database update error: $e');
      rethrow;
    }
  }
  
  Future<void> delete(String table, String id) async {
    try {
      await _firestore.collection(table).doc(id).delete();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Database delete error: $e');
      rethrow;
    }
  }
  
  // Accounting-specific operations
  Future<String> createJournalEntry(Map<String, dynamic> entry, List<Map<String, dynamic>> lines) async {
    try {
      // Use Firestore batch for atomic operations
      final batch = _firestore.batch();
      
      // Create journal entry
      final entryRef = _firestore.collection('journal_entries').doc();
      entry['created_at'] = FieldValue.serverTimestamp();
      entry['updated_at'] = FieldValue.serverTimestamp();
      batch.set(entryRef, entry);
      
      // Create journal lines
      for (final line in lines) {
        final lineRef = _firestore.collection('journal_lines').doc();
        line['entry_id'] = entryRef.id;
        line['created_at'] = FieldValue.serverTimestamp();
        batch.set(lineRef, line);
      }
      
      await batch.commit();
      notifyListeners();
      return entryRef.id;
    } catch (e) {
      if (kDebugMode) print('Journal entry creation error: $e');
      rethrow;
    }
  }
  
  // Inventory operations
  Future<void> adjustStock(String productId, int quantity, String type, String reference) async {
    try {
      // Use Firestore transaction for atomic stock adjustment
      await _firestore.runTransaction((transaction) async {
        // Create stock movement
        final movementRef = _firestore.collection('stock_movements').doc();
        transaction.set(movementRef, {
          'product_id': productId,
          'quantity': quantity,
          'type': type,
          'date': FieldValue.serverTimestamp(),
          'reference': reference,
          'created_at': FieldValue.serverTimestamp(),
        });
        
        // Update product inventory
        final productRef = _firestore.collection('products').doc(productId);
        final productDoc = await transaction.get(productRef);
        
        if (productDoc.exists) {
          final currentQty = productDoc.data()!['inventory_qty'] as int? ?? 0;
          final newQty = type == 'IN' ? currentQty + quantity : currentQty - quantity;
          transaction.update(productRef, {
            'inventory_qty': newQty,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      });
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Stock adjustment error: $e');
      rethrow;
    }
  }
  
  // Search operations
  Future<List<Map<String, dynamic>>> searchRecords(String table, String searchColumn, String searchTerm) async {
    try {
      // Firestore doesn't support case-insensitive search directly
      // This is a simple implementation - for production, consider using Algolia or similar
      final querySnapshot = await _firestore.collection(table).get();
      
      final results = querySnapshot.docs.where((doc) {
        final data = doc.data();
        final value = data[searchColumn]?.toString().toLowerCase() ?? '';
        return value.contains(searchTerm.toLowerCase());
      }).map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      
      return results;
    } catch (e) {
      if (kDebugMode) print('Search error: $e');
      rethrow;
    }
  }
}