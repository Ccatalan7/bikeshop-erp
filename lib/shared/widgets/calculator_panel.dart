import 'package:flutter/material.dart';

/// A fully functional calculator widget designed to live inside
/// the right-side toolbar panel.
class CalculatorPanel extends StatefulWidget {
  const CalculatorPanel({super.key});

  @override
  State<CalculatorPanel> createState() => _CalculatorPanelState();
}

class _CalculatorPanelState extends State<CalculatorPanel> {
  String _display = '0';
  String _expression = '';
  double? _firstOperand;
  String? _operator;
  bool _shouldResetDisplay = false;

  void _onDigit(String digit) {
    setState(() {
      if (_shouldResetDisplay) {
        _display = digit;
        _shouldResetDisplay = false;
      } else {
        _display = _display == '0' ? digit : _display + digit;
      }
    });
  }

  void _onDecimal() {
    setState(() {
      if (_shouldResetDisplay) {
        _display = '0.';
        _shouldResetDisplay = false;
      } else if (!_display.contains('.')) {
        _display += '.';
      }
    });
  }

  void _onOperator(String op) {
    setState(() {
      final current = double.tryParse(_display) ?? 0;
      if (_firstOperand != null && _operator != null && !_shouldResetDisplay) {
        _firstOperand = _calculate(_firstOperand!, current, _operator!);
        _display = _formatNumber(_firstOperand!);
      } else {
        _firstOperand = current;
      }
      _operator = op;
      _expression = '${_formatNumber(_firstOperand!)} $op';
      _shouldResetDisplay = true;
    });
  }

  void _onEquals() {
    if (_firstOperand == null || _operator == null) return;
    setState(() {
      final second = double.tryParse(_display) ?? 0;
      final result = _calculate(_firstOperand!, second, _operator!);
      _expression = '';
      _display = _formatNumber(result);
      _firstOperand = null;
      _operator = null;
      _shouldResetDisplay = true;
    });
  }

  void _onClear() {
    setState(() {
      _display = '0';
      _expression = '';
      _firstOperand = null;
      _operator = null;
      _shouldResetDisplay = false;
    });
  }

  void _onToggleSign() {
    setState(() {
      final value = double.tryParse(_display) ?? 0;
      _display = _formatNumber(-value);
    });
  }

  void _onPercent() {
    setState(() {
      final value = double.tryParse(_display) ?? 0;
      _display = _formatNumber(value / 100);
    });
  }

  void _onBackspace() {
    setState(() {
      if (_display.length > 1) {
        _display = _display.substring(0, _display.length - 1);
      } else {
        _display = '0';
      }
    });
  }

  double _calculate(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b != 0 ? a / b : 0;
      default:
        return b;
    }
  }

  String _formatNumber(double value) {
    if (value == value.toInt().toDouble()) {
      return value.toInt().toString();
    }
    // Limit to 10 decimal places and strip trailing zeros
    return value.toStringAsFixed(10).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF252525) : const Color(0xFFF8F9FA);
    final displayBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final buttonBg = isDark ? const Color(0xFF2E2E2E) : Colors.white;
    final operatorBg = isDark ? const Color(0xFF1976D2) : const Color(0xFF1976D2);
    final functionBg = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);

    return Container(
      color: bgColor,
      child: Column(
        children: [
          // Display area
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: displayBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_expression.isNotEmpty)
                  Text(
                    _expression,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _display,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),

          // Button grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  // Row 1: C, ±, %, ÷
                  _buildRow([
                    _CalcButton('C', onTap: _onClear, bgColor: functionBg, textColor: isDark ? Colors.white70 : Colors.black87),
                    _CalcButton('±', onTap: _onToggleSign, bgColor: functionBg, textColor: isDark ? Colors.white70 : Colors.black87),
                    _CalcButton('%', onTap: _onPercent, bgColor: functionBg, textColor: isDark ? Colors.white70 : Colors.black87),
                    _CalcButton('÷', onTap: () => _onOperator('÷'), bgColor: operatorBg, textColor: Colors.white),
                  ]),
                  // Row 2: 7, 8, 9, ×
                  _buildRow([
                    _CalcButton('7', onTap: () => _onDigit('7'), bgColor: buttonBg),
                    _CalcButton('8', onTap: () => _onDigit('8'), bgColor: buttonBg),
                    _CalcButton('9', onTap: () => _onDigit('9'), bgColor: buttonBg),
                    _CalcButton('×', onTap: () => _onOperator('×'), bgColor: operatorBg, textColor: Colors.white),
                  ]),
                  // Row 3: 4, 5, 6, −
                  _buildRow([
                    _CalcButton('4', onTap: () => _onDigit('4'), bgColor: buttonBg),
                    _CalcButton('5', onTap: () => _onDigit('5'), bgColor: buttonBg),
                    _CalcButton('6', onTap: () => _onDigit('6'), bgColor: buttonBg),
                    _CalcButton('−', onTap: () => _onOperator('−'), bgColor: operatorBg, textColor: Colors.white),
                  ]),
                  // Row 4: 1, 2, 3, +
                  _buildRow([
                    _CalcButton('1', onTap: () => _onDigit('1'), bgColor: buttonBg),
                    _CalcButton('2', onTap: () => _onDigit('2'), bgColor: buttonBg),
                    _CalcButton('3', onTap: () => _onDigit('3'), bgColor: buttonBg),
                    _CalcButton('+', onTap: () => _onOperator('+'), bgColor: operatorBg, textColor: Colors.white),
                  ]),
                  // Row 5: ⌫, 0, ., =
                  _buildRow([
                    _CalcButton('⌫', onTap: _onBackspace, bgColor: functionBg, textColor: isDark ? Colors.white70 : Colors.black87, fontSize: 18),
                    _CalcButton('0', onTap: () => _onDigit('0'), bgColor: buttonBg),
                    _CalcButton('.', onTap: _onDecimal, bgColor: buttonBg),
                    _CalcButton('=', onTap: _onEquals, bgColor: const Color(0xFF388E3C), textColor: Colors.white),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(List<_CalcButton> buttons) {
    return Expanded(
      child: Row(
        children: buttons
            .map((btn) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _CalculatorButton(
                      label: btn.label,
                      onTap: btn.onTap,
                      bgColor: btn.bgColor,
                      textColor: btn.textColor,
                      fontSize: btn.fontSize,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _CalcButton {
  final String label;
  final VoidCallback onTap;
  final Color bgColor;
  final Color? textColor;
  final double? fontSize;

  _CalcButton(
    this.label, {
    required this.onTap,
    required this.bgColor,
    this.textColor,
    this.fontSize,
  });
}

class _CalculatorButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color bgColor;
  final Color? textColor;
  final double? fontSize;

  const _CalculatorButton({
    required this.label,
    required this.onTap,
    required this.bgColor,
    this.textColor,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize ?? 20,
              fontWeight: FontWeight.w500,
              color: textColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
