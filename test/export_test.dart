// 추가 S: 엑셀 파일(.xlsx) 무료 — 행사 장부 · 주고받은 내역
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/gift_record.dart';
import 'package:gyeongjosa/models/person.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/services/export_service.dart';
import 'package:gyeongjosa/services/ledger_text_format.dart';

/// 칸 값을 글자로 (빈 칸은 '')
String _v(Sheet sheet, int row, int col) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
      .value;
  return switch (value) {
    null => '',
    TextCellValue() => value.value.toString(),
    IntCellValue() => '${value.value}',
    _ => value.toString(),
  };
}

String _xml(List<int> bytes, String name) => utf8.decode(
    ZipDecoder().decodeBytes(bytes).findFile(name)!.content as List<int>);

/// 시트 이름 → 파일 경로 (workbook.xml + rels)
String _sheetXml(List<int> bytes, String sheetName) {
  final workbook = _xml(bytes, 'xl/workbook.xml');
  final rels = _xml(bytes, 'xl/_rels/workbook.xml.rels');
  final tag = RegExp('<sheet [^>]*name="$sheetName"[^>]*/>').firstMatch(workbook)!.group(0)!;
  final rid = RegExp(r'r:id="([^"]+)"').firstMatch(tag)!.group(1)!;
  final target = RegExp('<Relationship [^>]*Id="$rid"[^>]*/>')
      .firstMatch(rels)!
      .group(0)!;
  final path = RegExp(r'Target="([^"]+)"').firstMatch(target)!.group(1)!;
  return _xml(bytes, path.startsWith('/') ? path.substring(1) : 'xl/$path');
}

