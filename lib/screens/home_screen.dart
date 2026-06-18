import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/channel_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/live_player.dart';
import '../widgets/channel_card.dart';

/// Main screen — adapts between a mobile (stacked) layout and a
/// TV / large-screen (sidebar) layout based on available width.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _dialogShowing = false;
  @override
  void initState() {
    super.initState();
  }

  void _showNoInternetDialog() {
    if (_dialogShowing) return;
    _dialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: AppTheme.primary),
              const SizedBox(width: 10),
              Text(
                'No Internet',
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Text(
            'Please check your internet connection and try again.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _dialogShowing = false;
                ref.invalidate(internetReachableProvider);
                ref.invalidate(channelListProvider);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    ).then((_) {
      _dialogShowing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Wait for ISP detection before showing channels (avoids flash of all-channels)
    final ispAsync = ref.watch(ispNameProvider);
    final ftpIspsAsync = ref.watch(ftpIspListProvider);
    final isWifi = ref.watch(isWifiProvider);
    final ispStillLoading = isWifi && (ispAsync.isLoading || ftpIspsAsync.isLoading);

    if (ispStillLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
                SizedBox(height: 16),
                Text(
                  'Detecting your network…',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final channelsAsync = ref.watch(channelListProvider);
    final selected = ref.watch(selectedChannelProvider);
    ref.watch(ftpAutoSelectProvider); // ✅ activates one-shot FTP auto-select
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700; // TV / large tablet / desktop breakpoint
    final sidebarWidth = (width * 0.25).clamp(280.0, 500.0);

    // Listen for internet reachability changes and show/dismiss popup
    ref.listen<AsyncValue<bool>>(internetReachableProvider, (previous, next) {
      next.whenData((reachable) {
        if (!reachable) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showNoInternetDialog();
          });
        } else if (_dialogShowing) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      });
    });

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: channelsAsync.when(
            // ✅ Data loaded successfully
            data: (channels) {
              if (channels.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.tv_off_rounded,
                        size: 56,
                        color: AppTheme.textSecondary.withOpacity(0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No channels available',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This channel list is coming soon',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Consumer(
                        builder: (context, ref, _) => ElevatedButton.icon(
                          onPressed: () {
                            ref.read(channelFilterProvider.notifier).state = ChannelFilter.ftp;
                            ref.invalidate(channelListProvider);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 12,
                            ),
                          ),
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          label: const Text(
                            'Back to FTP Channels',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return isWide
                  ? _TvLayout(channels: channels, selected: selected, sidebarWidth: sidebarWidth)
                  : _MobileLayout(channels: channels, selected: selected);
            },

            // ⏳ Still loading channels
            loading: () {
              return isWide
                  ? _TvLayout(channels: const [], selected: selected, sidebarWidth: sidebarWidth)
                  : _MobileLayout(channels: const [], selected: selected, isLoading: true);
            },

            // ❌ Error fetching channels
            error: (error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.signal_wifi_off_rounded,
                      size: 48,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load channels',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Retry by invalidating the provider
                        ref.invalidate(channelListProvider);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text(
                        'Retry',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// TV / large screen: persistent sidebar with player taking the main area.
class _TvLayout extends StatelessWidget {
  final List channels;
  final dynamic selected;
  final double sidebarWidth;

  const _TvLayout({required this.channels, required this.selected, required this.sidebarWidth});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Sidebar
        Container(
          width: sidebarWidth,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.5),
            border: Border(
              right: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              const _BrandHeader(compact: true),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Consumer(
                  builder: (context, ref, _) {
                    final ispAsync = ref.watch(ispNameProvider);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ispAsync.when(
                          data: (isp) => Text(
                            isp.toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          loading: () => const Text(
                            'DETECTING ISP…',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              letterSpacing: 1.5,
                            ),
                          ),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'YOUR FTP CHANNELS',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Filter chips — same logic as mobile
              Consumer(
                builder: (context, ref, _) {
                  final filter = ref.watch(channelFilterProvider);
                  final showFtp = ref.watch(showFtpButtonProvider);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        if (showFtp) ...[
                          _FilterChip(
                            label: 'FTP',
                            isSelected: filter == ChannelFilter.ftp,
                            onTap: () {
                              if (ref.read(channelFilterProvider) == ChannelFilter.ftp) return;
                              ref.read(channelFilterProvider.notifier).state = ChannelFilter.ftp;
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        _FilterChip(
                          label: 'ALL',
                          isSelected: filter == ChannelFilter.all || !showFtp,
                          onTap: () {
                            if (ref.read(channelFilterProvider) == ChannelFilter.all) return;
                            ref.read(channelFilterProvider.notifier).state = ChannelFilter.all;
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: channels.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
                      )
                    : ListView.builder(
                        itemCount: channels.length,
                        itemBuilder: (context, i) => ChannelCard(
                          channel: channels[i],
                          isActive: selected != null && channels[i].id == selected.id,
                        ),
                      ),
              ),
              // const _FooterCredit(),
            ],
          ),
        ),
        // Main player area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LivePlayer(),
                  const SizedBox(height: 16),
                  if (selected != null) _NowPlayingInfo(channel: selected) else const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Mobile / tablet: stacked player on top, channel list below.
class _MobileLayout extends StatelessWidget {
  final List channels;
  final dynamic selected;
  final bool isLoading;

  const _MobileLayout({required this.channels, required this.selected, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: const _BrandHeader(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: const LivePlayer(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Consumer(
              builder: (context, ref, _) {
                final ispAsync = ref.watch(ispNameProvider);
                final isWifi = ref.watch(isWifiProvider);
                return ispAsync.when(
                  data: (isp) {
                    final showFtp = ref.watch(showFtpButtonProvider);
                    String? hintText;
                    if (!isWifi) {
                      hintText = 'Connect to WiFi for FTP channels (no buffering)';
                    } else if (!showFtp) {
                      hintText = 'Your ISP is not in my FTP list — using All Channels';
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isWifi ? Icons.wifi_rounded : Icons.signal_cellular_alt_rounded,
                              size: 14,
                              color: isWifi ? AppTheme.accent : AppTheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isp.toUpperCase(),
                              style: TextStyle(
                                color: isWifi ? AppTheme.accent : AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        if (hintText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            hintText,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                  loading: () => const Row(
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'DETECTING ISP…',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
        if (selected != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _NowPlayingInfo(channel: selected),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Consumer(
              builder: (context, ref, _) {
                final filter = ref.watch(channelFilterProvider);
                final showFtp = ref.watch(showFtpButtonProvider);
                return Row(
                  children: [
                    if (showFtp) ...[
                      _FilterChip(
                        label: 'FTP CHANNELS',
                        isSelected: filter == ChannelFilter.ftp,
                        onTap: () {
                          if (ref.read(channelFilterProvider) == ChannelFilter.ftp) return;
                          ref.read(channelFilterProvider.notifier).state = ChannelFilter.ftp;
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    _FilterChip(
                      label: 'ALL CHANNELS',
                      isSelected: filter == ChannelFilter.all || !showFtp,
                      onTap: () {
                        if (ref.read(channelFilterProvider) == ChannelFilter.all) return;
                        ref.read(channelFilterProvider.notifier).state = ChannelFilter.all;
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
                  SizedBox(height: 16),
                  Text(
                    'Loading channels…',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => ChannelCard(
                channel: channels[i],
                isActive: selected != null && channels[i].id == selected.id,
              ),
              childCount: channels.length,
            ),
          ),
        SliverToBoxAdapter(
            // child: Padding(
            //   padding: const EdgeInsets.only(top: 16, bottom: 24),
            //   child: const _FooterCredit(),
            // ),
            ),
      ],
    );
  }
}

class _BrandHeader extends ConsumerWidget {
  final bool compact;

  const _BrandHeader({this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannerAsync = ref.watch(bannerUrlProvider);

    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/logos/appLogo.png',
            width: 50,
            height: 50,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      'BOALIPARA TV',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'v1.0',
                      style: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.6),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                'Live TV Streaming',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              const FooterCredit(),
            ],
          ),
        ),
        if (!compact)
          bannerAsync.when(
            data: (url) => url != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      height: 70,
                      width: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primary),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
      ],
    );

    if (!compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleRow,
            const _BlinkingNotice(),
          ],
        ),
      );
    }

    // Compact (sidebar) variant: banner shown full-width below the title row
    // instead of squeezed beside it.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleRow,
          const SizedBox(height: 8),
          bannerAsync.when(
            data: (url) => url != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const _BlinkingNotice(),
        ],
      ),
    );
  }
}

/// Shows match/title info under the player.
class _NowPlayingInfo extends StatelessWidget {
  final dynamic channel;

  const _NowPlayingInfo({required this.channel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: AppTheme.liveBadgeGradient,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: Colors.white),
                SizedBox(width: 4),
                Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  channel.category,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Blinking notice text fetched from ispBannerAPI.json. Hidden if empty/null.
class _BlinkingNotice extends ConsumerStatefulWidget {
  const _BlinkingNotice();

  @override
  ConsumerState<_BlinkingNotice> createState() => _BlinkingNoticeState();
}

class _BlinkingNoticeState extends ConsumerState<_BlinkingNotice> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  double? _lastDistance;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _setupMarquee(double textWidth, double viewportWidth) {
    final distance = textWidth + viewportWidth;
    if (_lastDistance == distance && _controller != null) return; // already set up

    _lastDistance = distance;
    _controller?.dispose();

    final duration = Duration(milliseconds: (distance * 18).round()); // speed factor
    _controller = AnimationController(vsync: this, duration: duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _controller!.forward(from: 0);
        }
      })
      ..forward();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final noticeAsync = ref.watch(noticeTextProvider);
    return noticeAsync.when(
      data: (text) {
        if (text == null) return const SizedBox.shrink();
        final textStyle = TextStyle(
          color: AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textPainter = TextPainter(
                text: TextSpan(text: text, style: textStyle),
                maxLines: 1,
                textDirection: TextDirection.ltr,
              )..layout();

              final viewportWidth = constraints.maxWidth;
              final textWidth = textPainter.width;

              if (textWidth <= viewportWidth) {
                // Fits — show with slow blinking animation
                return _BlinkingText(text: text, style: textStyle);
              }

              final distance = textWidth + viewportWidth;

              WidgetsBinding.instance.addPostFrameCallback((_) {
                _setupMarquee(textWidth, viewportWidth);
              });

              if (_controller == null) {
                return ClipRect(
                  child: SizedBox(
                    height: textPainter.height,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(text, style: textStyle, maxLines: 1, softWrap: false),
                    ),
                  ),
                );
              }

              return ClipRect(
                child: SizedBox(
                  height: textPainter.height,
                  child: AnimatedBuilder(
                    animation: _controller!,
                    builder: (context, child) {
                      final dx = viewportWidth - _controller!.value * distance;
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: child,
                      );
                    },
                    child: Text(text, style: textStyle, maxLines: 1, softWrap: false),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Subtle "Made by Raisul" footer credit shown across screens.
class FooterCredit extends StatelessWidget {
  const FooterCredit();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Designed & Developed by ',
            style: TextStyle(
              color: AppTheme.textSecondary.withOpacity(0.6),
              fontSize: 10,
            ),
          ),
          TextSpan(
            text: 'Raisul',
            style: TextStyle(
              color: AppTheme.primary.withOpacity(0.9),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }
}

class _FilterChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: widget.isSelected ? AppTheme.liveBadgeGradient : null,
            color: widget.isSelected ? null : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : widget.isSelected
                      ? Colors.transparent
                      : Colors.white.withOpacity(0.15),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected ? Colors.white : AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _BlinkingText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _BlinkingText({required this.text, required this.style});

  @override
  State<_BlinkingText> createState() => _BlinkingTextState();
}

class _BlinkingTextState extends State<_BlinkingText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1.0, end: 0.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Text(widget.text, style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
