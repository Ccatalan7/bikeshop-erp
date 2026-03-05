import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse('https://api.veryfi.com/api/v8/partner/documents');
  
  final httpClient = HttpClient();
  try {
    final request = await httpClient.postUrl(url);
    
    // As per screenshot:
    request.headers.add('Accept', 'application/json');
    request.headers.add('CLIENT-ID', 'vrf0cpkTSPBjL7G6LOmSwh8WcsdieM4Yt5zXD1a');
    request.headers.add('AUTHORIZATION', 'apikey ccatalansandoval7:be662bb3cf5cb863e2033ecd4fbfe47f');
    
    final response = await request.close();
    print('Status: ${response.statusCode}');
    
    final body = await response.transform(utf8.decoder).join();
    print('Body: $body');
  } catch (e) {
    print('Error: $e');
  } finally {
    httpClient.close();
  }
}
