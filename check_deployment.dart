import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  // Initialize Supabase
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  final client = Supabase.instance.client;

  print('🔍 Checking database schema deployment...\n');

  // 1. Check if expense_lines trigger exists
  try {
    final triggerCheck = await client.rpc('check_trigger_exists', params: {
      'trigger_name': 'trg_expense_lines_change',
      'table_name': 'expense_lines'
    });
    print('✅ expense_lines trigger check: $triggerCheck');
  } catch (e) {
    print('❌ Cannot check trigger (RPC might not exist): $e');
  }

  // 2. Check journal_entries columns
  try {
    final columns = await client
        .from('journal_entries')
        .select('*')
        .limit(1)
        .maybeSingle();
    
    if (columns != null) {
      print('\n📋 journal_entries columns:');
      for (var key in columns.keys) {
        print('  - $key');
      }
      
      if (columns.containsKey('entry_date')) {
        print('\n✅ Column "entry_date" exists');
      } else if (columns.containsKey('date')) {
        print('\n❌ Still using old "date" column - schema not deployed!');
      }
    }
  } catch (e) {
    print('❌ Error checking columns: $e');
  }

  // 3. Check recent expenses and their journals
  try {
    final expenses = await client
        .from('expenses')
        .select('id, expense_number, posting_status, total_amount, created_at')
        .order('created_at', ascending: false)
        .limit(5);

    print('\n📊 Recent expenses:');
    for (var expense in expenses) {
      final lineCount = await client
          .from('expense_lines')
          .select('id')
          .eq('expense_id', expense['id'])
          .count();
      
      final journalCount = await client
          .from('journal_entries')
          .select('id')
          .eq('source_module', 'expenses')
          .eq('source_reference', expense['id'].toString())
          .count();

      print('  ${expense['expense_number']}:');
      print('    Status: ${expense['posting_status']}');
      print('    Lines: ${lineCount.count}');
      print('    Journals: ${journalCount.count}');
      
      if (expense['posting_status'] == 'posted' && journalCount.count == 0) {
        print('    ❌ MISSING JOURNAL ENTRY!');
      } else if (expense['posting_status'] == 'posted' && journalCount.count > 0) {
        print('    ✅ Has journal entry');
      }
    }
  } catch (e) {
    print('❌ Error checking expenses: $e');
  }
}
