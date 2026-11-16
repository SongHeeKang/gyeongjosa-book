import 'package:flutter/material.dart';

import '../models/event.dart';
import '../services/receive_targets.dart';
import 'receive_money_screen.dart';
import 'reception_form_screen.dart';

/// 행사 만들기 화면을 연다. 맨 위에서 '누구 행사예요?'를 고르고, 저장하면 바로 받은 돈 적기로 간다.
/// 내 행사 한도는 [내 행사]를 고르는 순간 검사한다.
Future<void> openCreateEvent(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const ReceptionFormScreen()));

/// 내 행사의 받은 돈 적기를 연다. 받기 설정이 없는 예전 내 행사면 설정(구분 · 식권 · 결제 방법)부터 묻는다.
Route<void> myEventReceiveRoute(Event event) => MaterialPageRoute<void>(
    builder: (_) => event.receiveSettingsDone
        ? ReceiveMoneyScreen(target: MyEventTarget(event.id!))
        : ReceptionFormScreen.myEvent(event: event));

/// 다른 사람 행사의 받은 돈 적기
Route<void> receptionReceiveRoute(String receptionId) =>
    MaterialPageRoute<void>(
        builder: (_) =>
            ReceiveMoneyScreen(target: ReceptionTarget(receptionId)));
