import 'package:flutter/material.dart';

/// 홈 '다가오는 일정' · '최근 기록' 목록(추가 AA).
/// - 항목이 적으면 내용만큼, 많으면 약 [maxRows]줄 높이까지만 보이고 안에서 스크롤한다
///   (마지막 줄이 반쯤 보여 더 있다는 걸 알 수 있게). 스크롤할 때 얇은 막대가 보인다.
/// - 보이는 항목만 그린다(ListView.builder). 기록이 수백 건이어도 느려지지 않는다.
/// - 안쪽 목록이 맨 위 · 맨 아래에 닿으면 남은 움직임을 바깥(홈 화면 전체)에 넘겨
///   손가락이 섹션 안에 갇히지 않는다.
class CappedScrollList extends StatefulWidget {
  const CappedScrollList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.maxRows = 4.5,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double maxRows;

  @override
  State<CappedScrollList> createState() => _CappedScrollListState();
}

class _CappedScrollListState extends State<CappedScrollList> {
  final _controller = ScrollController();
  final _firstKey = GlobalKey();

  /// 첫 줄의 실제 높이(그린 뒤에 잰다). 재기 전에는 글자 크기로 어림한다.
  double? _rowHeight;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    final height = _firstKey.currentContext?.size?.height;
    if (!mounted || height == null || height <= 0) return;
    if (_rowHeight == null || (height - _rowHeight!).abs() > 0.5) {
      setState(() => _rowHeight = height);
    }
  }

  /// 안쪽이 끝에 닿아 더 못 움직인 만큼 바깥 스크롤을 움직인다.
  bool _handOff(OverscrollNotification n) {
    if (n.depth != 0) return false;
    final outer = Scrollable.maybeOf(context);
    if (outer == null) return false;
    final position = outer.position;
    final target = (position.pixels + n.overscroll)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) position.jumpTo(target);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final row = _rowHeight ?? 72 * MediaQuery.textScalerOf(context).scale(1);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: row * widget.maxRows),
      child: NotificationListener<OverscrollNotification>(
        onNotification: _handOff,
        child: Scrollbar(
          controller: _controller,
          child: ListView.builder(
            controller: _controller,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: widget.itemCount,
            itemBuilder: (context, i) => i == 0
                ? KeyedSubtree(
                    key: _firstKey, child: widget.itemBuilder(context, 0))
                : widget.itemBuilder(context, i),
          ),
        ),
      ),
    );
  }
}
