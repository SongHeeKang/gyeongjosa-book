import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/gift_record.dart';
import 'format.dart';

/// 엑셀에서 열 수 있는 CSV 만들기 (프로 전용).
class CsvService {
  static const header = ['이름', '관계', '보냄/받음', '금액', '행사', '날짜', '메모'];

  /// 엑셀에서 한글이 깨지지 않도록 UTF-8 BOM을 붙인다.
  static String buildCsv(List<GiftRecord> records) {
    final rows = <List<dynamic>>[
      header,
      for (final r in records)
        [
          r.personName ?? '',
          r.personRelation ?? '',
          r.direction,
          r.amount,
          r.eventLabel,
          toDbDate(r.date),
          r.memo ?? '',
        ],
    ];
    return Csv(addBom: true).encode(rows);
  }

  static Future<void> exportAndShare(List<GiftRecord> records) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
    final file = File(p.join(dir.path, 'gyeongjosa_records_$stamp.csv'));
    await file.writeAsString(buildCsv(records), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: '경조사 장부 내역 (엑셀)',
    ));
  }
}
