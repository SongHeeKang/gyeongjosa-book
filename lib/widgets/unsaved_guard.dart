import 'package:flutter/material.dart';

import 'common.dart';

/// 입력 화면 · 입력 창의 뒤로 가기(안드로이드 뒤로 가기 · 예측 뒤로 가기 제스처 · 왼쪽 위 ←).
/// 적은 내용이 없으면 바로 나가고, 있으면 "작성 중인 내용이 있어요. 나갈까요?"를 묻는다.
/// 저장 버튼은 Navigator.pop으로 닫으므로 이 확인을 거치지 않는다.
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard(
      {super.key, required this.isDirty, required this.child});

  /// 처음 열었을 때와 달라졌는지
  final bool Function() isDirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (isDirty() && !await confirmLeaveUnsaved(context)) return;
        if (navigator.mounted) navigator.pop();
      },
      child: child,
    );
  }
}

/// "작성 중인 내용이 있어요. 나갈까요?" [계속 작성] [나가기]. 나가면 true.
Future<bool> confirmLeaveUnsaved(BuildContext context) => confirmDialog(
      context,
      title: '작성 중인 내용이 있어요',
      message: '나갈까요? 적은 내용은 저장되지 않아요.',
      okText: '나가기',
      cancelText: '계속 작성',
    );
