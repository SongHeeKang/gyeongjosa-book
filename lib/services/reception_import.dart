import '../models/reception.dart';

/// 가져올 항목 1건에 대한 결정.
class ImportItem {
  final ReceptionEntry entry;

  /// 연결할 기존 사람. null이면 entry.name으로 새로 등록한다.
  final int? personId;

  /// 동명이인 가능성이 있어 사용자가 확인해야 하는지
  final bool needsReview;

  const ImportItem(this.entry, this.personId, this.needsReview);
}

/// 받은 장부를 가져올 때의 계획. DB에 쓰기 전에 미리보기 · 한도 안내에도 쓴다.
class ImportPlan {
  /// 이번에 가져올 항목
  final List<ImportItem> items;

  /// 이미 가져온 적이 있어 건너뛴 건수
  final int alreadyImported;

  /// 사람 한도에 걸려 이번에 가져오지 못한 건수
  final int skippedByLimit;

  const ImportPlan(this.items, this.alreadyImported, this.skippedByLimit);

  /// 아직 가져오지 않은 전체 건수
  int get remaining => items.length + skippedByLimit;
  int get reviewCount => items.where((i) => i.needsReview).length;
}

/// 어떤 항목을 어떤 사람에게 연결할지 결정한다. (DB 없이 동작하는 규칙)
///
/// - 이미 가져온 항목(uuid)은 건너뛴다.
/// - 같은 이름의 사람이 있으면 연결하고, 없으면 새 사람으로 등록한다.
/// - 같은 이름이 여러 명이거나, 이 장부에 같은 이름이 이미 있으면 '확인 필요'.
/// - [newPersonSlots]가 있으면 새 사람은 그 수만큼만 등록하고, 나머지는 남겨 둔다.
///   기존 사람에게 연결되는 항목은 한도와 상관없이 가져온다.
ImportPlan buildImportPlan({
  required List<ReceptionEntry> entries,
  required Set<String> importedIds,
  required Map<String, List<int>> peopleByName,
  required Set<String> namesInEvent,
  int? newPersonSlots,
}) {
  final ordered = entries.where((e) => !e.deleted).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final seen = {...namesInEvent};
  final newNames = <String>{};
  final items = <ImportItem>[];
  var already = 0;
  var skipped = 0;

  for (final entry in ordered) {
    if (importedIds.contains(entry.id)) {
      already++;
      continue;
    }
    final name = entry.name.trim();
    final existing = peopleByName[name] ?? const <int>[];
    if (existing.isEmpty && !newNames.contains(name)) {
      if (newPersonSlots != null && newNames.length >= newPersonSlots) {
        skipped++;
        continue;
      }
      newNames.add(name);
    }
    final needsReview = existing.length > 1 || seen.contains(name);
    seen.add(name);
    items.add(
        ImportItem(entry, existing.isEmpty ? null : existing.first, needsReview));
  }
  return ImportPlan(items, already, skipped);
}
