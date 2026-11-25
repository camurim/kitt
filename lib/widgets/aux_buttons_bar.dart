import 'package:flutter/material.dart';

import '../models/aux_slot_config.dart';

/// Barra de 4 Botões Auxiliares Configuráveis estilo HUD no painel do KITT.
///
/// - Toque curto em botão configurado: abre o app vinculado.
/// - Toque curto em botão vazio ou long-press em qualquer botão: abre a tela de configuração.
class AuxButtonsBar extends StatelessWidget {
  const AuxButtonsBar({
    super.key,
    required this.slots,
    required this.onTapSlot,
    required this.onLongPressSlot,
  });

  final List<AuxSlotConfig> slots;
  final void Function(AuxSlotConfig slot) onTapSlot;
  final void Function(AuxSlotConfig slot) onLongPressSlot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF252532), width: 1.1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'AUXILIARES HUD',
                style: TextStyle(
                  color: Color(0xFF8C8CA0),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              Text(
                'SEGURE P/ CONFIGURAR',
                style: TextStyle(
                  color: Color(0xFF646478),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: List<Widget>.generate(slots.length, (int i) {
              final AuxSlotConfig slot = slots[i];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  child: _AuxSlotTile(
                    slot: slot,
                    onTap: () => onTapSlot(slot),
                    onLongPress: () => onLongPressSlot(slot),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _AuxSlotTile extends StatelessWidget {
  const _AuxSlotTile({
    required this.slot,
    required this.onTap,
    required this.onLongPress,
  });

  final AuxSlotConfig slot;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bool configured = slot.isConfigured;
    final AuxHudIcon hudIcon = slot.hudIcon;
    final Color accent =
        configured ? hudIcon.accentColor : const Color(0xFF5C5C70);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(7),
        splashColor: accent.withValues(alpha: 0.35),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          decoration: BoxDecoration(
            color: configured
                ? accent.withValues(alpha: 0.14)
                : const Color(0xFF12121A),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: configured
                  ? accent.withValues(alpha: 0.72)
                  : const Color(0xFF282836),
              width: configured ? 1.3 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '0${slot.slotNumber}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: accent.withValues(alpha: 0.8),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: configured
                          ? accent
                          : const Color(0xFF333344),
                      boxShadow: configured
                          ? <BoxShadow>[
                              BoxShadow(
                                color: accent.withValues(alpha: 0.85),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Icon(
                configured ? hudIcon.iconData : Icons.add,
                color: accent,
                size: 16,
              ),
              const SizedBox(height: 3),
              Text(
                slot.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: configured ? Colors.white : const Color(0xFF77778B),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
