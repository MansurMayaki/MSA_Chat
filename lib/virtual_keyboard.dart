import 'package:flutter/material.dart';
import 'main.dart' show AppColors;

class VirtualKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onDone;

  const VirtualKeyboard({
    super.key,
    required this.controller,
    required this.onDone,
  });

  @override
  State<VirtualKeyboard> createState() => _VirtualKeyboardState();
}

class _VirtualKeyboardState extends State<VirtualKeyboard> {
  bool _isUpperCase = false;
  bool _showNumbers = false;

  static const _row1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  static const _row2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  static const _row3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];
  static const _numRow1 = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const _numRow2 = ['@', '#', '\$', '%', '&', '*', '-', '_'];
  static const _numRow3 = ['.', ',', '?', '!', "'", '/'];

  void _insertChar(String char) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    int start = selection.start < 0 ? text.length : selection.start;
    int end = selection.end < 0 ? text.length : selection.end;

    final newText = text.replaceRange(start, end, char);
    final newPosition = start + char.length;

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newPosition),
    );
  }

  void _typeLetter(String letter) {
    _insertChar(_isUpperCase ? letter.toUpperCase() : letter);
  }

  void _backspace() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (text.isEmpty) return;
    int start = selection.start < 0 ? text.length : selection.start;
    if (start == 0) return;
    final newText = text.replaceRange(start - 1, start, '');
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start - 1),
    );
  }

  Widget _buildKey(
    String label, {
    VoidCallback? onTap,
    int flex = 1,
    Widget? child,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.all(3),
        child: Material(
          color: AppColors.fieldFill,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap ?? () => _typeLetter(label),
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.fieldBorder),
              ),
              child:
                  child ??
                  Text(
                    _isUpperCase ? label.toUpperCase() : label,
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 16,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row1 = _showNumbers ? _numRow1 : _row1;
    final row2 = _showNumbers ? _numRow2 : _row2;
    final row3 = _showNumbers ? _numRow3 : _row3;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        border: Border(top: BorderSide(color: AppColors.fieldBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: row1.map((c) => _buildKey(c)).toList()),
            SizedBox(height: 2),
            Row(
              children: [
                Spacer(),
                ...row2.map((c) => _buildKey(c)),
                Spacer(),
              ],
            ),
            SizedBox(height: 2),
            Row(
              children: [
                if (!_showNumbers)
                  _buildKey(
                    'shift',
                    flex: 2,
                    onTap: () => setState(() => _isUpperCase = !_isUpperCase),
                    child: Icon(
                      Icons.arrow_upward,
                      color: _isUpperCase ? AppColors.accent : Colors.grey,
                      size: 18,
                    ),
                  ),
                ...row3.map((c) => _buildKey(c)),
                _buildKey(
                  'back',
                  flex: _showNumbers ? 1 : 2,
                  onTap: _backspace,
                  child: Icon(
                    Icons.backspace_outlined,
                    color: Colors.grey,
                    size: 18,
                  ),
                ),
              ],
            ),
            SizedBox(height: 2),
            Row(
              children: [
                _buildKey(
                  '123',
                  flex: 2,
                  onTap: () => setState(() => _showNumbers = !_showNumbers),
                  child: Text(
                    _showNumbers ? 'ABC' : '123',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                _buildKey(
                  'space',
                  flex: 5,
                  onTap: () => _insertChar(' '),
                  child: Text(
                    'space',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                _buildKey(
                  'done',
                  flex: 2,
                  onTap: widget.onDone,
                  child: Text(
                    'Done',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
