import 'package:flutter/material.dart';

class ClearableSearchField extends StatefulWidget {
  const ClearableSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
  });
  final String hintText;
  final ValueChanged<String> onChanged;
  @override
  State<ClearableSearchField> createState() => _ClearableSearchFieldState();
}

class _ClearableSearchFieldState extends State<ClearableSearchField> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: (value) {
      setState(() {});
      widget.onChanged(value);
    },
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      hintText: widget.hintText,
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                controller.clear();
                setState(() {});
                widget.onChanged('');
              },
              icon: const Icon(Icons.close),
            ),
    ),
  );
}
