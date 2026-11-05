import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/providers.dart';
import '../data/repository.dart';
import 'settings_service.dart';

class AutoBackupState {
  final bool enabled;
  final DateTime? lastAt;

  /// 마지막 시도가 실패했는지 (다음 변경 때 다시 시도한다)
  final bool failed;

  const AutoBackupState(
      {required this.enabled, this.lastAt, this.failed = false});
}

/// Download/경조사장부/ 폴더에 실제로 파일을 쓰는 부분 (MainActivity.kt)
class AutoBackupWriter {
  static const _channel = MethodChannel('gyeongjosa/auto_backup');

  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 저장된 실제 파일 이름을 돌려준다.
  Future<String> save(Repository repository,
      {required String fileName, String? replaceName}) async {
    final dir = await getTemporaryDirectory();
    final snapshot = File(p.join(dir.path, 'auto_backup_snapshot.db'));
    try {
      await repository.snapshotTo(snapshot.path);
      final saved = await _channel.invokeMethod<String>('save', {
        'sourcePath': snapshot.path,
        'fileName': fileName,
        'replaceName': replaceName,
      });
      return saved ?? fileName;
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }
}

final autoBackupWriterProvider =
    Provider<AutoBackupWriter>((ref) => AutoBackupWriter());

final autoBackupSupportedProvider = FutureProvider<bool>(
    (ref) => ref.watch(autoBackupWriterProvider).isSupported());

String autoBackupFileName(DateTime date) =>
    '경조사장부_백업_${DateFormat('yyyyMMdd').format(date)}.db';

/// 이번 장부에서 오늘 만든 파일이 있으면 그 이름 ('(1)'이 붙었을 수도 있다).
/// 앱 데이터를 지우고 새로 시작했다면 기록이 없어서, 같은 날짜의 예전 백업은 그대로 남는다.
String? autoBackupReplaceName(String? lastSaved, String todayFileName) {
  final today = p.basenameWithoutExtension(todayFileName);
  return lastSaved != null && lastSaved.startsWith(today) ? lastSaved : null;
}

/// 기록이 바뀌면 조금 기다렸다가 한 번만 백업한다.
/// 접수처럼 저장이 계속 이어져도 [maxWait]마다는 백업하고, 앱이 뒤로 가면 바로 백업한다.
class AutoBackupNotifier extends Notifier<AutoBackupState> {
  static const quietTime = Duration(seconds: 5);
  static const maxWait = Duration(seconds: 60);

  Timer? _quietTimer;
  Timer? _maxTimer;
  bool _running = false;
  bool _changedWhileRunning = false;

  @override
  AutoBackupState build() {
    ref.listen(dbVersionProvider, (_, _) => schedule());
    ref.onDispose(_cancelTimers);
    final prefs = ref.read(prefsProvider);
    final last = prefs.getString(PrefKeys.lastAutoBackupAt);
    return AutoBackupState(
      enabled: prefs.getBool(PrefKeys.autoBackupEnabled) ?? true,
      lastAt: last == null ? null : DateTime.tryParse(last),
    );
  }

  bool get _isPending => _quietTimer != null;

  void _cancelTimers() {
    _quietTimer?.cancel();
    _maxTimer?.cancel();
    _quietTimer = null;
    _maxTimer = null;
  }

  void schedule() {
    if (!state.enabled) return;
    _quietTimer?.cancel();
    _quietTimer = Timer(quietTime, flush);
    _maxTimer ??= Timer(maxWait, flush);
  }

  /// 앱을 켰는데 아직 자동 백업이 한 번도 없으면 (이 기능이 생기기 전부터 쓰던 경우 등) 백업한다.
  void scheduleIfNeverBackedUp() {
    if (state.lastAt == null) schedule();
  }

  /// 기다리는 백업이 있으면 지금 한다.
  Future<void> flush() async {
    if (!_isPending) return;
    _cancelTimers();
    if (_running) {
      _changedWhileRunning = true;
      return;
    }
    _running = true;
    try {
      await _backup();
    } finally {
      _running = false;
    }
    if (_changedWhileRunning) {
      _changedWhileRunning = false;
      schedule();
    }
  }

  Future<void> _backup() async {
    if (!state.enabled) return;
    final repository = ref.read(repositoryProvider);
    final prefs = ref.read(prefsProvider);
    try {
      // 데이터를 지운 직후의 빈 장부로 예전 백업을 덮어쓰지 않는다.
      if (!await repository.hasAnyData()) return;
      final now = DateTime.now();
      final fileName = autoBackupFileName(now);
      final saved = await ref.read(autoBackupWriterProvider).save(repository,
          fileName: fileName,
          replaceName: autoBackupReplaceName(
              prefs.getString(PrefKeys.autoBackupFileName), fileName));
      await prefs.setString(PrefKeys.autoBackupFileName, saved);
      await prefs.setString(PrefKeys.lastAutoBackupAt, now.toIso8601String());
      state = AutoBackupState(enabled: state.enabled, lastAt: now);
    } catch (e) {
      debugPrint('자동 백업 실패: $e');
      state = AutoBackupState(
          enabled: state.enabled, lastAt: state.lastAt, failed: true);
    }
  }

  Future<void> setEnabled(bool value) async {
    await ref.read(prefsProvider).setBool(PrefKeys.autoBackupEnabled, value);
    state = AutoBackupState(enabled: value, lastAt: state.lastAt);
    if (value) {
      schedule();
    } else {
      _cancelTimers();
    }
  }

  /// 백업에서 복원하기 전에 부른다. 복원한 내용이 오늘의 백업을 덮어쓰지 않고 새 파일로 남는다.
  Future<void> beforeRestore() async {
    _cancelTimers();
    await ref.read(prefsProvider).remove(PrefKeys.autoBackupFileName);
  }
}

final autoBackupProvider =
    NotifierProvider<AutoBackupNotifier, AutoBackupState>(
        AutoBackupNotifier.new);
