import 'package:flutter/material.dart';

import '../models/person.dart';
import '../theme/app_theme.dart';

/// 이름 입력칸 + 기존 사람 자동완성
class PersonNameField extends StatelessWidget {
  const PersonNameField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.people,
    required this.onSelected,
    required this.onChanged,
    this.hintText,
    this.helperText,
    this.autofocus = false,
    this.errorText,
    this.onEditingComplete,
    this.optionsMaxHeight = 280,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<Person> people;
  final ValueChanged<Person> onSelected;
  final VoidCallback onChanged;
  final String? hintText;
  final String? helperText;
  final bool autofocus;
  final String? errorText;

  /// 키보드의 다음을 눌렀을 때
  final VoidCallback? onEditingComplete;

  /// 자동완성 목록 최대 높이. 아래 버튼을 가리지 않게 줄일 때 쓴다.
  final double optionsMaxHeight;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Person>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (p) => p.name,
      optionsBuilder: (value) {
        final q = value.text.trim();
        if (q.isEmpty) return const Iterable<Person>.empty();
        return people.where((p) => p.name.contains(q)).take(6);
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        onChanged: (_) => onChanged(),
        onEditingComplete: onEditingComplete,
        decoration: InputDecoration(
          labelText: '이름',
          hintText: hintText,
          helperText: helperText,
          errorText: errorText,
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: optionsMaxHeight,
                maxWidth:
                    MediaQuery.of(context).size.width - AppSpacing.page * 2),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final p in options)
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text([
                      p.relation,
                      if ((p.phone ?? '').isNotEmpty) p.phone!,
                    ].join(' · ')),
                    onTap: () => onSelected(p),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
