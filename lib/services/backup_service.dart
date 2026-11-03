import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database_helper.dart';

/// 수동 백업 파일 만들기 / 복원.
/// 백업 파일 = DB 파일을 그대로 복사한 것 (.db 1개).
class BackupService {
  BackupService(this._helper);
  final DatabaseHelper _helper;

  /// 백업 파일을 만들어 공유창(카카오톡 나에게 보내기 등)으로 보낸다.
  /// 사용자가 공유창을 그냥 닫으면 false.
  Future<bool> createAndShareBackup() async {
    final file = await _createBackupFile();
    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/octet-stream')],
      subject: '경조사 장부 백업',
      text: '경조사 장부 백업 파일이에요. 새 폰에서 [설정 > 백업에서 복원]으로 불러오세요.',
    ));
    return result.status != ShareResultStatus.dismissed;
  }

  Future<File> _createBackupFile() async {
    final dbPath = await _helper.dbPath;
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final out = File(p.join(dir.path, 'gyeongjosa_backup_$stamp.db'));
    if (await out.exists()) await out.delete();

    // 쓰는 중인 내용이 빠지지 않도록 DB를 잠시 닫고 복사
    await _helper.close();
    try {
      await File(dbPath).copy(out.path);
    } finally {
      await _helper.database; // 다시 열기
    }
    return out;
  }

  /// 백업 파일을 고른다. 고르지 않으면 null.
  /// 고른 파일은 임시 폴더로 복사한 뒤 검사까지 끝낸 경로를 돌려준다.
  /// 이 앱의 백업 파일이 아니면 [FormatException].
  Future<String?> pickAndValidate() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty) return null;

    final bytes = await picked.first.xFile.readAsBytes();
    final dir = await getTemporaryDirectory();
    final candidate = File(p.join(dir.path, 'restore_candidate.db'));
    await candidate.writeAsBytes(bytes, flush: true);
    await DatabaseHelper.validateBackupFile(candidate.path);
    return candidate.path;
  }

  /// 검사가 끝난 백업 파일로 현재 DB를 바꾼다.
  /// 실패하면 원래 데이터로 되돌리고 [FormatException]을 던진다.
  Future<void> restoreFrom(String candidatePath) async {
    final dbPath = await _helper.dbPath;
    final safety = File('$dbPath.before_restore');

    await _helper.close();
    final current = File(dbPath);
    if (await current.exists()) await current.copy(safety.path);
    try {
      await _deleteSidecars(dbPath);
      await File(candidatePath).copy(dbPath);
      // 열어서 실제로 읽히는지 확인 (오래된 백업이면 여기서 자동 업그레이드)
      final db = await _helper.database;
      await db.rawQuery('SELECT COUNT(*) FROM people');
    } catch (e) {
      await _helper.close();
      if (await safety.exists()) {
        await _deleteSidecars(dbPath);
        await safety.copy(dbPath);
      }
      await _helper.database;
      throw const FormatException('복원하지 못했어요. 기존 기록은 그대로 남아 있어요.');
    } finally {
      if (await safety.exists()) await safety.delete();
      final c = File(candidatePath);
      if (await c.exists()) await c.delete();
    }
  }

  Future<void> _deleteSidecars(String dbPath) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) await f.delete();
    }
  }
}
