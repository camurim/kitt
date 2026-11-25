import 'package:flutter/material.dart';

/// Botão retroiluminado estilo painel do KITT (Knight Rider 1982).
class SideButton extends StatelessWidget {
  const SideButton({
    super.key,
    required this.label,
    required this.accentColor,
    required this.onPressed,
    this.isActive = false,
    this.compact = false,
  });

  final String label;
  final Color accentColor;
  final VoidCallback onPressed;
  final bool isActive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color bgColor = isActive
        ? accentColor.withValues(alpha: 0.92)
        : accentColor.withValues(alpha: 0.16);
    final Color textColor = isActive ? Colors.black : accentColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: compact ? 10 : 14,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                  ? accentColor
                  : accentColor.withValues(alpha: 0.55),
              width: isActive ? 2 : 1.2,
            ),
            boxShadow: isActive
                ? <BoxShadow>[
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.55),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 11 : 12,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
