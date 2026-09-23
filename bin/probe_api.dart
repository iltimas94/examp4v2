// Probe diagnostik (bukan bagian aplikasi): memeriksa perilaku POST Apps Script
// dari Dart — apakah redirect 302 dipertahankan sebagai POST+body atau
// diubah jadi GET (menentukan apakah klien perlu follow redirect manual).
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String url =
    'https://script.google.com/macros/s/AKfycbyZZTiWMClqOPcRg4vtohaL7cX1gnmuhDjqS7lSfZB0Hj62GUQ9MF9-rdTxhOvCbtc/exec';

String potong(String s, int n) =>
    s.replaceAll('\n', ' ').replaceAll('\r', '').substring(0, s.length.clamp(0, n));

Future<void> main() async {
  final body = jsonEncode({'action': 'getDataLogin'});

  // 1) package:http — persis seperti yang dipakai aplikasi (cbt_api.dart).
  try {
    final r = await http
        .post(Uri.parse(url),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: body)
        .timeout(const Duration(seconds: 45));
    print('1) http.post       => HTTP ${r.statusCode}, ${r.bodyBytes.length} bytes');
    print('   awal body       => ${potong(utf8.decode(r.bodyBytes), 220)}');
  } catch (e) {
    print('1) http.post ERROR => $e');
  }

  // 2) dart:io HttpClient followRedirects=true (perilaku redirect bawaan).
  try {
    final c = HttpClient();
    final req = await c.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    req.write(body);
    final resp = await req.close().timeout(const Duration(seconds: 45));
    final txt = await utf8.decoder.bind(resp).join();
    print('2) io(redirect on) => HTTP ${resp.statusCode}, ${txt.length} bytes');
    print('   awal body       => ${potong(txt, 220)}');
    c.close();
  } catch (e) {
    print('2) io ERROR        => $e');
  }

  // 3) dart:io tanpa redirect — ekspos status 302 + Location.
  try {
    final c = HttpClient()..autoUncompress = false;
    final req = await c.postUrl(Uri.parse(url));
    req.followRedirects = false;
    req.headers.contentType = ContentType.json;
    req.write(body);
    final resp = await req.close().timeout(const Duration(seconds: 45));
    print('3) io(redirect off)=> HTTP ${resp.statusCode}, '
        'location=${resp.headers.value('location')?.substring(0, 80)}...');
    c.close();
  } catch (e) {
    print('3) io ERROR        => $e');
  }

  // 4) RESEP TERVERIFIKASI: POST /exec -> 302 -> GET polos ke Location
  //    (tanpa header kustom, tanpa body) -> echo eksekusi -> JSON doPost.
  try {
    final c = HttpClient();
    final rq = await c.postUrl(Uri.parse(url));
    rq.followRedirects = false;
    rq.headers.contentType = ContentType.json;
    rq.write(body);
    final r = await rq.close().timeout(const Duration(seconds: 45));
    final loc = r.headers.value('location');
    if ((r.statusCode == 302 || r.statusCode == 307) &&
        loc != null &&
        loc.isNotEmpty) {
      await r.drain<void>(); // tutup body 302 dulu
      final r2 = await c.getUrl(Uri.parse(loc)); // GET polos, tanpa header
      final resp2 = await r2.close().timeout(const Duration(seconds: 45));
      final txt = await utf8.decoder.bind(resp2).join();
      print('4) resep verified  => HTTP ${resp2.statusCode} (302 -> GET polos)');
      print('   awal body       => ${potong(txt, 400)}');
    } else {
      print('4) POST bukan 302+Location: HTTP ${r.statusCode}');
    }
    c.close();
  } catch (e) {
    print('4) ERROR           => $e');
  }
}
