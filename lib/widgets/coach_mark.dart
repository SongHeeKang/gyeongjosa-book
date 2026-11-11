import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/test_id.dart';

/// 도움말이 가리킬 수 있는 자리
enum CoachSpot {
  recordButton,
  homePending,
  homeHelp,
  menuSent,
  menuSchedule,
  menuDirect,
  menuReception,
  menuClose,
  peopleSearch,
  peopleCard,
  myEventsCreate,
  myEventsFirst,
  eventReception,
  eventDirect,
  eventImport,
  statsPeriod,
  statsChart,
  receptionName,
  receptionAmounts,
  receptionRecent,
  receptionFinish,
  quickAmounts,
  quickList,
}

/// [child]의 위치를 도움말에 알려준다. 같은 화면이 두 번 쌓여 있으면 맨 위 것을 쓴다.
class CoachTarget extends StatefulWidget {
  const CoachTarget({super.key, required this.spot, required this.child});
  final CoachSpot spot;
  final Widget child;

  /// 지금 화면에서의 위치. 아직 없으면 null.
  static Rect? rectOf(CoachSpot spot) {
    final states = _CoachTargetState._mounted[spot];
    if (states == null || states.isEmpty) return null;
    final box = states.last.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  State<CoachTarget> createState() => _CoachTargetState();
}

class _CoachTargetState extends State<CoachTarget> {
  static final _mounted = <CoachSpot, List<_CoachTargetState>>{};

  @override
  void initState() {
    super.initState();
    (_mounted[widget.spot] ??= []).add(this);
  }

