import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/reception.dart';
import 'settings_service.dart';

/// 내 행사 상세의 [장부 보내기]: 내 행사의 받은 기록을 대신 받은 장부와 같은 파일 모양으로 만든다.
/// 받는 쪽(가족) 앱은 예전 버전이어도 같은 방법으로 가져올 수 있다.
///
/// 항목 ID는 '이 설치의 고유값-행사-기록'이라 같은 파일을 다시 보내도 받는 쪽에서
/// 두 번 들어가지 않고, 다른 사람이 보낸 파일과도 겹치지 않는다.
ReceptionPackage eventPackage(
    SharedPreferences prefs, Event event, List<GiftRecord> records) {
  var install = prefs.getString(PrefKeys.installId);
  if (install == null) {
    install = const Uuid().v4();
    prefs.setString(PrefKeys.installId, install);
  }
  final prefix = '$install-e${event.id}';
  return ReceptionPackage(
    Reception(
      id: prefix,
      title: event.title,
      eventType: event.type,
      date: event.date,
      sides: event.sides,
      operatorName: '',
      startedAt: event.date,
      finishedAt: event.date,
      mealTicketEnabled: event.mealTicketEnabled ||
          records.any((r) => (r.mealTickets ?? 0) > 0),
      defaultMealTickets: event.defaultMealTickets,
      methodEnabled: event.methodEnabled ||
          records.any((r) => r.method == ReceptionDefaults.transfer),
    ),
    [
      for (final r in records)
        if (!r.isSent)
          ReceptionEntry(
            id: '$prefix-r${r.id}',
            receptionId: prefix,
            name: r.personName ?? '',
            amount: r.amount,
            side: r.side ?? ReceptionDefaults.noSide,
            method: r.method == ReceptionDefaults.transfer
                ? ReceptionDefaults.transfer
                : ReceptionDefaults.cash,
            mealTickets: r.mealTickets ?? 0,
            memo: r.memo,
            createdAt: r.date,
          ),
    ],
  );
}
