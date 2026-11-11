import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/constants.dart';
import '../models/reception.dart';
import 'app_config.dart';
import 'limits.dart';
import 'format.dart';

/// 요약 메시지 공유, 장부 파일(JSON 1개) 만들기 · 공유 · 읽기
class ReceptionFileService {
  static const _maxFileBytes = 20 * 1024 * 1024;

  /// 경조사장부_행사이름_날짜_접수자.json
  static String fileName(Reception r) {
    String clean(String s) =>
        s.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final parts = [
      '경조사장부',
      clean(r.title),
      toDbDate(r.date),
      if (r.operatorName.trim().isNotEmpty) clean(r.operatorName),
    ];
    return '${parts.join('_')}.json';
  }

  /// 요약(안내) 메시지. 앱이 없어도 읽을 수 있고, 전체 명단은 넣지 않는다.
  /// 끝에 받는 사람이 장부 파일을 여는 방법을 붙인다.
  static String summaryMessage(ReceptionPackage package) {
    final r = package.reception;
    final totals = package.totals;
    final hasOperator = r.operatorName.trim().isNotEmpty;
    return [
      '[경조사 장부] ${r.title} 접수 결과',
      '${formatDate(r.date)}${hasOperator ? ' · 접수: ${r.operatorName}' : ''}',
      '',
      '총 ${totals.count}명 · ${formatWon(totals.amount)}',
      for (final side in package.sides)
        if (side != ReceptionDefaults.noSide)
          '- $side ${package.totalsFor(side).count}명 · ${formatWon(package.totalsFor(side).amount)}',
      if (package.showsMealTickets) '식권 ${totals.mealTickets}장',
      if (r.methodEnabled)
        '현금 ${formatWon(package.totalsForMethod(ReceptionDefaults.cash).amount)} · '
            '계좌이체 ${formatWon(package.totalsForMethod(ReceptionDefaults.transfer).amount)}',
      '',
      '[장부 파일 받는 방법]',
      "① 아래 링크로 '경조사 장부' 앱 설치",
      "② 함께 보낸 장부 파일(.json)을 눌러 '경조사 장부'로 열기",
      '③ 이름 · 금액 전체 명단을 확인하고 [가져오기]',
      '※ 무료는 ${FreeLimits.people}명까지 가져올 수 있어요(이 장부 ${totals.count}명)',
      '※ 카카오톡 파일은 보관 기간이 지나면 받을 수 없어요',
      '앱 받기: ${AppConfig.playStoreUrl}',
    ].join('\n');
  }

  /// 요약(안내) 메시지를 글자로 공유창에 보낸다. 공유 창을 그냥 닫으면 false.
  /// 제목(subject)은 넣지 않는다. 카카오톡이 제목과 본문을 합쳐 첫 줄이 두 번 들어가기 때문.
  static Future<bool> shareSummary(ReceptionPackage package) async {
    final result = await SharePlus.instance
        .share(ShareParams(text: summaryMessage(package)));
    return result.status != ShareResultStatus.dismissed;
  }

  /// 파일을 만들어 공유창으로 보낸다.
  static Future<void> share(ReceptionPackage package) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName(package.reception)));
    await file.writeAsString(package.toJsonString(), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
    ));
  }

  /// 파일을 골라 읽는다. 고르지 않으면 null.
  /// 올바른 파일이 아니면 [FormatException].
  static Future<ReceptionPackage?> pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty) return null;
    return fromBytes(await picked.first.xFile.readAsBytes());
  }

  /// 파일 내용을 읽는다. 우리 장부 파일이 아니면 [FormatException].
  static ReceptionPackage fromBytes(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > _maxFileBytes) {
      throw const FormatException(ReceptionPackage.notOursMessage);
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException(ReceptionPackage.notOursMessage);
    }
    return ReceptionPackage.parse(text);
  }
}