void main() {
  setUpAll(() => initializeDateFormatting('ko'));
  final reception = ReceptionPackage(
    Reception(
      id: 'r1',
      title: '누나 결혼식',
      eventType: '결혼',
      date: DateTime(2026, 12, 26),
      sides: const ['신랑측', '신부측'],
      operatorName: '송희강',
      startedAt: DateTime(2026, 12, 26, 11, 30),
      finishedAt: DateTime(2026, 12, 26, 14, 0),
    ),
    [
      for (var i = 0; i < 120; i++)
        ReceptionEntry(
          id: 'e$i',
          receptionId: 'r1',
          name: '손님${(120 - i).toString().padLeft(3, '0')}',
          amount: 50000 + (i % 3) * 50000,
          side: i.isEven ? '신랑측' : '신부측',
          method: i % 4 == 0 ? '계좌' : '현금',
          mealTickets: i % 3,
          memo: i == 0 ? '봉투 2개' : null,
          createdAt: DateTime(2026, 12, 26, 12, 0).add(Duration(minutes: i)),
        ),
      ReceptionEntry(
        id: 'gone',
        receptionId: 'r1',
        name: '지운손님',
        amount: 10000,
        side: '신랑측',
        createdAt: DateTime(2026, 12, 26, 15),
        deleted: true,
      ),
    ],
  );

  group('행사 장부', () {
    test('다른 사람 행사 120명이 파일 하나에, 합계가 앱 계산과 같고 지운 손님은 빠진다', () {
      final ledger = LedgerExcel.fromReception(reception);
      final bytes = ExportService.buildLedger(ledger, now: DateTime(2026, 11, 17, 9));
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, containsAll(['명단', '합계', '정보']));

      final list = book['명단'];
      // 1~2행 행사 정보
      expect(_v(list, 0, 0), '행사 이름');
      expect(_v(list, 1, 0), '누나 결혼식');
      final info = {for (var c = 0; c < 10; c++) _v(list, 0, c): _v(list, 1, c)};
      expect(info['종류'], '결혼');
      expect(info['날짜'], '2026-12-26');
      expect(info['행사 구분'], '다른 사람 행사');
      expect(info['적은 사람'], '송희강');
      expect(info['구분 목록'], '신랑측, 신부측');
      expect(info['받기 시작'], '2026-12-26 11:30');
      expect(info['받기 끝'], '2026-12-26 14:00');
      // 4행 열 제목, 5행부터 손님 (가나다순)
      expect([for (var c = 0; c < 9; c++) _v(list, 3, c)],
          ['번호', '이름', '금액', '구분', '결제 방법', '식권', '메모', '적은 날짜', '시간']);
      expect(_v(list, 4, 0), '1');
      expect(_v(list, 4, 1), '손님001');
      expect(_v(list, 4 + 119, 1), '손님120');
      expect(_v(list, 4 + 120, 1), '');
      expect([for (var r = 4; r < 124; r++) _v(list, r, 1)], isNot(contains('지운손님')));
      // 손님120 = 처음 받은 손님: 계좌 · 식권 0 · 메모
      expect(_v(list, 123, 2), '50000');
      expect(_v(list, 123, 3), '신랑측');
      expect(_v(list, 123, 4), '계좌');
      expect(_v(list, 123, 5), '0');
      expect(_v(list, 123, 6), '봉투 2개');
      expect(_v(list, 123, 7), '2026-12-26');
      expect(_v(list, 123, 8), '12:00');

      // [합계] = 앱 계산
      final sum = book['합계'];
      // 앱에서 불러온 장부에는 지운 항목이 없다
      final shown = ReceptionPackage(
          reception.reception, [for (final e in reception.entries) if (!e.deleted) e]);
      final totals = shown.totals;
      expect(_v(sum, 1, 0), '총계');
      expect(_v(sum, 1, 1), '${totals.count}');
      expect(_v(sum, 1, 2), '${totals.amount}');
      expect(_v(sum, 1, 3), '${totals.mealTickets}');
      final rows = {for (var r = 1; r < 8; r++) _v(sum, r, 0): r};
      expect(_v(sum, rows['신랑측']!, 2), '${shown.totalsFor('신랑측').amount}');
      expect(_v(sum, rows['신부측']!, 1), '${shown.totalsFor('신부측').count}');
      expect(_v(sum, rows['현금']!, 2), '${shown.totalsForMethod('현금').amount}');
      // 정한 구분 순서대로
      expect(rows['신랑측']! < rows['신부측']!, isTrue);
      expect(_v(sum, rows['계좌']!, 2), '${shown.totalsForMethod('계좌').amount}');
    });

    test('받은 순서로 고르면 그 순서대로', () {
      final ledger = LedgerExcel.fromReception(reception, order: LedgerOrder.received);
      final list = Excel.decodeBytes(ExportService.buildLedger(ledger))['명단'];
      expect(_v(list, 4, 1), '손님120');
      expect(_v(list, 5, 1), '손님119');
    });

    test('내 행사: 관계 · 연락처 · 구분 · 식권 · 결제 방법 · 메모가 그대로', () {
      final event = Event(
          id: 7,
          type: '결혼',
          title: '우리 결혼식',
          date: DateTime(2026, 10, 11),
          isMine: true,
          place: '그랜드홀',
          memo: '2층',
          receiveSides: const ['신랑측', '신부측']);
      final people = {
        1: Person(id: 1, name: '강민호', relation: '친구', phone: '010-1111-2222', createdAt: DateTime(2026)),
        2: Person(id: 2, name: '강지은', relation: '회사', createdAt: DateTime(2026)),
      };
      final records = [
        GiftRecord(id: 2, personId: 2, eventId: 7, direction: '받음', amount: 50000,
            method: '계좌', date: DateTime(2026, 10, 11), memo: '회사 동료', side: '신부측',
            mealTickets: 2, personName: '강지은', personRelation: '회사'),
        GiftRecord(id: 1, personId: 1, eventId: 7, direction: '받음', amount: 100000,
            date: DateTime(2026, 10, 11), side: '신랑측', mealTickets: 1,
            personName: '강민호', personRelation: '친구', needsReview: true),
      ];
      final ledger = LedgerExcel.fromEvent(event, records, people);
      expect(ledger.fileName, '경조사장부_우리 결혼식_20261011.xlsx');
      final list = Excel.decodeBytes(ExportService.buildLedger(ledger))['명단'];
      final info = {for (var c = 0; c < 10; c++) _v(list, 0, c): _v(list, 1, c)};
      expect(info['행사 구분'], '내 행사');
      expect(info['장소'], '그랜드홀');
      expect(info['메모'], '2층');
      expect([for (var c = 0; c < 12; c++) _v(list, 4, c)],
          ['1', '강민호', '100000', '신랑측', '현금', '1', '', '2026-10-11', '', '친구', '010-1111-2222', '확인 필요']);
      expect([for (var c = 0; c < 12; c++) _v(list, 5, c)],
          ['2', '강지은', '50000', '신부측', '계좌', '2', '회사 동료', '2026-10-11', '', '회사', '', '']);
      // 받은 사람이 없는 구분도 합계에 0명으로
      final onlyGroom = Excel.decodeBytes(ExportService.buildLedger(
          LedgerExcel.fromEvent(event, [records.last], people)))['합계'];
      expect([for (var r = 1; r < 5; r++) _v(onlyGroom, r, 0)], containsAll(['신랑측', '신부측']));
    });
  });

  test('주고받은 내역: 세 시트, 사람 메모 · 연락처, 아직 돈을 안 적은 일정, 보냄 · 받음 합계', () {
    final people = [
      Person(id: 1, name: '김철수', relation: '친구', phone: '010-1234-5678', memo: '대학 동기', createdAt: DateTime(2026, 1, 2)),
      Person(id: 2, name: '이영희', relation: '회사', createdAt: DateTime(2026, 3, 4)),
    ];
    final events = [
      Event(id: 1, type: '결혼', title: '철수 결혼식', date: DateTime(2026, 5, 2), isMine: false, place: '웨딩홀', personId: 1),
      Event(id: 2, type: '돌', title: '영희 돌잔치', date: DateTime(2026, 12, 1), isMine: false, reminderDays: null),
    ];
    final records = [
      GiftRecord(id: 1, personId: 1, eventId: 1, direction: '보냄', amount: 100000,
          date: DateTime(2026, 5, 2), memo: '봉투, 꽃', personName: '김철수', personRelation: '친구'),
      GiftRecord(id: 2, personId: 1, direction: '받음', amount: 50000, method: '계좌',
          date: DateTime(2026, 8, 1), eventType: '생일', personName: '김철수', personRelation: '친구'),
      GiftRecord(id: 3, personId: 2, direction: '보냄', amount: 30000,
          date: DateTime(2026, 2, 1), eventType: '장례', personName: '이영희', personRelation: '회사'),
    ];
    final bytes = ExportService.buildHistory(
        records: records, people: people, events: events, now: DateTime(2026, 11, 17));
    expect(ExportService.historyFileName(DateTime(2026, 11, 17)),
        '경조사장부_주고받은내역_20261117.xlsx');
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, containsAll(['내역', '사람별 합계', '행사 일정', '정보']));

    final list = book['내역'];
    expect(_v(list, 0, 0), '날짜');
    // 날짜 최신순
    expect([for (var r = 1; r <= 3; r++) _v(list, r, 0)], ['2026-08-01', '2026-05-02', '2026-02-01']);
    expect([for (var c = 0; c < 14; c++) _v(list, 2, c)], [
      '2026-05-02', '보냄', '김철수', '친구', '010-1234-5678', '100000', '현금', '결혼',
      '철수 결혼식', '2026-05-02', '웨딩홀', '', '', '봉투, 꽃',
    ]);
    expect(_v(list, 1, 7), '생일');
    // 맨 아래 합계
    expect(_v(list, 5, 0), '보냄 합계');
    expect(_v(list, 5, 1), '2건');
    expect(_v(list, 5, 5), '130000');
    expect(_v(list, 6, 0), '받음 합계');
    expect(_v(list, 6, 5), '50000');

    final sum = book['사람별 합계'];
    expect([for (var c = 0; c < 10; c++) _v(sum, 1, c)],
        ['김철수', '친구', '010-1234-5678', '대학 동기', '1', '100000', '1', '50000', '-50000', '2026-01-02']);

    final schedule = book['행사 일정'];
    expect(_v(schedule, 1, 2), '영희 돌잔치'); // 돈을 안 적은 일정도
    expect(_v(schedule, 1, 7), '끔');
    expect(_v(schedule, 2, 6), '김철수');
    expect(_v(schedule, 1, 4), '아니요');
  });

  test('금액 칸은 천 단위 쉼표 형식, 열 제목 줄 고정, [정보] 시트는 숨김 · 형식 버전 1', () {
    final bytes = ExportService.buildLedger(LedgerExcel.fromReception(reception),
        now: DateTime(2026, 11, 17, 9, 5));
    // 눈으로 확인할 수 있게 파일로도 남긴다
    File('${Directory.systemTemp.path}/gyeongjosa_excel_ledger.xlsx').writeAsBytesSync(bytes);
    final book = Excel.decodeBytes(bytes);
    final info = book['정보'];
    expect(_v(info, 0, 1), '경조사 장부');
    expect(_v(info, 1, 1), '장부');
    expect(_v(info, 2, 1), '1');
    expect(_v(info, 3, 1), '2026-11-17 09:05');

    final workbook = _xml(bytes, 'xl/workbook.xml');
    expect(RegExp(r'<sheet [^>]*state="hidden"[^>]*name="정보"|<sheet [^>]*name="정보"[^>]*state="hidden"')
        .hasMatch(workbook), isTrue);
    expect(_sheetXml(bytes, '명단'), contains('ySplit="4"'));
    expect(_sheetXml(bytes, '명단'), contains('state="frozen"'));
    expect(_sheetXml(bytes, '합계'), contains('ySplit="1"'));
    // 금액 칸 스타일 = numFmtId 3 (#,##0)
    expect(_xml(bytes, 'xl/styles.xml'), contains('numFmtId="3"'));
  });

  test('파일 이름에 쓸 수 없는 글자는 _로', () {
    expect(ExportService.ledgerFileName('엄마/아빠: "회갑"?', DateTime(2026, 1, 2)),
        '경조사장부_엄마_아빠_ _회갑___20260102.xlsx');
  });

  group('추가 T: 행사 하나 · 주고받은 내역 텍스트 (행사 전체 공유는 v1에서 없앰)', () {
    test('행사 하나 텍스트: 공유는 100명씩 나눔, 다운로드는 나누지 않은 .txt 하나', () {
      final parts = LedgerText.build(reception);
      expect(parts.length, 2); // 120명 = 100 + 20
      final file = ExportService.ledgersTextFile([reception]);
      expect(file, LedgerText.build(reception, chunkSize: 1 << 30).single);
      expect(ExportService.ledgerFileName('누나 결혼식', DateTime(2026, 12, 26), ext: 'txt'),
          '경조사장부_누나 결혼식_20261226.txt');
      // 붙여넣어 가져오기로 다시 읽힌다
      expect(LedgerText.parse(parts.first), isNotNull);
    });

    test('주고받은 내역 텍스트: 머리 · 합계 · 한 줄씩(빈 값 빼고), 100줄씩 나눔', () {
      final records = [
        for (var i = 0; i < 150; i++)
          GiftRecord(id: i, personId: 1, direction: i.isEven ? '보냄' : '받음', amount: 10000,
              date: DateTime(2026, 1, 1).add(Duration(days: i)), personName: '김철수',
              personRelation: i == 149 ? '친구' : null, memo: i == 149 ? '꽃' : null),
      ];
      final parts = ExportService.historyText(records: records, now: DateTime(2026, 11, 17));
      expect(parts.length, 2);
      final lines = parts.first.split('\n');
      expect(lines[0], '[경조사 장부] 주고받은 내역 · 2026-11-17 (1/2)');
      expect(lines[1], '보냄 75건 750,000원 / 받음 75건 750,000원');
      expect(lines[3], '1. 2026-05-30 · 받음 · 김철수(친구) · 10,000원 · 현금 · 메모: 꽃');
      expect(parts.last.split('\n').where((l) => RegExp(r'^\d+\. ').hasMatch(l)).length, 50);
    });
  });
}
