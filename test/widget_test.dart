import 'package:flutter_test/flutter_test.dart';

import 'package:examp4/main.dart';

void main() {
  test('Exam model menyimpan data dengan benar', () {
    final exam = Exam(
      image: 'https://example.com/image.png',
      mapel: 'Matematika',
      waktu: '09:00 - 10:30',
      link: 'https://exam.example.com/matematika',
    );

    expect(exam.image, 'https://example.com/image.png');
    expect(exam.mapel, 'Matematika');
    expect(exam.waktu, '09:00 - 10:30');
    expect(exam.link, 'https://exam.example.com/matematika');
  });
}