  @override
  void dispose() {
    _mounted[widget.spot]?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class CoachMark {
  const CoachMark(this.spot, this.text, {this.also = const []});
  final CoachSpot spot;
  final String text;

  /// 함께 묶어 점선 하나로 감쌀 자리들 (기록하기 메뉴 카드처럼)
  final List<CoachSpot> also;

  /// 묶음 전체의 위치. 첫 자리가 아직 없으면 null.
  Rect? get rect {
    var result = CoachTarget.rectOf(spot);
    for (final other in also) {
      final r = CoachTarget.rectOf(other);
      if (r != null) result = result?.expandToInclude(r);
    }
    return result;
  }
}

/// 점선 · 설명 없이 어둡게 덮지 않고 그대로 보여줄 자리와 그 옆의 작은 글씨
class CoachReveal {
  const CoachReveal(this.spot, this.label);
  final CoachSpot spot;
  final String label;
}

/// 도움말이 떠 있는지. 뒤 화면의 안내 표시를 잠시 숨길 때 쓴다.
final coachOpen = ValueNotifier<bool>(false);

/// 문구에서 대상까지 곧게 이은 화살표의 양 끝
(Offset, Offset) coachArrowEnds(Rect label, Rect hole) {
  const gap = 5.0;
  return label.bottom <= hole.top
      ? (label.bottomCenter, hole.topCenter.translate(0, -gap))
      : (label.topCenter, hole.bottomCenter.translate(0, gap));
}

bool _segmentHits(Offset a, Offset b, Rect rect) {
  for (var t = 0.0; t <= 1; t += 0.05) {
    if (rect.contains(Offset.lerp(a, b, t)!)) return true;
  }
  return false;
}

/// 문구 자리를 정한다. 문구끼리, 또 뚫린 자리와 겹치지 않고 화면 안에 들어오게 한다.
/// 곧은 화살표가 다른 자리나 문구를 지나가지 않는 자리를 먼저 찾고, 그런 자리가 없는
/// 대상(붙어 있는 버튼의 가운데 등)만 마지막에 남은 자리를 쓴다.
/// [holes]와 [sizes]는 같은 순서다. [avoid]는 문구가 피해야 할 자리다.
List<Rect> layoutCoachLabels({
  required Size screen,
  required double top,
  required double bottom,
  required List<Rect> holes,
  required List<Size> sizes,
  List<Rect> avoid = const [],
}) {
  const margin = 16.0;
  const step = 20.0;
  const closest = 10.0; // 대상 사이가 좁을 때 쓰는 가까운 자리
  final placed = <Rect>[];
  final arrows = <Rect>[];
  final result = List<Rect?>.filled(holes.length, null);

  bool isLower(Rect h) => h.center.dy > screen.height / 2;

  List<Rect> candidatesFor(int i) {
    final hole = holes[i];
    final size = sizes[i];
    final maxLeft = screen.width - margin - size.width;
    final left = maxLeft < margin
        ? margin
        : (hole.center.dx - size.width / 2).clamp(margin, maxLeft);
    Rect at(double y) => Rect.fromLTWH(left, y, size.width, size.height);
    final above = [
      for (var y = hole.top - step - size.height; y >= top; y -= step) at(y),
      if (hole.top - closest - size.height >= top)
        at(hole.top - closest - size.height),
    ];
    final below = [
      for (var y = hole.bottom + step; y + size.height <= bottom; y += step)
        at(y),
      if (hole.bottom + closest + size.height <= bottom)
        at(hole.bottom + closest),
    ];
    // 넉넉한 자리부터 보되, 멀리 밀려나기 전에 가까운 자리를 먼저 쓴다.
    for (final list in [above, below]) {
      if (list.length > 2) list.insert(1, list.removeLast());
    }
    return isLower(hole) ? [...above, ...below] : [...below, ...above];
  }

  bool free(Rect r) =>
      r.top >= top &&
      r.bottom <= bottom &&
      !holes.any((h) => h.inflate(4).overlaps(r)) &&
      !avoid.any((a) => a.overlaps(r)) &&
      !placed.any((p) => p.inflate(6).overlaps(r)) &&
      !arrows.any((a) => a.overlaps(r));

  bool directArrow(Rect label, int i) {
    final (start, end) = coachArrowEnds(label, holes[i]);
    for (var j = 0; j < holes.length; j++) {
      if (j != i && _segmentHits(start, end, holes[j])) return false;
    }
    return !placed.any((p) => _segmentHits(start, end, p.inflate(2)));
  }

  void place(int i, Rect label) {
    result[i] = label;
    placed.add(label);
    if (directArrow(label, i)) {
      final (start, end) = coachArrowEnds(label, holes[i]);
      arrows.add(Rect.fromPoints(start, end).inflate(2));
    }
  }

  // 위쪽 대상은 아래쪽 것부터, 아래쪽 대상은 위쪽 것부터 자리를 잡는다.
  final order = [for (var i = 0; i < holes.length; i++) i]..sort((a, b) {
      final lowerA = isLower(holes[a]);
      if (lowerA != isLower(holes[b])) return lowerA ? 1 : -1;
      final byTop = holes[a].top.compareTo(holes[b].top);
      return lowerA ? byTop : -byTop;
    });
  for (final i in order) {
    final label = candidatesFor(i)
        .where((c) => free(c) && directArrow(c, i))
        .firstOrNull;
    if (label != null) place(i, label);
  }
  for (final i in order) {
    if (result[i] != null) continue;
    final candidates = candidatesFor(i);
    final hole = holes[i];
    final size = sizes[i];
    place(
        i,
        candidates.where(free).firstOrNull ??
            candidates.firstOrNull ??
            Rect.fromLTWH(
                margin,
                (hole.bottom + step)
                    .clamp(top, (bottom - size.height).clamp(top, bottom)),
                size.width,
                size.height));
  }
  return [for (final r in result) r!];
}

/// 화면을 어둡게 하고 [marks]의 자리만 뚫어 설명을 보여준다. 아무 데나 누르면 닫힌다.
Future<void> showCoachOverlay(BuildContext context, List<CoachMark> marks,
    {CoachReveal? reveal}) async {
  coachOpen.value = true;
  await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, _, _) => _CoachOverlay(marks: marks, reveal: reveal),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
  coachOpen.value = false;
}

class _CoachOverlay extends StatefulWidget {
  const _CoachOverlay({required this.marks, this.reveal});
  final List<CoachMark> marks;
  final CoachReveal? reveal;

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay> {
  static const _labelMaxWidth = 300.0;
  static const _holePadding = 6.0;
  static const _tightHolePadding = 2.0; // 대상끼리 붙어 있을 때
  static const _buttonWidth = 120.0;
  static const _buttonHeight = 40.0;
  static const _footerHeight = 66.0; // 작은 안내문 + 간격 + 버튼
  static const _footerWidth = 230.0;
  static const _footerRoom = 160.0; // 옮길 때 위아래 설명을 위해 남길 높이
  static const _labelPadding = 8.0;

  List<Rect?> _rects = const [];

  @override
  void initState() {
    super.initState();
    _rects = _measure();
  }

  /// 키보드가 닫히는 등 뒤 화면이 움직이면 그 프레임이 끝난 뒤 구멍을 맞춘다.
  /// MediaQuery가 바뀔 때마다 다시 그려지므로 계속 돌지 않는다.
  void _followTargets() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = _measure();
      for (var i = 0; i < next.length; i++) {
        if (next[i] != _rects[i]) {
          setState(() => _rects = next);
          return;
        }
      }
    });
  }

