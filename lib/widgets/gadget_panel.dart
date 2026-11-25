import 'package:flutter/material.dart';

import '../models/kitt_state.dart';

/// Painel retrô anos 80 de gadgets clássicos e telemetria do KITT com:
/// - Barra segmentada de LEDs para RPM, velocímetro real em km/h (GPS) e força G
/// - Botão 'TELEMETRIA / SENSORES' para ativar/silenciar reações automáticas do KITT
/// - Grid de 3 botões táteis retroiluminados com LEDs de status (Oil Slick, Smoke Screen, Turbo Boost)
class GadgetPanel extends StatelessWidget {
  const GadgetPanel({
    super.key,
    required this.activeGadget,
    required this.rpmNormalized,
    required this.rpmValue,
    required this.speedKmh,
    this.isGpsLive = false,
    this.currentGForce = 0.0,
    this.telemetryEnabled = true,
    this.onToggleTelemetry,
    required this.onTriggerGadget,
  });

  final GadgetType? activeGadget;
  final double rpmNormalized;
  final int rpmValue;
  final int speedKmh;
  final bool isGpsLive;
  final double currentGForce;
  final bool telemetryEnabled;
  final VoidCallback? onToggleTelemetry;
  final void Function(GadgetType gadget) onTriggerGadget;

  @override
  Widget build(BuildContext context) {
    final bool isBoosting = activeGadget == GadgetType.turboBoost;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C11),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isBoosting
              ? const Color(0xFFFF2424)
              : const Color(0xFF282834),
          width: isBoosting ? 1.8 : 1.2,
        ),
        boxShadow: isBoosting
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x55FF2424),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildTelemetryBar(isBoosting),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _RetroGadgetTile(
                  gadget: GadgetType.oilSlick,
                  accentColor: const Color(0xFFFF9100),
                  icon: Icons.water_drop,
                  isActive: activeGadget == GadgetType.oilSlick,
                  onTap: () => onTriggerGadget(GadgetType.oilSlick),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RetroGadgetTile(
                  gadget: GadgetType.smokeScreen,
                  accentColor: const Color(0xFF80DEEA),
                  icon: Icons.cloud,
                  isActive: activeGadget == GadgetType.smokeScreen,
                  onTap: () => onTriggerGadget(GadgetType.smokeScreen),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RetroGadgetTile(
                  gadget: GadgetType.turboBoost,
                  accentColor: const Color(0xFFFF2424),
                  icon: Icons.bolt,
                  isActive: activeGadget == GadgetType.turboBoost,
                  onTap: () => onTriggerGadget(GadgetType.turboBoost),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryBar(bool isBoosting) {
    const int segments = 18;
    final int litSegments = (rpmNormalized.clamp(0.0, 1.0) * segments).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'RPM ${rpmValue.toString().padLeft(4, '0')} • ${currentGForce.toStringAsFixed(2)}G',
              style: TextStyle(
                fontFamily: 'monospace',
                color: isBoosting
                    ? const Color(0xFFFF5252)
                    : const Color(0xFFFFD54F),
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
                letterSpacing: 0.9,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (isGpsLive)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x2800E676),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF00E676)),
                    ),
                    child: const Text(
                      'GPS',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF69F0AE),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                Text(
                  '${speedKmh.toString().padLeft(3, '0')} KM/H',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: isBoosting
                        ? const Color(0xFFFFEA00)
                        : const Color(0xFF69F0AE),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.3,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: List<Widget>.generate(segments, (int i) {
                  final bool lit = i < litSegments;
                  final Color segColor = i < 10
                      ? const Color(0xFF00E676)
                      : i < 14
                          ? const Color(0xFFFFC400)
                          : const Color(0xFFFF1744);
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 1.1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1.5),
                        color: lit ? segColor : segColor.withValues(alpha: 0.14),
                        boxShadow: lit
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: segColor.withValues(alpha: 0.6),
                                  blurRadius: 5,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (onToggleTelemetry != null) ...<Widget>[
              const SizedBox(width: 8),
              InkWell(
                onTap: onToggleTelemetry,
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: telemetryEnabled
                        ? const Color(0x2800E676)
                        : const Color(0xFF1A1A22),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: telemetryEnabled
                          ? const Color(0xFF00E676)
                          : const Color(0xFF454556),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        telemetryEnabled
                            ? Icons.sensors
                            : Icons.sensors_off,
                        size: 12,
                        color: telemetryEnabled
                            ? const Color(0xFF69F0AE)
                            : const Color(0xFF8A8A9E),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'TELEMETRIA / SENSORES',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: telemetryEnabled
                              ? const Color(0xFF69F0AE)
                              : const Color(0xFF8A8A9E),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RetroGadgetTile extends StatelessWidget {
  const _RetroGadgetTile({
    required this.gadget,
    required this.accentColor,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final GadgetType gadget;
  final Color accentColor;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          decoration: BoxDecoration(
            color: isActive
                ? accentColor.withValues(alpha: 0.26)
                : const Color(0xFF14141C),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isActive
                  ? accentColor
                  : accentColor.withValues(alpha: 0.42),
              width: isActive ? 1.8 : 1.1,
            ),
            boxShadow: isActive
                ? <BoxShadow>[
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Icon(
                    icon,
                    size: 14,
                    color: isActive ? accentColor : accentColor.withValues(alpha: 0.75),
                  ),
                  // LED indicador retrô
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? accentColor
                          : accentColor.withValues(alpha: 0.18),
                      boxShadow: isActive
                          ? <BoxShadow>[
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.9),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                gadget.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? Colors.white : accentColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0.9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
