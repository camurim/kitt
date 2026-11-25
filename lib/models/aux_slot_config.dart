import 'package:flutter/material.dart';

/// Ícones estilo HUD disponíveis para os botões auxiliares configuráveis.
enum AuxHudIcon {
  navigation('navigation', 'NAVEGAÇÃO', Icons.navigation, Color(0xFF40C4FF)),
  audio('audio', 'ÁUDIO', Icons.graphic_eq, Color(0xFF69F0AE)),
  comms('comms', 'COMMS', Icons.forum, Color(0xFFFFD54F)),
  radar('radar', 'RADAR', Icons.radar, Color(0xFFFF5252)),
  camera('camera', 'CÂMERA', Icons.videocam, Color(0xFFE040FB)),
  weather('weather', 'CLIMA', Icons.cloud_queue, Color(0xFF80DEEA)),
  terminal('terminal', 'SISTEMA', Icons.terminal, Color(0xFFFF9100)),
  bolt('bolt', 'ATALHO', Icons.bolt, Color(0xFFFFEB3B));

  const AuxHudIcon(this.id, this.defaultLabel, this.iconData, this.accentColor);

  final String id;
  final String defaultLabel;
  final IconData iconData;
  final Color accentColor;

  static AuxHudIcon fromId(String? id) {
    for (final AuxHudIcon item in AuxHudIcon.values) {
      if (item.id == id) return item;
    }
    return AuxHudIcon.bolt;
  }
}

/// Configuração persistida de um dos 4 slots de botões auxiliares do painel KITT.
class AuxSlotConfig {
  const AuxSlotConfig({
    required this.slotNumber,
    this.label = '',
    this.packageName = '',
    this.appName = '',
    this.iconId = 'bolt',
  });

  /// Número do slot (1 a 4).
  final int slotNumber;
  final String label;
  final String packageName;
  final String appName;
  final String iconId;

  bool get isConfigured => packageName.trim().isNotEmpty;

  String get displayLabel =>
      label.trim().isNotEmpty ? label.trim().toUpperCase() : 'AUX $slotNumber';

  AuxHudIcon get hudIcon => AuxHudIcon.fromId(iconId);

  AuxSlotConfig copyWith({
    String? label,
    String? packageName,
    String? appName,
    String? iconId,
  }) {
    return AuxSlotConfig(
      slotNumber: slotNumber,
      label: label ?? this.label,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      iconId: iconId ?? this.iconId,
    );
  }

  AuxSlotConfig cleared() => AuxSlotConfig(slotNumber: slotNumber);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'slotNumber': slotNumber,
        'label': label,
        'packageName': packageName,
        'appName': appName,
        'iconId': iconId,
      };

  factory AuxSlotConfig.fromJson(Map<String, dynamic> json) {
    return AuxSlotConfig(
      slotNumber: (json['slotNumber'] as num?)?.toInt() ?? 1,
      label: json['label'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
      appName: json['appName'] as String? ?? '',
      iconId: json['iconId'] as String? ?? 'bolt',
    );
  }

  static List<AuxSlotConfig> defaultSlots() => List<AuxSlotConfig>.generate(
        4,
        (int i) => AuxSlotConfig(slotNumber: i + 1),
      );
}
