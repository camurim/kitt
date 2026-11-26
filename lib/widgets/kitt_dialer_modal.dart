import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Abre o modal estilizado com teclado numérico retrô do KITT (Commlink Dialer).
Future<void> showKittDialerModal({
  required BuildContext context,
  required Future<void> Function(String phoneNumber, bool directCall) onDial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0A0A0F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      side: BorderSide(color: Color(0xFF3A1418), width: 1.5),
    ),
    builder: (BuildContext ctx) {
      return KittDialerSheet(
        onDial: (String number, bool directCall) async {
          Navigator.of(ctx).pop();
          await onDial(number, directCall);
        },
      );
    },
  );
}

/// Conteúdo do teclado numérico retrô estilo painel do KITT.
class KittDialerSheet extends StatefulWidget {
  const KittDialerSheet({
    super.key,
    required this.onDial,
  });

  final Future<void> Function(String phoneNumber, bool directCall) onDial;

  @override
  State<KittDialerSheet> createState() => _KittDialerSheetState();
}

class _KittDialerSheetState extends State<KittDialerSheet> {
  String _number = '';

  void _append(String char) {
    HapticFeedback.lightImpact();
    if (_number.length >= 20) return;
    setState(() => _number += char);
  }

  void _backspace() {
    if (_number.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _number = _number.substring(0, _number.length - 1));
  }

  void _clear() {
    if (_number.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _number = '');
  }

  @override
  Widget build(BuildContext context) {
    const List<List<String>> rows = <List<String>>[
      <String>['1', '2', '3'],
      <String>['4', '5', '6'],
      <String>['7', '8', '9'],
      <String>['*', '0', '#'],
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Cabeçalho Commlink
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF2424),
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: Color(0xCCFF2424), blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'K.i.t.Turbo • COMMLINK DISCADOR',
                    style: TextStyle(
                      color: Color(0xFFFF5252),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.8,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Display LED digital do número
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF050508),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3E181C), width: 1.5),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _number.isEmpty ? 'DIGITE O NÚMERO...' : _number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: _number.isEmpty
                            ? const Color(0xFF555566)
                            : const Color(0xFFFFD54F),
                        fontSize: _number.isEmpty ? 15 : 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onLongPress: _clear,
                    child: IconButton(
                      tooltip: 'Apagar (segure para limpar)',
                      onPressed: _number.isEmpty ? null : _backspace,
                      icon: const Icon(
                        Icons.backspace_outlined,
                        color: Color(0xFFFF8A80),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Teclado numérico 3x4 retrô
            for (final List<String> row in rows) ...<Widget>[
              Row(
                children: row.map((String key) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _DialKey(
                        label: key,
                        subLabel: key == '0' ? '+' : null,
                        onTap: () => _append(key),
                        onLongPress: key == '0' ? () => _append('+') : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),

            // Botões de ação: Discador (tel:) vs Ligação Direta (CALL_PHONE)
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => widget.onDial(_number, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFD54F),
                      side: const BorderSide(color: Color(0xFFFFD54F)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.dialpad, size: 18),
                    label: const Text(
                      'DISCADOR',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _number.isEmpty
                        ? null
                        : () => widget.onDial(_number, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF1744),
                      disabledBackgroundColor: const Color(0xFF2B181C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text(
                      'LIGAR DIRETO',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
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

class _DialKey extends StatelessWidget {
  const _DialKey({
    required this.label,
    required this.onTap,
    this.subLabel,
    this.onLongPress,
  });

  final String label;
  final String? subLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF14141D),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        splashColor: const Color(0x55FF2424),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E2E3B)),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subLabel != null)
                Text(
                  subLabel!,
                  style: const TextStyle(
                    color: Color(0xFFFFD54F),
                    fontSize: 10,
                    height: 0.9,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
