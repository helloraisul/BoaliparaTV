import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'fullscreen_stub.dart' if (dart.library.html) 'fullscreen_web.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../providers/channel_providers.dart';
import '../theme/app_theme.dart';

class LivePlayer extends ConsumerStatefulWidget {
  const LivePlayer({super.key});

  @override
  ConsumerState<LivePlayer> createState() => _LivePlayerState();
}

class _LivePlayerState extends ConsumerState<LivePlayer> with SingleTickerProviderStateMixin {
  final FocusNode _playPauseFocus = FocusNode();

  late AnimationController _wmController;
  late Animation<double> _wmPosition;
  Timer? _wmTimer;
  bool _wmVisible = false;

  void _startWatermarkTimer() {
    _wmTimer?.cancel();
    _wmTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      setState(() => _wmVisible = true);
      _wmController.forward(from: 0.0);
    });
  }

  void _onWmComplete() {
    if (!mounted) return;
    setState(() => _wmVisible = false);
    _startWatermarkTimer();
  }

  @override
  void initState() {
    super.initState();
    ref.read(channelPlayerSyncProvider);
    ref.read(autoSelectChannelProvider); // add this
    _wmController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _wmPosition = Tween<double>(begin: 1.2, end: -1.4).animate(
      CurvedAnimation(parent: _wmController, curve: Curves.linear),
    );
    _wmController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _onWmComplete();
    });
    _startWatermarkTimer();
