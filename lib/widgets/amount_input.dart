import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/format.dart';

/// 입력 중에 50,000 처럼 쉼표를 넣어준다.
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final trimmed = digits.length > 12 ? digits.substring(0, 12) : digits;
    final text = formatNumber(int.parse(trimmed));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

int parseAmount(String text) =>
    int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// 금액 빠른 버튼 + 직접 입력
class AmountInput extends StatelessWidget {
  const AmountInput({
    super.key,
    required this.controller,
    this.quickAmounts = const [50000, 100000, 200000],
    this.focusNode,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final List<int> quickAmounts;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final current = parseAmount(controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final a in quickAmounts) ...[
              Expanded(
                child: current == a
                    ? FilledButton(
                        onPressed: () => _set(a),
                        child: Text(formatManWon(a)))
                    : OutlinedButton(
                        onPressed: () => _set(a),
                        child: Text(formatManWon(a))),
              ),
              if (a != quickAmounts.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          inputFormatters: [ThousandsFormatter()],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            labelText: '금액 직접 입력',
            suffixText: '원',
          ),
          onChanged: (_) => onChanged?.call(),
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }

  void _set(int amount) {
    final text = formatNumber(amount);
    controller.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    onChanged?.call();
  }
}

/// 한 줄짜리 선택 칩 묶음
class ChoiceChips extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o),
            selected: o == selected,
            onSelected: (_) => onSelected(o),
          ),
      ],
    );
  }
}
