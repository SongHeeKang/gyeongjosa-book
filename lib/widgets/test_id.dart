import 'package:flutter/widgets.dart';

/// 자동화 테스트(Appium)용 식별자.
/// 안드로이드에서는 이 이름이 화면 요소의 resource-id로 보인다.
/// 화면 모양과 동작은 바꾸지 않고, 감싼 위젯을 하나의 요소로 묶기만 한다.
/// 이름 목록은 AutoTest/README.md의 '자동화 식별자' 표를 따른다.
class TestId extends StatelessWidget {
  const TestId(this.id, {super.key, required this.child, this.selected});
  final String id;
  final Widget child;

  /// 색으로만 선택을 보여주는 버튼은 선택 여부도 알려준다.
  final bool? selected;

  @override
  Widget build(BuildContext context) => Semantics(
      identifier: id, container: true, selected: selected, child: child);
}