// // ✅ listenManual must be called synchronously in initState, not inside microtask
//     ref.listenManual(selectedChannelProvider, (previous, next) {
//       if (next != null && previous?.id != next.id) {
//         ref.read(playerControllerProvider.notifier).initialize(next.streamUrl);
//       }
//     });
//     Future.microtask(() {
//       final channel = ref.read(selectedChannelProvider);
//       if (channel != null) {
//         ref.read(playerControllerProvider.notifier).initialize(channel.streamUrl);
//       }
//     });
  }

  @override
  void didUpdateWidget(LivePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _playPauseFocus.dispose();
    _wmController.dispose();
    _wmTimer?.cancel();
    super.dispose();
  }

  void _requestNativeFullscreen() {
    requestNativeFullscreen();
  }

  // void _exitNativeFullscreen() {
  //   exitNativeFullscreen();
  // }

  Future<void> _enterFullscreen(BuildContext context) async {
    if (kIsWeb) {
      _requestNativeFullscreen();
      return;
    }

    // Mobile: route-based fullscreen
    final notifier = ref.read(playerControllerProvider.notifier);
    final wasPlaying = notifier.videoController?.value.isPlaying ?? false;
    notifier.setFullscreen(true);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _FullscreenPlayerScreen(),
        fullscreenDialog: true,
      ),
    );

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    notifier.setFullscreen(false);

    final controller = notifier.videoController;
    if (wasPlaying && controller != null && controller.value.isInitialized && !controller.value.isPlaying) {
      controller.play().catchError((e) {
        debugPrint('[RaisulTV] resume play() error: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final controllerNotifier = ref.read(playerControllerProvider.notifier);
    final channel = ref.watch(selectedChannelProvider);
    final videoController = controllerNotifier.videoController;
    ref.watch(channelPlayerSyncProvider);
    ref.watch(autoSelectChannelProvider); // keeps auto-select active
    if (channel == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
                  const SizedBox(height: 16),
                  Text('Loading channels…', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),

            // VideoPlayer always stays here — never moved
            // VideoPlayer always stays here — never moved
            if (state.status == PlayerStatus.playing && videoController != null && videoController.value.isInitialized)
              Builder(builder: (_) {
                debugPrint('[RaisulTV] 🎬 VideoPlayer widget built: isPlaying=${videoController.value.isPlaying}');
                return VideoPlayer(videoController);
              }),

            // Loading
            if (state.status == PlayerStatus.loading)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
                    SizedBox(height: 16),
                    Text('Connecting to stream…', style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),

            // Error
            if (state.status == PlayerStatus.error)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.signal_wifi_off_rounded, size: 48, color: AppTheme.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      state.errorMessage ?? 'Stream unavailable',
                      style: TextStyle(color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => controllerNotifier.retry(channel.streamUrl),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('Retry', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),

            // Tap to toggle controls
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: controllerNotifier.toggleControls,
              child: const SizedBox.expand(),
            ),

            // Watermark
            if (_wmVisible)
              AnimatedBuilder(
                animation: _wmPosition,
                builder: (context, child) => Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment(_wmPosition.value, -0.3),
                    child: child,
                  ),
                ),
                child: Opacity(
                  opacity: 0.4,
                  child: Text(
                    'Raisul',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 4,
                          offset: const Offset(1, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Unmute banner
            if (kIsWeb && state.isMuted && state.status == PlayerStatus.playing)
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: controllerNotifier.toggleMute,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volume_off_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('Tap to unmute', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Top bar
            if (state.showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: AppTheme.liveBadgeGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: Colors.white),
                            SizedBox(width: 4),
                            Text('LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  letterSpacing: 1,
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          channel.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom controls
            if (state.showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      _ControlButton(
                        focusNode: _playPauseFocus,
                        icon: (videoController?.value.isPlaying ?? false)
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onTap: controllerNotifier.togglePlayPause,
                        autofocus: true,
                      ),
                      const SizedBox(width: 8),
                      _ControlButton(
                        icon: state.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        onTap: controllerNotifier.toggleMute,
                      ),
                      const Spacer(),
                      Icon(Icons.hd_rounded, color: AppTheme.textSecondary, size: 22),
                      const SizedBox(width: 12),
                      _ControlButton(
                        icon: Icons.fullscreen_rounded,
                        onTap: () => _enterFullscreen(context),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _focused ? AppTheme.primary.withOpacity(0.25) : Colors.white.withOpacity(0.08),
            border: _focused ? Border.all(color: AppTheme.primary, width: 2) : null,
          ),
          child: Icon(widget.icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

/// Fullscreen route — mobile only.
class _FullscreenPlayerScreen extends ConsumerStatefulWidget {
  const _FullscreenPlayerScreen();

  @override
  ConsumerState<_FullscreenPlayerScreen> createState() => _FullscreenPlayerScreenState();
}

class _FullscreenPlayerScreenState extends ConsumerState<_FullscreenPlayerScreen> with SingleTickerProviderStateMixin {
  late AnimationController _wmController;
  late Animation<double> _wmPosition;
  Timer? _wmTimer;
  bool _wmVisible = false;

  @override
  void initState() {
    super.initState();
    _wmController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _wmPosition = Tween<double>(begin: 1.2, end: -1.4).animate(
      CurvedAnimation(parent: _wmController, curve: Curves.linear),
    );
    _wmController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (!mounted) return;
        setState(() => _wmVisible = false);
        _wmTimer?.cancel();
        _wmTimer = Timer(const Duration(seconds: 15), () {
          if (!mounted) return;
          setState(() => _wmVisible = true);
          _wmController.forward(from: 0.0);
        });
      }
    });
    _wmTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      setState(() => _wmVisible = true);
      _wmController.forward(from: 0.0);
    });
  }

  @override
  void dispose() {
    _wmController.dispose();
    _wmTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final notifier = ref.read(playerControllerProvider.notifier);
    final channel = ref.watch(selectedChannelProvider);
    final videoController = notifier.videoController;

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (didPop) {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: notifier.toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (state.status == PlayerStatus.playing &&
                  videoController != null &&
                  videoController.value.isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: videoController.value.aspectRatio,
                    child: VideoPlayer(videoController),
                  ),
                )
              else if (state.status == PlayerStatus.loading)
                Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3))
              else if (state.status == PlayerStatus.error)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.signal_wifi_off_rounded, size: 48, color: AppTheme.textSecondary),
                      const SizedBox(height: 12),
                      Text(state.errorMessage ?? 'Stream unavailable', style: TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 16),
                      if (channel != null)
                        ElevatedButton.icon(
                          onPressed: () => notifier.retry(channel.streamUrl),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          label: const Text('Retry', style: TextStyle(color: Colors.white)),
                        ),
                    ],
                  ),
                ),
              // Watermark
              if (_wmVisible)
                AnimatedBuilder(
                  animation: _wmPosition,
                  builder: (context, child) => Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment(_wmPosition.value, -0.3),
                      child: child,
                    ),
                  ),
                  child: Opacity(
                    opacity: 0.4,
                    child: Text(
                      'Raisul',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.6),
                            blurRadius: 4,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (state.showControls && channel != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          _ControlButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: AppTheme.liveBadgeGradient,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, size: 8, color: Colors.white),
                                SizedBox(width: 4),
                                Text('LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      letterSpacing: 1,
                                    )),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              channel.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (state.showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          _ControlButton(
                            icon: (videoController?.value.isPlaying ?? false)
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onTap: notifier.togglePlayPause,
                            autofocus: true,
                          ),
                          const SizedBox(width: 8),
                          _ControlButton(
                            icon: state.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            onTap: notifier.toggleMute,
                          ),
                          const Spacer(),
                          _ControlButton(
                            icon: Icons.fullscreen_exit_rounded,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
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
