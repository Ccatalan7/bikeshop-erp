import 'dart:io';
import 'dart:convert';

void main() async {
  final lines = File('.env').readAsLinesSync();
  String? key;
  for (final line in lines) {
    if (line.startsWith('SUPABASE_SERVICE_ROLE_KEY=')) {
      key = line.split('=')[1].trim();
    }
  }

  if (key == null) {
    print('No SUPABASE_SERVICE_ROLE_KEY found in .env');
    return;
  }

  // Use the local project's supabase connection config if we can't find an http client,
  // but let's just use dart:io HttpClient which is built-in.

  final client = HttpClient();
  final url1 = Uri.parse(
      'https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/job_subjects?select=id,name&limit=1');
  final url2 = Uri.parse(
      'https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/mechanic_jobs?select=id,job_type,warranty_outcome,quotation_status&limit=1');

  print('\n--- Verifying Job Subjects ---');
  final req1 = await client.getUrl(url1);
  req1.headers.add('apikey', key);
  req1.headers.add('Authorization', 'Bearer $key');
  final res1 = await req1.close();
  final body1 = await res1.transform(utf8.decoder).join();
  if (res1.statusCode == 200) {
    print('✅ job_subjects table exists! Response: $body1');
  } else {
    print('❌ Error checking job_subjects: $body1');
  }

  print('\n--- Verifying Mechanic Jobs Columns ---');
  final req2 = await client.getUrl(url2);
  req2.headers.add('apikey', key);
  req2.headers.add('Authorization', 'Bearer $key');
  final res2 = await req2.close();
  final body2 = await res2.transform(utf8.decoder).join();
  if (res2.statusCode == 200) {
    print('✅ mechanic_jobs updated correctly! Response: $body2');
  } else {
    print('❌ Columns might be missing! Error: $body2');
  }

  client.close();
}
