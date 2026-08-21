import 'package:flutter/material.dart';
import '../theme/uranio_theme.dart';

/// Tarjeta resumen reutilizable para el dashboard de Mercurio.
/// Al pulsarla, se abre la vista completa de esa sección con una
/// transición de fade + scale (sensación de "expansión", estilo BeReal).
class SectionCard extends StatelessWidget {
  final String heroTag;
  final Widget child;
  final WidgetBuilder fullViewBuilder;
  final bool glow;

  const SectionCard({
    super.key,
    required this.heroTag,
    required this.child,
    required this.fullViewBuilder,
    this.glow = false,
  });

  void _open(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondaryAnimation) => fullViewBuilder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: UranioTheme.cardDecoration(glow: glow),
          child: child,
        ),
      ),
    );
  }
}
