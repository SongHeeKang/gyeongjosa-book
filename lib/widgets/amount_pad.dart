import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/constants.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import 'test_id.dart';
import 'amount_input.dart';

/// 행사장 접수와 받은 명단 직접 입력이 함께 쓰는 금액 입력 묶음.
/// 한쪽을 고치면 다른 쪽도 같이 바뀐다.

/// 키보드와 제목을 뺀 공간이 아주 작은 폰: 금액 패드를 낮추고 확인 줄을 뺀다.
bool isAmountAreaTight(BuildContext context) {
  final media = MediaQuery.of(context);
  return media.size.height -
          media.viewInsets.bottom -
          media.padding.vertical -
          kToolbarHeight <
      AppSpacing.receptionTightBody;
}

/// 최근 저장 한 줄의 내용
class RecentSavedItem {
  const RecentSavedItem({
    required this.id,
    required this.name,
    required this.amount,
    required this.savedAt,
    this.details = const [],
  });
  final Object id;
  final String name;
  final int amount;
  final DateTime savedAt;

  /// 금액과 시각 사이에 넣을 내용 (식권, 계좌 등)
  final List<InlineSpan> details;
}

/// 금액 버튼 바로 위 줄: 금액칸 + 식권 칩 + 계좌 칩, 그 아래에 읽기 쉬운 금액.
/// 키보드의 완료를 누르면 저장된다. 칩까지 한 줄에 안 들어가는 폰에서는 칩을 윗줄로 올린다.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSave,
    required this.tight,
    this.meals,
    this.onMeals,
    this.transfer,
    this.onTransfer,
  });
  final bool tight;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSave;

  /// 식권 기록을 끄면 null
  final int? meals;
  final ValueChanged<int>? onMeals;

  /// 결제 방법 구분을 끄면 null
  final bool? transfer;
  final VoidCallback? onTransfer;

  static const _maxChipWidth = 36.0;
  static const _minChipWidth = 28.0;
  static const _chipGap = 3.0;
  static const _transferWidth = 48.0;
  static const _transferGap = 6.0;
  static const _minFieldWidth = 84.0;
  static const _fieldGap = 8.0;

  double get _extrasWidth =>
      (meals != null ? 4 * _chipGap : 0) +
      (transfer != null ? _transferWidth : 0) +
      (meals != null && transfer != null ? _transferGap : 0);

  /// 금액칸과 한 줄에 넣을 수 있는 식권 칩 폭. 화면이 넓어도 커지기만 하고 금액칸을 넓게 남긴다.
  double _chipWidthFor(double maxWidth) {
    final room = maxWidth - _minFieldWidth - _fieldGap - _extrasWidth;
    return (room / 5).clamp(0.0, _maxChipWidth);
  }

  /// 4+는 누를 때마다 한 장씩 늘어난다.
  void _pickMeals(int value) {
    final current = meals!;
    onMeals?.call(value == 4 && current >= 4 ? current + 1 : value);
  }

  Widget _chip(String testId, String label, bool selected, VoidCallback onTap,
      double width) {
    return TestId(testId, selected: selected, child: SizedBox(
      width: width,
      height: AppSpacing.padButton,
      child: OutlinedButton(
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: AppText.receptionChip,
          backgroundColor: selected ? AppColors.primarySoft : null,
          foregroundColor: selected ? AppColors.primary : AppColors.text,
          side: selected
              ? const BorderSide(color: AppColors.primary, width: 1.5)
              : const BorderSide(color: AppColors.divider),
        ),
        child: Text(label),
      ),
    ));
  }

  Widget _chips(double chipWidth) {
    final current = meals;
    final paying = transfer;
    // 칩이 포커스를 가져가면 키보드가 닫히므로 포커스를 받지 않게 한다.
    return ExcludeFocus(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (current != null) ...[
            for (var count = 0; count <= 4; count++) ...[
              if (count > 0) const SizedBox(width: _chipGap),
              _chip(
                count < 4 ? 'chip_meal_$count' : 'chip_meal_more',
                count < 4 ? '$count' : (current > 4 ? '$current' : '4+'),
                count < 4 ? current == count : current >= 4,
                () => _pickMeals(count),
                chipWidth,
              ),
            ],
          ],
          if (current != null && paying != null)
            const SizedBox(width: _transferGap),
          if (paying != null)
            _chip('chip_account', '계좌', paying, () => onTransfer?.call(),
                _transferWidth),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = TestId('input_amount_pad', child: TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [ThousandsFormatter()],
      style: AppText.receptionName,
      onEditingComplete: () {},
      onSubmitted: (_) => onSave(),
      decoration: const InputDecoration(
        hintText: '금액',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
    ));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 0),
      child: LayoutBuilder(builder: (context, constraints) {
        final hasMeals = meals != null;
        final hasChips = hasMeals || transfer != null;
        final fitted = _chipWidthFor(constraints.maxWidth);
        // 아주 좁은 폰에서만 칩을 윗줄로 올린다.
        final sameLine = hasChips && (!hasMeals || fitted >= _minChipWidth);
        final chipWidth = sameLine ? fitted : _maxChipWidth;
        final chips = _chips(chipWidth);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasChips && !sameLine) ...[
              SizedBox(
                height: AppSpacing.padButton,
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: chips),
              ),
              const SizedBox(height: 4),
            ],
            SizedBox(
              height: AppSpacing.padButton,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: field),
                  if (sameLine) ...[
                    const SizedBox(width: _fieldGap),
                    chips,
                  ],
                ],
              ),
            ),
            // 맞게 쳤는지 확인하는 줄. 자리를 미리 잡아 입력할 때 칸이 움직이지 않게 한다.
            // 키보드를 뺀 공간이 아주 작은 폰에서는 생략한다.
            if (!tight)
              SizedBox(
                height: 20,
                child: Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: controller,
                        builder: (_, value, _) {
                          final amount = parseAmount(value.text);
                          return TestId('amount_hint', child: Text(
                              amount > 0 ? formatReadableWon(amount) : '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.sub));
                        },
                      ),
                    ),
                    if (hasMeals)
                      SizedBox(
                        width: 5 * chipWidth + 4 * _chipGap +
                            (transfer != null
                                ? _transferGap + _transferWidth
                                : 0),
                        child: const Text('식권', style: AppText.label),
                      ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// 금액 버튼 8개(4개씩 2줄). 키보드 바로 위에 붙고, 누르면 짧게 진동한다.
class AmountPad extends StatelessWidget {
  const AmountPad({super.key, required this.onAmount, required this.buttonHeight});
  final ValueChanged<int> onAmount;
  final double buttonHeight;

  @override
  Widget build(BuildContext context) {
    const perRow = 4;
    const amounts = ReceptionDefaults.amounts;
    Widget button(int amount) => Expanded(
          child: TestId('amount_$amount', child: FilledButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              onAmount(amount);
            },
            style: FilledButton.styleFrom(
              minimumSize: Size(0, buttonHeight),
              maximumSize: Size(double.infinity, buttonHeight),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: AppText.receptionAmount,
            ),
            child: Text(formatManWon(amount)),
          )),
        );
    // 버튼이 포커스를 가져가면 키보드가 닫히므로 포커스를 받지 않게 한다.
    return ExcludeFocus(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, 4, AppSpacing.page, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < amounts.length; i += perRow) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (var j = i; j < i + perRow; j++) ...[
                    if (j > i) const SizedBox(width: 8),
                    button(amounts[j]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 최근 저장 목록: 새 항목이 맨 위에 들어오며 1초쯤 강조되고, 전 항목은 한 칸씩 밀리며 흐려진다.
/// 되돌리기와 같은 이름 경고는 맨 위 항목 기준이다. 넘치는 항목은 이 목록에서만 사라진다.
class RecentSavedList extends StatefulWidget {
  const RecentSavedList({
    super.key,
    required this.items,
    required this.lines,
    required this.warn,
    required this.onUndo,
  });

  /// 최신이 맨 앞
  final List<RecentSavedItem> items;
  final int lines;

  /// '같은 이름이 있어요' 경고를 보여줄지
  final bool warn;
  final VoidCallback onUndo;

  static const warningHeight = 22.0;

  @override
  State<RecentSavedList> createState() => _RecentSavedListState();
}

class _RecentSavedListState extends State<RecentSavedList>
    with SingleTickerProviderStateMixin {
  // 끝난 상태(1)로 시작해 화면을 다시 열었을 때는 강조하지 않는다.
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(seconds: 1), value: 1);

  @override
  void didUpdateWidget(RecentSavedList old) {
    super.didUpdateWidget(old);
    final entries = widget.items;
    // 되돌리기로 줄어들 때는 움직이지 않고, 새로 저장했을 때만 움직인다.
    if (entries.isNotEmpty &&
        !old.items.any((e) => e.id == entries.first.id)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _line(RecentSavedItem item, {required bool latest, Color? background}) {
    return Container(
      height: AppSpacing.recentLine,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Icon(Icons.check,
              size: 16,
              color: latest ? AppColors.primary : AppColors.textSub),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${item.name} · ${formatManWon(item.amount)} · '),
                ...item.details,
                TextSpan(text: formatTime(item.savedAt)),
              ]),
              style: latest ? AppText.body : AppText.sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.items;
    final latest = entries.isEmpty ? null : entries.first;
    final warn = widget.warn;
    final visible = entries.length.clamp(0, widget.lines);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (warn)
          const SizedBox(
            height: RecentSavedList.warningHeight,
            child: TestId('recent_warning',
                child: Text('같은 이름이 있어요', style: AppText.warning)),
          ),
        if (latest != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (_, _) {
                    // 앞의 4분의 1 동안 한 칸 내려오고, 강조는 1초에 걸쳐 사라진다.
                    final slide = 1 -
                        Curves.easeOut
                            .transform((_controller.value * 4).clamp(0.0, 1.0));
                    final count = visible + (slide > 0 ? 1 : 0);
                    return SizedBox(
                      height: visible * AppSpacing.recentLine,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          maxHeight: double.infinity,
                          child: Transform.translate(
                            offset: Offset(0, -slide * AppSpacing.recentLine),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final (i, e)
                                    in entries.take(count).indexed)
                                  TestId('recent_item_$i', child: _line(
                                    e,
                                    latest: i == 0,
                                    background: i == 0
                                        ? Color.lerp(
                                            AppColors.primarySoft,
                                            AppColors.primarySoft.withValues(alpha: 0),
                                            _controller.value)
                                        : null,
                                  )),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 줄은 낮아도 되돌리기는 누르기 쉽게 44 높이를 준다
              SizedBox(
                height: 44,
                child: ExcludeFocus(
                  child: TestId('recent_undo', child: TextButton(
                    onPressed: widget.onUndo,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.topCenter,
                    ),
                    child: const Text('되돌리기'),
                  )),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

