// ==================== Uji syarat keamanan NISN login CBT ====================
// NISN ketik WAJIB cocok dengan nama yang dipilih — berlaku semua login.
import 'package:examp4/cbt/cbt_login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validasiNisnLogin (syarat login: NISN harus sesuai nama)', () {
    test('NISN cocok dengan nama terpilih -> lolos (null)', () {
      expect(
        validasiNisnLogin(
          diketik: '3132915823',
          nisnTerpilih: '3132915823',
          namaTerpilih: 'ABI WAHYU',
        ),
        isNull,
      );
    });

    test('NISN beda dengan nama terpilih -> ditolak, pesan menyebut nama', () {
      final e = validasiNisnLogin(
        diketik: '9999999999',
        nisnTerpilih: '3132915823',
        namaTerpilih: 'ABI WAHYU',
      );
      expect(e, isNotNull);
      expect(e!, contains('ABI WAHYU'));
    });

    test('NISN kosong -> ditolak (wajib diketik)', () {
      final e = validasiNisnLogin(
        diketik: '   ',
        nisnTerpilih: '3132915823',
        namaTerpilih: 'SISWA TES',
      );
      expect(e, isNotNull);
      expect(e, contains('wajib diketik'));
    });

    test('pemisah titik diabaikan & nol depan yang hilang disamakan', () {
      expect(
        validasiNisnLogin(
          diketik: '313.291.5823',
          nisnTerpilih: '3132915823',
          namaTerpilih: 'ABI WAHYU',
        ),
        isNull,
      );
      // Sheet menyimpan '0123456789', siswa mengetik tanpa nol depan.
      expect(
        validasiNisnLogin(
          diketik: '123456789',
          nisnTerpilih: '0123456789',
          namaTerpilih: 'SISWA NOL',
        ),
        isNull,
      );
    });
  });
}
