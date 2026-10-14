import 'package:flutter/material.dart';
import 'package:diu_ride/features/ai_assistant/presentation/widgets/diu_ai_chat_sheet.dart';

/// Interactive, glowing floating AI Chatbot badge with subtle pulse animation
class MiniFloatingAiBadge extends StatefulWidget {
  final bool showLabel;

  const MiniFloatingAiBadge({
    super.key,
    this.showLabel = true,
  });

  @override
  State<MiniFloatingAiBadge> createState() => _MiniFloatingAiBadgeState();
}

class _MiniFloatingAiBadgeState extends State<MiniFloatingAiBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: () => DiuAiChatSheet.show(context),
        child: Container(
          padding: widget.showLabel
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
              : const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFE65100), // Vibrant Sunset Orange
                Color(0xFFF57C00), // Amber
                Color(0xFFFF9800), // Warm Golden Peach
              ],
            ),
            borderRadius: BorderRadius.circular(widget.showLabel ? 28 : 28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE65100).withOpacity(0.45),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: -2,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing AI Badge Icon
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.auto_awesome,
                        size: 19,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ),
                  // Green online dot
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.showLabel) ...[
                const SizedBox(width: 10),
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'DIU AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.chat_bubble_outline, size: 12, color: Colors.white70),
                      ],
                    ),
                    Text(
                      'রাইড সহকারী',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
