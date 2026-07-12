import 'dart:io';

void main() async {
  final env = await File('.env').readAsString();
  final lines = env.split('\n');
  String? url;
  String? key;
  for (var line in lines) {
    if (line.startsWith('SUPABASE_URL=')) url = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_SECRET_KEY=')) key = line.split('=')[1].trim();
  }
  
  const jobId = '19ca1b77-f2a1-4d83-9c38-ee5ea3100835';
  
  final res = await Process.run('curl', [
    '-s',
    '-H', 'apikey: $key',
    '-H', 'Authorization: Bearer $key',
    '$url/rest/v1/mechanic_job_bikes?select=*,bike:bikes(*),status:job_statuses(*)&job_id=eq.$jobId&order=order_index'
  ]);
  print("Job Bikes full query: ${res.stdout}");
}
