import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../models/gift_record.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';

/// 받은 돈은 '+50,000원', 보낸 돈은 '−50,000원'
String signedWon(int amount, {required bool isSent}) =>
    '${isSent ? '−' : '+'}${formatWon(amount)}';

/// FutureProvider 결과를 로딩/오류/데이터로 나눠 그린다.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Text('불러오지 못했어요.\n$e',
              textAlign: TextAlign.center, style: AppText.sub),
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 24, horizontal: AppSpacing.page),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: AppColors.divider),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: AppText.sub.copyWith(height: 1.5)),
        ],
      ),
    );
  }
}

/// 섹션 제목 (16/700) + 오른쪽 링크 등
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.section, AppSpacing.page - 8, 6),
      child: Row(
        children: [
          Expanded(child: Text(text, style: AppText.sectionTitle)),
          ?trailing,
        ],
      ),
    );
  }
}

/// 오른쪽 '전체 보기' 같은 링크
class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Text(text, style: AppText.link),
        ),
      );
}

/// 요약 한 칸: 라벨(13) / 금액(24) / 건수(13)
class SummaryColumn extends StatelessWidget {
  const SummaryColumn({
    super.key,
    required this.label,
    required this.amount,
    this.count,
    this.highlight = false,
  });
  final String label;
  final int amount;
  final int? count;

  /// true면 금액을 포인트색으로 (받은 돈)
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.label),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatWon(amount),
                style: AppText.summaryAmount.copyWith(
                    color: highlight ? AppColors.primary : AppColors.text)),
          ),
          if (count != null) ...[
            const SizedBox(height: 2),
            Text('$count건', style: AppText.sub),
          ],
        ],
      ),
    );
  }
}

/// 두 칸 요약 (보낸 마음 · 받은 마음)
class SummaryRow extends StatelessWidget {
  const SummaryRow({
    super.key,
    required this.sent,
    required this.received,
    this.sentCount,
    this.receivedCount,
    this.sentLabel = '보낸 마음',
    this.receivedLabel = '받은 마음',
  });
  final int sent;
  final int received;
  final int? sentCount;
  final int? receivedCount;
  final String sentLabel;
  final String receivedLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        children: [
          SummaryColumn(label: sentLabel, amount: sent, count: sentCount),
          const SizedBox(width: 16),
          SummaryColumn(
              label: receivedLabel,
              amount: received,
              count: receivedCount,
              highlight: true),
        ],
      ),
    );
  }
}

/// 내역 한 줄: 이름(15/500) · 보조 설명(13) · 금액(15/700)
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.record,
    this.showPerson = false,
    this.onTap,
  });
  final GiftRecord record;
  final bool showPerson;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = showPerson
        ? (record.personName ?? '')
        : (record.eventLabel.isEmpty ? record.direction : record.eventLabel);
    final sub = <String>[
      formatDotDate(record.date),
      if (showPerson && record.eventLabel.isNotEmpty) record.eventLabel,
      record.method,
      if ((record.memo ?? '').isNotEmpty) record.memo!,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page, vertical: AppSpacing.item),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.listName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: AppText.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (record.needsReview) ...[
                    const SizedBox(height: 2),
                    const Text('확인 필요 · 동명이인일 수 있어요',
                        style: AppText.warning),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(signedWon(record.amount, isSent: record.isSent),
                style: AppText.listAmount
                    .copyWith(color: AppColors.amount(record.isSent))),
          ],
        ),
      ),
    );
  }
}

/// 행사 한 줄: 왼쪽 D-day, 이름, 날짜 · 종류
class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.event,
    this.subtitle,
    this.highlight = false,
    this.onTap,
  });
  final Event event;
  final String? subtitle;

  /// 가장 가까운 행사만 D-day를 포인트색으로
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final upcoming = !event.date.isBefore(dateOnly(DateTime.now()));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page, vertical: AppSpacing.item),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                upcoming ? dDay(event.date) : formatShortDate(event.date),
                style: AppText.dDay.copyWith(
                    color: highlight && upcoming
                        ? AppColors.primary
                        : AppColors.icon),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      style: AppText.listName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    subtitle ??
                        [
                          formatDate(event.date),
                          event.isMine ? '내 ${event.type}' : event.type,
                        ].join(' · '),
                    style: AppText.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.divider),
          ],
        ),
      ),
    );
  }
}

/// 오른쪽 아래에 떠 있는 알약 모양 버튼 (높이 52, 모서리 26, 좌우 22)
class PillActionButton extends StatelessWidget {
  const PillActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      elevation: 3,
      shadowColor: AppColors.primary.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onPressed,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 6),
                Text(label,
                    style: AppText.button.copyWith(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 떠 있는 버튼 위치: 하단 메뉴 위 20, 오른쪽 24
class PillFabLocation extends StandardFabLocation {
  const PillFabLocation();

  @override
  double getOffsetX(
          ScaffoldPrelayoutGeometry scaffoldGeometry, double adjustment) =>
      scaffoldGeometry.scaffoldSize.width -
      AppSpacing.page -
      scaffoldGeometry.floatingActionButtonSize.width;

  @override
  double getOffsetY(
          ScaffoldPrelayoutGeometry scaffoldGeometry, double adjustment) =>
      scaffoldGeometry.contentBottom -
      20 -
      scaffoldGeometry.floatingActionButtonSize.height;
}

/// 화면 아래 여백 (떠 있는 버튼에 가리지 않게)
const fabBottomSpace = SizedBox(height: 96);

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String okText = '확인',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.textSub),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소')),
        TextButton(
          style: TextButton.styleFrom(
              foregroundColor:
                  destructive ? AppColors.error : AppColors.primary),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okText,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 아래 시트/폼 안의 작은 라벨
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: AppText.label),
      );
}
