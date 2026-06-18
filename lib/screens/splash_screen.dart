import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/channel_providers.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) _checkAppStatus();
    });
  }

  Future<void> _checkAppStatus() async {
    final config = await ref.read(ispBannerConfigProvider.future);
    if (!mounted) return;

    final isLock = (config?['isLock'] as bool?) ?? false;
    final remoteVersion = config?['version'] as String?;
    final appLink = config?['appLink'] as String?;

    final info = await PackageInfo.fromPlatform();
    debugPrint('[RaisulTV] 🔎 remoteVersion=$remoteVersion, localVersion=${info.version}, isLock=$isLock');

    if (isLock) {
      _showLockDialog(appLink);
      return;
    }

    if (remoteVersion != null) {
      final localVersion = info.version; // e.g. "1.0.0"
      if (localVersion != remoteVersion) {
        _showUpdateDialog(appLink, remoteVersion);
        return;
      }
    }

    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _showUpdateDialog(String? appLink, String newVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.system_update_rounded, color: AppTheme.primary),
              const SizedBox(width: 10),
              Text(
                'Update Required',
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: _UpdateDialogContent(appLink: appLink, newVersion: newVersion),
        ),
      ),
    );
  }

  void _showLockDialog(String? appLink) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.lock_rounded, color: AppTheme.primary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Locked',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'by Developer',
                    style: TextStyle(
                      color: AppTheme.textSecondary.withOpacity(0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ),
          content: const Text(
            'This app is currently unavailable. Please check back later.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: appLink != null ? [
               
                ]
              : [],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.4),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/logos/appLogo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'BOALIPARA TV',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'LIVE SPORTS • ANYTIME, ANYWHERE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  ),
                  const SizedBox(height: 60),
                  Text(
                    'Crafted by Raisul',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textSecondary.withOpacity(0.7),
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateDialogContent extends StatefulWidget {
  final String? appLink;
  final String newVersion;

  const _UpdateDialogContent({required this.appLink, required this.newVersion});

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  double? _progress;
  bool _downloading = false;
  String? _error;

  Future<void> _downloadAndInstall() async {
    final link = widget.appLink;
    if (link == null) return;

    // Not a direct APK (e.g. Play Store link) — just open it externally
    if (!link.toLowerCase().endsWith('.apk')) {
      final uri = Uri.parse(link);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/app-update.apk';

      // Remove any old leftover file first
      final file = File(savePath);
      if (await file.exists()) await file.delete();

      await Dio().download(
        link,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );

      setState(() => _progress = 1);

      final result = await OpenFilex.open(savePath);
      debugPrint('[RaisulTV] OpenFilex: ${result.type} - ${result.message}');

      if (result.type != ResultType.done) {
        setState(() {
          _downloading = false;
          _error =
              'Couldn\'t open the installer. If prompted, allow "Install unknown apps" for this app, then tap Download again.';
        });
      }
    } catch (e) {
      debugPrint('[RaisulTV] Download error: $e');
      setState(() {
        _downloading = false;
        _progress = null;
        _error = 'Download failed. Please check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'A new version (${widget.newVersion}) is available. Please update to continue using the app.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        if (_downloading) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (_progress == null || _progress == 0) ? null : _progress,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (_progress == null || _progress == 0) ? 'Starting download…' : '${(_progress! * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _downloading ? null : _downloadAndInstall,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _downloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_rounded, color: Colors.white),
            label: Text(
              _downloading ? 'Downloading…' : 'Download Update',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