  List<Rect?> _measure() => [
        for (final m in widget.marks) m.rect,
        if (widget.reveal != null) CoachTarget.rectOf(widget.reveal!.spot),
      ];

  /// 실제로 그릴 글자 스타일로 재서, 글자가 잘리지 않을 자리를 잡는다.
  Size _measureText(String text, TextStyle style, TextScaler scaler, double max) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: max);
    final size = Size(painter.width + 6, painter.height + 4);
    painter.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    _followTargets();
    final media = MediaQuery.of(context);
    final screen = media.size;
    final area = Offset.zero & screen;

    final texts = <String>[];
    final targets = <Rect>[];
    for (var i = 0; i < widget.marks.length; i++) {
      final rect = _rects[i];
      if (rect == null || !rect.overlaps(area)) continue;
      texts.add(widget.marks[i].text);
      targets.add(rect);
    }
    bool overlapWhen(double padding) {
      for (var i = 0; i < targets.length; i++) {
        for (var j = i + 1; j < targets.length; j++) {
          if (targets[i].inflate(padding).overlaps(targets[j].inflate(padding))) {
            return true;
          }
        }
      }
      return false;
    }

    final padding =
        overlapWhen(_holePadding) ? _tightHolePadding : _holePadding;
    final holes = [
      for (final t in targets) t.inflate(padding).intersect(area),
    ];

    final reveal = widget.reveal;
    final revealRect = reveal == null ? null : _rects.last;

    // 안내문과 버튼은 하단 탭보다 위에 둔다. 그 자리에 뚫린 곳이 있으면 왼쪽으로 붙여 보고,
    // 그래도 겹치면 가장 넓은 빈 곳의 가운데로 옮긴다.
    final blocked = [...holes, ?revealRect];
    final safeBottom = screen.height - media.padding.bottom;
    var footerTop =
        safeBottom - AppSpacing.bottomNav - 16 - _footerHeight;
    Rect footerAt(double left) =>
        Rect.fromLTWH(left, footerTop, _footerWidth, _footerHeight);
    var footer = footerAt((screen.width - _footerWidth) / 2);
    if (blocked.any(footer.overlaps)) footer = footerAt(AppSpacing.page);
    final footerMoved = blocked.any(footer.overlaps);
    if (footerMoved) {
      final sorted = [...blocked]..sort((x, y) => x.top.compareTo(y.top));
      var gapTop = media.padding.top;
      var bestTop = gapTop;
      var bestHeight = 0.0;
      // 설명이 들어갈 여유가 있는 빈 곳 중 가장 아래를 쓴다. 없으면 가장 넓은 곳.
      for (final h in [...sorted, Rect.fromLTWH(0, safeBottom, 0, 0)]) {
        final height = h.top - gapTop;
        final roomy = height >= _footerHeight + _footerRoom;
        if (roomy || (height > bestHeight && bestHeight < _footerHeight + _footerRoom)) {
          bestHeight = height;
          bestTop = gapTop;
        }
        if (h.bottom > gapTop) gapTop = h.bottom;
      }
      footerTop = bestTop + (bestHeight - _footerHeight) / 2;
      footer = footerAt((screen.width - _footerWidth) / 2);
    }

    final labelMax =
        _labelMaxWidth.clamp(0.0, screen.width - 32) - _labelPadding * 2;
    final labels = layoutCoachLabels(
      screen: screen,
      top: media.padding.top + 8,
      bottom: safeBottom,
      avoid: [
        footer.inflate(8),
        if (revealRect != null) revealRect.inflate(8),
      ],
      holes: holes,
      sizes: [
        for (final t in texts)
          _measureText(t, AppText.coach, media.textScaler, labelMax) +
              const Offset(_labelPadding * 2, _labelPadding * 2),
      ],
    );

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                  painter: _CoachPainter(
                      holes: holes, labels: labels, reveal: revealRect)),
            ),
            for (var i = 0; i < labels.length; i++)
              Positioned.fromRect(
                rect: labels[i],
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.coachLabel,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(texts[i],
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.visible,
                      style: AppText.coach),
                ),
              ),
            if (reveal != null && revealRect != null)
              Positioned(
                right: screen.width - revealRect.left + 10,
                top: revealRect.center.dy - 10,
                child: Text(reveal.label, style: AppText.coachClose),
              ),
            Positioned.fromRect(
              rect: footer,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('오른쪽 위 ? 버튼으로 다시 볼 수 있어요',
                      style: AppText.coachSmall, maxLines: 1),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: _buttonWidth,
                    height: _buttonHeight,
                    child: TestId(
                      'coach_ok',
                      child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.background,
                        foregroundColor: AppColors.text,
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('알겠어요'),
                    ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachPainter extends CustomPainter {
  _CoachPainter({required this.holes, required this.labels, this.reveal});
  final List<Rect> holes;
  final List<Rect> labels;
  final Rect? reveal;

  static const _radius = Radius.circular(12);

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.saveLayer(area, Paint());
    canvas.drawRect(area, Paint()..color = AppColors.coachScrim);
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final h in holes) {
      canvas.drawRRect(RRect.fromRectAndRadius(h, _radius), clear);
    }
    final shown = reveal;
    if (shown != null) canvas.drawOval(shown, clear);
    canvas.restore();

    final border = Paint()
      ..color = AppColors.background
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final h in holes) {
      _drawDashed(canvas, RRect.fromRectAndRadius(h, _radius), border);
    }

    final arrow = Paint()
      ..color = AppColors.background
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;
    for (var i = 0; i < holes.length; i++) {
      _drawArrow(canvas, i, arrow);
    }
  }

  void _drawDashed(Canvas canvas, RRect rect, Paint paint) {
    const dash = 7.0;
    const gap = 5.0;
    final path = Path()..addRRect(rect);
    for (final PathMetric metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  bool _crossesOthers(Offset a, Offset b, int self) {
    for (var i = 0; i < holes.length; i++) {
      if (i == self) continue;
      if (_segmentHits(a, b, holes[i]) || _segmentHits(a, b, labels[i])) {
        return true;
      }
    }
    return false;
  }

  void _drawArrow(Canvas canvas, int i, Paint paint) {
    const gap = 5.0;
    final label = labels[i];
    final hole = holes[i];
    var (start, end) = coachArrowEnds(label, hole);
    final path = Path();
    final Offset tangent;
    if (_crossesOthers(start, end, i)) {
      // 다른 자리를 가로지르게 되면 문구와 대상들의 왼쪽 빈 곳으로 돌아서 들어간다.
      start = label.centerLeft.translate(-4, 0);
      end = hole.centerLeft.translate(-gap, 0);
      final leftmost = [...labels.map((l) => l.left), ...holes.map((h) => h.left)]
          .reduce((a, b) => a < b ? a : b);
      final lane = (leftmost - 14 - i * 7).clamp(6.0, end.dx);
      path
        ..moveTo(start.dx, start.dy)
        ..cubicTo(lane, start.dy, lane, end.dy, end.dx, end.dy);
      tangent = Offset(end.dx - lane, 0);
    } else {
      final mid = Offset.lerp(start, end, 0.5)!;
      final direction = end - start;
      final normal = direction.distance == 0
          ? Offset.zero
          : Offset(-direction.dy, direction.dx) / direction.distance;
      // 짧은 화살표는 덜 휘게 해서 꼬여 보이지 않게 한다
      final control = mid + normal * (direction.distance * 0.2).clamp(0.0, 14.0);
      path
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      tangent = end - control;
    }
    canvas.drawPath(path, paint);

    // 화살촉: 끝에서 곡선이 들어오는 방향을 기준으로 양쪽 두 줄
    if (tangent.distance == 0) return;
    final unit = tangent / tangent.distance;
    final side = Offset(-unit.dy, unit.dx);
    const head = 8.0;
    canvas.drawLine(end, end - unit * head + side * (head * 0.6), paint);
    canvas.drawLine(end, end - unit * head - side * (head * 0.6), paint);
  }

  @override
  bool shouldRepaint(_CoachPainter old) =>
      old.holes != holes || old.labels != labels || old.reveal != reveal;
}
