import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/reception.dart';
import '../screens/reception_import_screen.dart';
import 'reception_file_service.dart';

/// 앱 전체의 화면 이동 열쇠. 다른 앱에서 받은 파일을 어느 화면에서든 열 때 쓴다.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// 카카오톡 등에서 장부 파일을 눌러 '경조사 장부'로 열었을 때 받아서 가져오기 화면으로 간다.
/// 앱이 꺼져 있었으면 첫 화면이 뜬 뒤, 켜져 있었으면 바로 연다 (MainActivity.kt).
class IncomingFiles {
  static const _channel = MethodChannel('gyeongjosa/incoming_file');

  static Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fileReceived') await open(call.arguments as String?);
    });
    try {
      await open(await _channel.invokeMethod<String>('takePending'));
    } on MissingPluginException {
      // 테스트 등 안드로이드가 아닌 곳
    }
  }

  /// [path]의 파일을 읽어 가져오기 미리보기로 간다. 빈 문자열이면 읽지 못한 파일.
  /// 첫 실행 가이드가 아직이면 가이드 위에 열어, 가져온 뒤 가이드가 보이게 한다.
  static Future<void> open(String? path) async {
    if (path == null) return;
    // 앱이 막 켜져 첫 화면이 아직이면 그려질 때까지 기다린다
    if (appNavigatorKey.currentState == null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    final ReceptionPackage package;
    try {
      if (path.isEmpty) throw const FormatException(ReceptionPackage.notOursMessage);
      package = ReceptionFileService.fromBytes(await File(path).readAsBytes());
    } on FormatException catch (e) {
      final context = appNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('가져올 수 없어요'),
          content: Text(e.message),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
          ],
        ),
      );
      return;
    } catch (_) {
      return;
    }
    await navigator.push(MaterialPageRoute<void>(
        builder: (_) => ReceptionImportScreen(package: package)));
  }
}
