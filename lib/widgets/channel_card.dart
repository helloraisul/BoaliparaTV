import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/channel_model.dart';
import '../providers/channel_providers.dart';
import '../theme/app_theme.dart';

/// A focusable channel tile — works with touch and TV remote D-pad.
class ChannelCard extends ConsumerStatefulWidget {
  final ChannelModel channel;
  final bool isActive;
  final bool autofocus;

  const ChannelCard({
    super.key,
    required this.channel,
    required this.isActive,
    this.autofocus = false,
  });

  @override
  ConsumerState<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends ConsumerState<ChannelCard> {
  bool _focused = false;

  void _select() {
    ref.read(selectedChannelProvider.notifier).state = widget.channel;
    ref.read(playerControllerProvider.notifier).retry(widget.channel.streamUrl);
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.isActive || _focused;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          _select();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _select,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: highlighted
                ? LinearGradient(
                    colors: [
                      AppTheme.primary.withOpacity(0.85),
                      AppTheme.primaryDark.withOpacity(0.85),
                    ],
                  )
                : AppTheme.cardGradient,
            border:
                _focused ? Border.all(color: Colors.white, width: 2) : Border.all(color: Colors.transparent, width: 2),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.12),
                ),
                child: Icon(
                  Icons.sports_cricket_rounded,
                  color: highlighted ? Colors.white : AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.channel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.channel.category,
                      style: TextStyle(
                        color: highlighted ? Colors.white.withOpacity(0.85) : AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'ON AIR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
