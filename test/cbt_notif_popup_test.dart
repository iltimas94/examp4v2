// Regresi bug "popup putih tidak bisa diapa-apakan" saat tekan X / keluar:
// CbtNotifs.konfirmasi & tampil harus ter-render utuh (pesan + tombol)
// tanpa exception — akarnya Expanded() di dalam actions AlertDialog yang
// kini dibungkus OverflowBar (bukan RenderFlex) pada Flutter 3.32.
import 'dart:async';
import 'dart:io';

import 'package:examp4/cbt/cbt_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: CbtNotifs.navKey,
      home: const SizedBox.shrink(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('konfirmasi: popup tampil utuh + tombol Batal & Ya berfungsi',
      (tester) async {
    await pumpApp(tester);
    var yaDitekan = false;

    unawaited(CbtNotifs.konfirmasi(
      CbtNotifs.navKey.currentContext!,
      'Keluar dari CBT Alternatif Family Link? Sesi ujian di perangkat ini akan dihapus.',
      () => yaDitekan = true,
    ));
    await tester.pumpAndSettle();

    // Konten popup harus tampil (bukan kotak putih kosong).
    expect(tester.takeException(), isNull,
        reason: 'build dialog melempar exception => inilah popup putih');
    expect(
        find.text(
            'Keluar dari CBT Alternatif Family Link? Sesi ujian di perangkat ini akan dihapus.'),
        findsOneWidget);
    expect(find.text('Batal'), findsOneWidget);
    expect(find.text('Ya, Lanjut'), findsOneWidget);

    // Tombol Batal: popup tertutup, callback TIDAK dipanggil.
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Batal'), findsNothing);
    expect(yaDitekan, isFalse);
  });

  testWidgets('konfirmasi: tombol Ya menutup popup lalu callback dijalankan',
      (tester) async {
    await pumpApp(tester);
    var yaDitekan = false;
    unawaited(CbtNotifs.konfirmasi(
      CbtNotifs.navKey.currentContext!,
      'Keluar ke halaman awal?',
      () => yaDitekan = true,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Ya, Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Ya, Lanjut'), findsNothing);
    expect(yaDitekan, isTrue);
  });

  testWidgets('tampil (satu tombol OK): popup tampil & tertutup saat OK',
      (tester) async {
    await pumpApp(tester);
    var okDitekan = false;
    unawaited(CbtNotifs.tampil(
      CbtNotifs.navKey.currentContext!,
      'Waktu ujian sudah habis.',
      tipe: 'warning',
      cbOk: () => okDitekan = true,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Waktu ujian sudah habis.'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Batal'), findsNothing);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsNothing);
    expect(okDitekan, isTrue);
  });

  testWidgets(
      'konfirmasiKunci: wajib kunci — salah tetap terbuka, benar menutup + callback',
      (tester) async {
    await pumpApp(tester);
    var yaDitekan = false;
    unawaited(CbtNotifs.konfirmasiKunci(
      CbtNotifs.navKey.currentContext!,
      'Keluar dari CBT Alternatif Family Link? Sesi ujian di perangkat ini akan dihapus.',
      () => yaDitekan = true,
      ambilKode: () async => '9876',
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Kunci Keluar'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Kunci salah: popup TETAP terbuka + pesan error, callback tidak jalan.
    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text('Ya, Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Kunci salah. Coba lagi.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(yaDitekan, isFalse);

    // Kunci benar: popup tertutup, callback dijalankan.
    await tester.enterText(find.byType(TextField), '9876');
    await tester.tap(find.text('Ya, Lanjut'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(yaDitekan, isTrue);
  });

  testWidgets('konfirmasiKunci: kunci tidak tersedia -> fallback konfirmasi biasa',
      (tester) async {
    await pumpApp(tester);
    var yaDitekan = false;
    unawaited(CbtNotifs.konfirmasiKunci(
      CbtNotifs.navKey.currentContext!,
      'Keluar ke halaman awal?',
      () => yaDitekan = true,
      ambilKode: () async => null,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Tanpa kunci: tidak ada TextField, popup tetap berfungsi normal.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Batal'), findsOneWidget);
    expect(
        find.textContaining(
            '(Kunci tidak tersedia — konfirmasi tanpa password.)'),
        findsOneWidget);
    await tester.tap(find.text('Ya, Lanjut'));
    await tester.pumpAndSettle();
    expect(yaDitekan, isTrue);
  });

  test('TIDAK ada flex di dalam actions dialog mana pun (jaring popup putih)',
      () {
    // Regresi: flex di actions AlertDialog -> ParentDataWidget error (actions
    // dibungkus OverflowBar, bukan Flex) -> dialog jadi kotak putih beku di
    // release. Pernah terjadi 2x: CbtNotifs lama + dialog "Selesai Ujian?".
    final files = [
      'lib/cbt/cbt_widgets.dart',
      'lib/cbt/cbt_exam_screen.dart',
      'lib/cbt/cbt_login_screen.dart',
      'lib/cbt/cbt_info_screen.dart',
      'lib/cbt/cbt_done_screen.dart',
    ];
    for (final f in files) {
      final src = File(f).readAsStringSync();
      var i = 0;
      while (true) {
        i = src.indexOf('actions:', i);
        if (i < 0) break;
        final end = src.indexOf('],', i);
        expect(end, greaterThan(i), reason: '$f: actions: tidak ketutup');
        final seg = src.substring(i, end + 2);
        expect(seg.contains('Expanded('), isFalse,
            reason:
                '$f: flex di dalam actions -> popup putih (OverflowBar)!');
        i = end + 2;
      }
    }
  });
}
