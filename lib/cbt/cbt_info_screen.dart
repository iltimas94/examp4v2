// ==================== Layar Informasi Ujian ====================
// Porting halaman info Index.txt: baris info + "Mulai Mengerjakan" TANPA
// panggilan server (startTime dicatat lokal, di-backfill saat autosave).
import 'package:flutter/material.dart';

import 'cbt_exam_screen.dart';
import 'cbt_security.dart';
import 'cbt_session.dart';
import 'cbt_widgets.dart';

class CbtInfoScreen extends StatelessWidget {
  final CbtSession session;
  const CbtInfoScreen({super.key, required this.session});

  Widget _barisInfo(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kCbtBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 15, color: kCbtTextMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mulai(BuildContext context) async {
    // TANPA eksekusi server: startTime dicatat lokal (hemat 1 eksekusi/siswa).
    session.startTime = DateTime.now().millisecondsSinceEpoch;
    await session.simpanSesi();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => CbtExamScreen(session: session)),
    );
  }

  Future<void> _kembaliKeLogin(BuildContext context) async {
    await session.kembaliKeLogin();
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📋 Informasi Ujian')),
      body: CbtSecurityController.instance.wrap(
        context,
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kCbtBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '📋 Informasi Ujian',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: kCbtPrimaryDark),
                  ),
                  const SizedBox(height: 16),
                  _barisInfo('Nama', session.siswaNama),
                  _barisInfo('NISN', session.nisn),
                  _barisInfo('Kelas', session.siswaKelas),
                  _barisInfo('Mata Pelajaran', session.mapel),
                  _barisInfo('Kode Ujian', session.kodeUjian),
                  _barisInfo('Jumlah Soal', '${session.soalList.length} soal'),
                  _barisInfo(
                    'Durasi',
                    session.isTanpaBatas()
                        ? 'Tanpa batas waktu'
                        : '${session.durasiUjianMenit} menit',
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kCbtPrimary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _mulai(context),
                    child: const Text('Mulai Mengerjakan'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kCbtSlate,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _kembaliKeLogin(context),
                    child: const Text('← Kembali ke Halaman Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
