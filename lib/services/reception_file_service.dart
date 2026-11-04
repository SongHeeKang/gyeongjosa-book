import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/reception.dart';
import 'format.dart';

/// 장부 파일(JSON 1개) 만들기 · 공유 · 읽기
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

  /// 파일을 만들어 공유창으로 보낸다.
  static Future<void> share(ReceptionPackage package) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName(package.reception)));
    await file.writeAsString(package.toJsonString(), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: '${package.reception.title} 접수 장부',
      text: '경조사 장부 앱에서 [장부 > 받은 장부 가져오기]로 이 파일을 불러오세요.',
    ));
  }

  /// 파일을 골라 읽는다. 고르지 않으면 null.
  /// 올바른 파일이 아니면 [FormatException].
  static Future<ReceptionPackage?> pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty) return null;
    final bytes = await picked.first.xFile.readAsBytes();
    if (bytes.length > _maxFileBytes) {
      throw const FormatException('경조사 장부에서 보낸 접수 파일이 아니에요.');
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('경조사 장부에서 보낸 접수 파일이 아니에요.');
    }
    return ReceptionPackage.parse(text);
  }
}
