import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/providers.dart';
import 'screens/main_shell.dart';
import 'screens/manage_space_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs)],
  );

  runApp(UncontrolledProviderScope(
    container: container,
    child: const GyeongjosaApp(),
  ));

  // 화면을 먼저 띄우고 나서 알림 재예약 · 구매 내역 확인
  await NotificationService.instance.init();
  final events = await container.read(repositoryProvider).allEvents();
  await NotificationService.instance.resyncAll(events);
  await container.read(purchaseProvider.notifier).init();
}

/// 안드로이드 설정의 '공간 관리'에서 열리는 화면의 시작점 (ManageSpaceActivity.kt)
@pragma('vm:entry-point')
Future<void> manageSpaceMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  runApp(MaterialApp(
    title: '경조사 장부',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: _appLocale,
    supportedLocales: const [_appLocale],
    localizationsDelegates: _appLocalizations,
    home: const ManageSpaceScreen(),
  ));
}

const _appLocale = Locale('ko', 'KR');
const _appLocalizations = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class GyeongjosaApp extends ConsumerWidget {
  const GyeongjosaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(onboardingSeenProvider);
    return MaterialApp(
      title: '경조사 장부',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: _appLocale,
      supportedLocales: const [_appLocale],
      localizationsDelegates: _appLocalizations,
      home: seen ? const MainShell() : const OnboardingScreen(),
    );
  }
}
