import 'package:flutter/material.dart';

/// 디자인 A (클린 화이트): 흰 바탕 + 파란 포인트 하나.
/// 모든 화면은 여기 있는 색 · 글자 · 간격만 쓴다.
class AppColors {
  static const background = Color(0xFFFFFFFF);
  static const text = Color(0xFF111827); // 기본 글자
  static const textSub = Color(0xFF4B5563); // 보조 글자
  static const icon = Color(0xFF374151); // 아이콘 버튼, 덜 급한 D-day
  static const divider = Color(0xFFE5E7EB); // 구분선
  static const primary = Color(0xFF2563EB); // 포인트 (받은 금액, D-day, 선택 탭, 버튼)
  static const link = Color(0xFF1D4ED8); // 링크 (전체 보기)
  static const primarySoft = Color(0xFFEFF4FF); // 선택된 칩 배경
  static const error = Color(0xFFDC2626);
  static const chartSent = Color(0xFF9CA3AF); // 차트의 보냄 막대
  static const guidePanel = Color(0xFFEEF4FF); // 가이드 그림의 연파랑 패널
  static const guideChip = Color(0xFFDBEAFE); // 가이드 그림의 칩 바탕
  static const guideChipText = Color(0xFF1E40AF); // 가이드 그림의 칩 글자
  static const success = Color(0xFF16A34A); // 가이드 그림의 초록 체크

  /// 받은 돈 = 포인트색, 보낸 돈 = 기본 글자색
  static Color amount(bool isSent) => isSent ? text : primary;
}

class AppSpacing {
  static const page = 24.0; // 좌우 여백
  static const section = 28.0; // 섹션 사이
  static const item = 10.0; // 목록 항목 위아래 여백
  static const padButton = 48.0; // 접수 화면 키보드 위 금액 버튼 높이
  static const receptionButton = 56.0; // 접수 화면 그 밖의 버튼 높이
}

class AppText {
  static const fontFamily = 'NotoSansKR';

  static const appTitle = TextStyle(
      fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.text);
  static const summaryAmount = TextStyle(
      fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppColors.text);
  static const sectionTitle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text);
  static const listName =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text);
  static const sub =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSub);
  static const listAmount =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text);
  static const body =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.text);
  static const label =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSub);
  static const dDay = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
  static const link =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.link);
  static const button = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);

  // 접수 화면: 행사장에서 빠르게 보도록 크게
  static const receptionInput = TextStyle(
      fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.text);
  static const receptionAmount = TextStyle(
      fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w700);
  static const receptionButton = TextStyle(
      fontFamily: fontFamily, fontSize: 17, fontWeight: FontWeight.w700);
  static const receptionName = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.text);
  static const warning = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.error);

  // 첫 실행 가이드
  static const guideTitle = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text);
  static const guideBody = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textSub);
  static const guideSmall = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.text);
}

/// 섹션을 나누는 1px 구분선
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.indent = 0});
  final double indent;

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        color: AppColors.divider,
        indent: indent,
        endIndent: indent,
      );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.background,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textSub,
    outline: AppColors.divider,
    outlineVariant: AppColors.divider,
    surfaceContainerLowest: AppColors.background,
    surfaceContainerLow: AppColors.background,
    surfaceContainer: AppColors.background,
    surfaceContainerHigh: AppColors.background,
    surfaceContainerHighest: const Color(0xFFF3F4F6),
    error: AppColors.error,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: AppText.fontFamily,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkRipple.splashFactory,
  );

  final buttonShape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  const buttonSize = Size(64, 52);

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
      fontFamily: AppText.fontFamily,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: AppSpacing.page,
      titleTextStyle: AppText.appTitle,
      iconTheme: IconThemeData(color: AppColors.icon, size: 24),
      actionsIconTheme: IconThemeData(color: AppColors.icon, size: 24),
    ),
    dividerTheme: const DividerThemeData(
        color: AppColors.divider, thickness: 1, space: 1),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: AppColors.background,
      margin: EdgeInsets.zero,
    ),
    iconTheme: const IconThemeData(color: AppColors.icon),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.icon,
        minimumSize: const Size(44, 44),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.divider,
        minimumSize: buttonSize,
        shape: buttonShape,
        textStyle: AppText.button,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        minimumSize: buttonSize,
        shape: buttonShape,
        side: const BorderSide(color: AppColors.divider),
        textStyle: AppText.button.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.link,
        minimumSize: const Size(44, 44),
        textStyle: AppText.button.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 2,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: false,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(fontSize: 15, color: AppColors.textSub),
      floatingLabelStyle: TextStyle(fontSize: 13, color: AppColors.primary),
      hintStyle: TextStyle(fontSize: 15, color: Color(0xFF9CA3AF)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.background,
      selectedColor: AppColors.primarySoft,
      side: const BorderSide(color: AppColors.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text),
      secondaryLabelStyle: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
      checkmarkColor: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textSub,
        selectedBackgroundColor: AppColors.primarySoft,
        selectedForegroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.divider),
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.divider),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
      minVerticalPadding: AppSpacing.item,
      titleTextStyle: AppText.listName,
      subtitleTextStyle: AppText.sub,
      iconColor: AppColors.icon,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: AppColors.divider,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: const TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text),
      contentTextStyle: const TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 15,
          height: 1.5,
          color: AppColors.textSub),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.background,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(
          fontFamily: AppText.fontFamily, fontSize: 15, color: AppColors.text),
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: AppColors.background,
      headerForegroundColor: AppColors.text,
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.primary),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      contentTextStyle: TextStyle(
          fontFamily: AppText.fontFamily, fontSize: 14, color: Colors.white),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      tilePadding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
      shape: Border(),
      collapsedShape: Border(),
      iconColor: AppColors.icon,
      collapsedIconColor: AppColors.icon,
    ),
  );
}
