import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import '../models/reception.dart';

/// 예전 장부 파일(JSON 1개) 읽기. 장부 보내기는 이제 글자로만 보내고(ledger_text_format.dart),
/// 이 파일은 예전 버전 앱이 보낸 파일을 [예전 장부 파일 가져오기]로 읽을 때만 쓴다.
class ReceptionFileService {
  static const _maxFileBytes = 20 * 1024 * 1024;

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
