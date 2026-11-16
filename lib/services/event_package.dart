import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/reception.dart';
import 'settings_service.dart';

/// 내 행사 상세의 [장부 보내기]: 내 행사의 받은 기록을 다른 사람 행사와 같은 묶음으로 만들어 글자로 보낸다.
/// (받는 쪽에서 같은 메시지를 두 번 붙여도 겹치지 않는 것은 ledger_text_format.dart가 맡는다)
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
