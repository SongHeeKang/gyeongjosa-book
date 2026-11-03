import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/providers.dart';
import 'screens/main_shell.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';
import 'services/settings_service.dart';

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

class GyeongjosaApp extends StatelessWidget {
  const GyeongjosaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '경조사 장부',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainShell(),
    );
  }
}

/// 40~60대 사용자를 위해 글자와 버튼을 넉넉하게
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8D5B3F),
    brightness: Brightness.light,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final t = base.textTheme;
  const buttonSize = Size(64, 52);
  const buttonText = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
  return base.copyWith(
    textTheme: t.copyWith(
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 18),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 17),
      bodySmall: t.bodySmall?.copyWith(fontSize: 15),
      titleLarge: t.titleLarge?.copyWith(fontSize: 23, fontWeight: FontWeight.bold),
      titleMedium: t.titleMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w600),
      titleSmall: t.titleSmall?.copyWith(fontSize: 17),
      labelLarge: t.labelLarge?.copyWith(fontSize: 17),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: buttonSize, textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: buttonSize, textStyle: buttonText),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(minimumSize: buttonSize, textStyle: buttonText),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), textStyle: buttonText),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(fontSize: 17),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: const TextStyle(fontSize: 16, color: Colors.black87),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    listTileTheme: const ListTileThemeData(
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
      subtitleTextStyle: TextStyle(fontSize: 15, color: Colors.black54),
      minVerticalPadding: 12,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: TextStyle(fontSize: 16),
    ),
  );
}
