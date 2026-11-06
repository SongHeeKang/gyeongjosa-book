import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 도움말이 가리킬 수 있는 자리
enum CoachSpot {
  recordButton,
  homePending,
  homeHelp,
  menuSent,
  menuSchedule,
  menuDirect,
  menuReception,
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
  const CoachMark(this.spot, this.text);
  final CoachSpot spot;
  final String text;
}

/// 문구 자리를 정한다. 문구끼리, 또 뚫린 자리와 겹치지 않고 화면 안에 들어오게 한다.
/// [holes]와 [sizes]는 같은 순서이고, 앞의 문구부터 대상에 가까운 자리를 차지한다.
List<Rect> layoutCoachLabels({
  required Size screen,
  required double top,
  required double bottom,
  required List<Rect> holes,
  required List<Size> sizes,
}) {
  const margin = 16.0;
  const step = 20.0;
  final placed = <Rect>[];
  for (var i = 0; i < holes.length; i++) {
    final hole = holes[i];
    final size = sizes[i];
    final maxLeft = screen.width - margin - size.width;
    final left = maxLeft < margin
        ? margin
        : (hole.center.dx - size.width / 2).clamp(margin, maxLeft);
    Rect at(double y) => Rect.fromLTWH(left, y, size.width, size.height);
    bool free(Rect r) =>
        r.top >= top &&
        r.bottom <= bottom &&
        !holes.any((h) => h.inflate(4).overlaps(r)) &&
        !placed.any((p) => p.inflate(6).overlaps(r));

    final above = [
      for (var y = hole.top - step - size.height; y >= top; y -= step) at(y),
    ];
    final below = [
      for (var y = hole.bottom + step;
          y + size.height <= bottom;
          y += step)
        at(y),
    ];
    final preferAbove = hole.center.dy > screen.height / 2;
    final candidates =
        preferAbove ? [...above, ...below] : [...below, ...above];
    placed.add(candidates.where(free).firstOrNull ??
        (candidates.isNotEmpty
            ? candidates.first
            : at((hole.bottom + step).clamp(top, bottom - size.height))));
  }
  return placed;
}

/// 화면을 어둡게 하고 [marks]의 자리만 뚫어 설명을 보여준다. 아무 데나 누르면 닫힌다.
Future<void> showCoachOverlay(BuildContext context, List<CoachMark> marks) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, _, _) => _CoachOverlay(marks: marks),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

class _CoachOverlay extends StatefulWidget {
  const _CoachOverlay({required this.marks});
  final List<CoachMark> marks;

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay> {
  static const _labelMaxWidth = 260.0;
  static const _buttonWidth = 120.0;
  static const _buttonHeight = 40.0;
  static const _footerHeight = 76.0; // 버튼 + 간격 + 작은 안내문

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

  List<Rect?> _measure() =>
      [for (final m in widget.marks) CoachTarget.rectOf(m.spot)];

  Size _measureText(String text, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: AppText.coach),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: _labelMaxWidth);
    final size = Size(painter.width + 2, painter.height + 2);
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
    final holes = <Rect>[];
    for (var i = 0; i < widget.marks.length; i++) {
      final rect = _rects[i];
      if (rect == null || !rect.overlaps(area)) continue;
      texts.add(widget.marks[i].text);
      holes.add(rect.inflate(6).intersect(area));
    }

    // 버튼은 맨 아래 가운데. 그 자리에 뚫린 곳이 있으면 그 위로 올린다.
    var footerTop = screen.height - media.padding.bottom - 12 - _footerHeight;
    final buttonX = Rect.fromCenter(
        center: Offset(screen.width / 2, footerTop),
        width: _buttonWidth,
        height: 1);
    for (final h in holes) {
      final overlapsX = h.left < buttonX.right && h.right > buttonX.left;
      if (overlapsX && h.bottom > footerTop) {
        footerTop = h.top - _footerHeight - 8;
      }
    }

    final labels = layoutCoachLabels(
      screen: screen,
      top: media.padding.top + 8,
      bottom: footerTop - 8,
      holes: holes,
      sizes: [for (final t in texts) _measureText(t, media.textScaler)],
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
                  painter: _CoachPainter(holes: holes, labels: labels)),
            ),
            for (var i = 0; i < labels.length; i++)
              Positioned.fromRect(
                rect: labels[i],
                child: Text(texts[i],
                    textAlign: TextAlign.center, style: AppText.coach),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: footerTop,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: _buttonWidth,
                    height: _buttonHeight,
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
                  const SizedBox(height: 8),
                  const Text('오른쪽 위 ? 버튼으로 다시 볼 수 있어요',
                      style: AppText.coachSmall),
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
  _CoachPainter({required this.holes, required this.labels});
  final List<Rect> holes;
  final List<Rect> labels;

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

  bool _crossesOtherHole(Offset a, Offset b, int self) {
    for (var i = 0; i < holes.length; i++) {
      if (i == self) continue;
      for (var t = 0.0; t <= 1; t += 0.05) {
        if (holes[i].contains(Offset.lerp(a, b, t)!)) return true;
      }
    }
    return false;
  }

  void _drawArrow(Canvas canvas, int i, Paint paint) {
    const gap = 5.0;
    final label = labels[i];
    final hole = holes[i];
    final isAbove = label.bottom <= hole.top;
    var start = isAbove ? label.bottomCenter : label.topCenter;
    var end = isAbove
        ? hole.topCenter.translate(0, -gap)
        : hole.bottomCenter.translate(0, gap);
    late Offset control;
    if (_crossesOtherHole(start, end, i)) {
      // 다른 자리를 가로지르면 옆으로 돌아서 왼쪽 가운데를 가리킨다.
      start = isAbove
          ? label.bottomLeft.translate(8, 0)
          : label.topLeft.translate(8, 0);
      end = hole.centerLeft.translate(-gap, 0);
      control = Offset(end.dx - 26, end.dy - (isAbove ? 34 : -34));
    } else {
      final mid = Offset.lerp(start, end, 0.5)!;
      final direction = end - start;
      final normal = direction.distance == 0
          ? Offset.zero
          : Offset(-direction.dy, direction.dx) / direction.distance;
      control = mid + normal * 14;
    }
    canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy),
        paint);

    // 화살촉: 끝에서 곡선이 들어오는 방향을 기준으로 양쪽 두 줄
    final tangent = end - control;
    if (tangent.distance == 0) return;
    final unit = tangent / tangent.distance;
    final side = Offset(-unit.dy, unit.dx);
    const head = 8.0;
    canvas.drawLine(end, end - unit * head + side * (head * 0.6), paint);
    canvas.drawLine(end, end - unit * head - side * (head * 0.6), paint);
  }

  @override
  bool shouldRepaint(_CoachPainter old) =>
      old.holes != holes || old.labels != labels;
}
