import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/channel_model.dart';

// ⚠️ IMPORTANT: REPLACE THESE URLS WITH YOUR ACTUAL JSON URLs

const String ISP_BANNER_API_URL = 'https://raw.githubusercontent.com/helloraisul/json/main/ispBannerAPI.json';

const String ALL_CHANNELS_URL = 'https://raw.githubusercontent.com/helloraisul/json/main/allChannels.json';

/// Raw config fetched once on app open:
/// {
///   "bannerUrl": "...",
///   "ftpIsps": [
///     { "name": "Achiever Broadband Internet", "url": "..." },
///     { "name": "Link Tech IT", "url": "..." }
///   ]
/// }
final ispBannerConfigProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    // ✅ Add timestamp to force cache bypass
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    const baseUrl = 'https://raw.githubusercontent.com/helloraisul/json/main/ispBannerAPI.json';
    final apiUrl = '$baseUrl?t=$timestamp';

    final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 30));
    debugPrint('[RaisulTV] 📥 ISP config response: ${response.statusCode}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
  } catch (e) {
    debugPrint('[RaisulTV] ❌ ISP config fetch error: $e');
  }
  return null;
});

final bannerUrlProvider = FutureProvider<String?>((ref) async {
  final raw = await ref.watch(ispBannerConfigProvider.future);
  final url = raw?['bannerUrl'] as String?;
  debugPrint('[RaisulTV] 🖼 Banner URL: $url');
  return url;
});

/// Optional scrolling/blinking notice text shown under the footer credit.
/// Returns null (hidden) if missing or empty in the JSON.
final noticeTextProvider = FutureProvider<String?>((ref) async {
  final raw = await ref.watch(ispBannerConfigProvider.future);
  final text = raw?['noticeText'] as String?;
  if (text == null || text.trim().isEmpty) return null;
  debugPrint('[RaisulTV] 📢 Notice: $text');
  return text;
});

/// List of { "name": ..., "url": ... } entries
final ftpIspListProvider = FutureProvider<List<Map<String, String>>>((ref) async {
  try {
    final raw = await ref.watch(ispBannerConfigProvider.future);
    final list = raw?['ftpIsps'] as List<dynamic>?;
    final result = list
            ?.map((e) => {
                  'name': (e['name'] ?? '').toString(),
                  'url': (e['url'] ?? '').toString(),
                })
            .toList() ??
        [];
    debugPrint('[RaisulTV] 📋 FTP ISPs: $result');
    return result;
  } catch (_) {}
  return [];
});

/// Matched FTP ISP entry for the current connection (null if none matches,
/// not on wifi, or still loading -> handled separately).
final matchedFtpIspProvider = Provider<Map<String, String>?>((ref) {
  final ispAsync = ref.watch(ispNameProvider);
  final ftpIspsAsync = ref.watch(ftpIspListProvider);
  final isWifi = ref.watch(isWifiProvider);

  final isp = ispAsync.whenOrNull(data: (v) => v.toLowerCase().trim()) ?? '';
  final ftpIsps = ftpIspsAsync.whenOrNull(data: (v) => v) ?? [];

  if (!isWifi || isp.isEmpty || ftpIsps.isEmpty) return null;

  for (final entry in ftpIsps) {
    final name = (entry['name'] ?? '').toLowerCase().trim();
    if (name.isEmpty) continue;
    if (isp.contains(name) || name.contains(isp)) {
      debugPrint('[RaisulTV] 🔍 ISP match: $name -> ${entry['url']}');
      return entry;
    }
  }
  return null;
});

/// Whether the FTP channels button should be shown at all.
final showFtpButtonProvider = Provider<bool>((ref) {
  final ispAsync = ref.watch(ispNameProvider);
  final ftpIspsAsync = ref.watch(ftpIspListProvider);
  final isWifi = ref.watch(isWifiProvider);

  // While loading critical data, don't show yet (avoid flicker)
  if (ispAsync.isLoading || ftpIspsAsync.isLoading) return false;
  if (!isWifi) return false;

  return ref.watch(matchedFtpIspProvider) != null;
});

enum ChannelFilter { ftp, all }

final channelFilterProvider = StateProvider<ChannelFilter>((ref) => ChannelFilter.all);
final _ftpAutoSelectDoneProvider = StateProvider<bool>((ref) => false);

final ftpAutoSelectProvider = Provider<void>((ref) {
  final matched = ref.watch(matchedFtpIspProvider);
  final done = ref.watch(_ftpAutoSelectDoneProvider);
  if (matched != null && !done) {
    // Capture notifiers before microtask — ref becomes invalid after dependency change
    final doneNotifier = ref.read(_ftpAutoSelectDoneProvider.notifier);
    final filterNotifier = ref.read(channelFilterProvider.notifier);
    final currentFilter = ref.read(channelFilterProvider);
    Future.microtask(() {
      doneNotifier.state = true;
      if (currentFilter != ChannelFilter.ftp) {
        filterNotifier.state = ChannelFilter.ftp;
      }
    });
  }
});
final channelListProvider = FutureProvider<List<ChannelModel>>((ref) async {
  final filter = ref.watch(channelFilterProvider);
  final matchedFtp = ref.read(matchedFtpIspProvider);

  debugPrint('[RaisulTV] 🔄 channelListProvider triggered — filter=$filter, matchedFtp=${matchedFtp?['name']}');

  // Log the call stack to find who triggered this
  // try {
  //   throw Exception('stack trace');
  // } catch (e, st) {
  //   final lines = st.toString().split('\n').take(6).join('\n');
  //   debugPrint('[RaisulTV] 📍 Trigger stack:\n$lines');
  // }

  final String url;
  if (filter == ChannelFilter.ftp && matchedFtp != null && (matchedFtp['url'] ?? '').isNotEmpty) {
    url = matchedFtp['url']!;
  } else {
    url = ALL_CHANNELS_URL;
  }

  try {
    debugPrint('[RaisulTV] 📡 Fetching channels from: $url');

    final response = await http.get(Uri.parse(url)).timeout(
          const Duration(seconds: 30),
        );

    debugPrint('[RaisulTV] 📊 Response status: ${response.statusCode}');
    debugPrint(
        '[RaisulTV] 📝 Response body (first 200 chars): ${response.body.substring(0, (response.body.length > 200 ? 200 : response.body.length))}');

    if (response.statusCode == 404) {
      debugPrint('[RaisulTV] ⚠️ Channel list not found (404) — returning empty list');
      return [];
    }

    if (response.statusCode == 200) {
      debugPrint('[RaisulTV] ✅ Channels fetched successfully');

      final jsonData = jsonDecode(response.body);
      debugPrint('[RaisulTV] 🔍 JSON data type: ${jsonData.runtimeType}');

      final List<dynamic> channelsList;

      if (jsonData is Map) {
        if (jsonData.containsKey('record')) {
          channelsList = jsonData['record']['channels'] ?? jsonData['record'] ?? [];
          debugPrint('[RaisulTV] 📦 Found data in: jsonData["record"]');
        } else if (jsonData.containsKey('channels')) {
          channelsList = jsonData['channels'] ?? [];
          debugPrint('[RaisulTV] 📦 Found data in: jsonData["channels"]');
        } else {
          channelsList = [];
          debugPrint('[RaisulTV] ⚠️ Warning: Could not find channels in expected format');
        }
      } else if (jsonData is List) {
        channelsList = jsonData;
        debugPrint('[RaisulTV] 📦 Found data as direct array');
      } else {
        channelsList = [];
        debugPrint('[RaisulTV] ❌ Unexpected JSON format');
      }

      debugPrint('[RaisulTV] 🔢 Found ${channelsList.length} channels');

      return channelsList.map((json) {
        try {
          return ChannelModel(
            id: json['id'] as String,
            name: json['name'] as String,
            logoAsset: json['logoAsset'] as String? ?? 'assets/logos/default.png',
            streamUrl: json['streamUrl'] as String,
            category: json['category'] as String? ?? 'Live',
          );
        } catch (e) {
          debugPrint('[RaisulTV] ❌ Error parsing channel: $e');
          rethrow;
        }
      }).toList();
    } else {
      throw Exception('Failed to load channels: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('[RaisulTV] ❌ Error fetching channels: $e');
    if (e.toString().contains('TimeoutException') ||
        e.toString().contains('404') ||
        e.toString().contains('SocketException')) {
      return [];
    }
    rethrow;
  }
});

/// Currently selected channel (defaults to the first one, but preserves
/// selection across channel-list refetches caused by ISP detection).
final selectedChannelProvider = StateProvider<ChannelModel?>((ref) => null);

// Separate auto-select provider — keeps selection logic out of StateProvider
final autoSelectChannelProvider = Provider<void>((ref) {
  final channelsAsync = ref.watch(channelListProvider);
  final filter = ref.watch(channelFilterProvider);
  channelsAsync.whenData((list) {
    if (list.isEmpty) return;
    final existing = ref.read(selectedChannelProvider);
    final existingInList = existing != null && list.any((c) => c.id == existing.id);

    // Always re-select first channel when switching to FTP
    // because the old selection was from a different channel list
    if (!existingInList || filter == ChannelFilter.ftp && existing != null && !list.any((c) => c.id == existing.id)) {
      final selectedNotifier = ref.read(selectedChannelProvider.notifier);
      final playerNotifier = ref.read(playerControllerProvider.notifier);
      Future.microtask(() {
        selectedNotifier.state = list.first;
        playerNotifier.initialize(list.first.streamUrl);
      });
    }
  });
});
final appVersionProvider = FutureProvider<String?>((ref) async {
  final raw = await ref.watch(ispBannerConfigProvider.future);
  return raw?['version'] as String?;
});

final isLockProvider = FutureProvider<bool>((ref) async {
  final raw = await ref.watch(ispBannerConfigProvider.future);
  return (raw?['isLock'] as bool?) ?? false;
});

final appLinkProvider = FutureProvider<String?>((ref) async {
  final raw = await ref.watch(ispBannerConfigProvider.future);
  return raw?['appLink'] as String?;
});

/// Player connection/loading state for the active stream.
enum PlayerStatus { idle, loading, playing, error }

class PlayerState {
  final PlayerStatus status;
  final String? errorMessage;
  final bool isMuted;
  final bool showControls;
  final bool isFullscreen;

  const PlayerState({
    this.status = PlayerStatus.idle,
    this.errorMessage,
    this.isMuted = false,
    this.showControls = true,
    this.isFullscreen = false,
  });

  PlayerState copyWith({
    PlayerStatus? status,
    String? errorMessage,
    bool? isMuted,
    bool? showControls,
    bool? isFullscreen,
  }) {
    return PlayerState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      isMuted: isMuted ?? this.isMuted,
      showControls: showControls ?? this.showControls,
      isFullscreen: isFullscreen ?? this.isFullscreen,
    );
  }
}

/// Manages the VideoPlayerController lifecycle for the live stream.
class PlayerController extends StateNotifier<PlayerState> {
  PlayerController() : super(const PlayerState());

  VideoPlayerController? _videoController;
  VideoPlayerController? get videoController => _videoController;
  bool _hasUserInteracted = false;
  String? _currentUrl; // ✅ guard against duplicate init
  bool _intentionallyMuted = false; // ✅ prevents listener race on mute

  Future<void> initialize(String url) async {
    // ✅ Ignore if already initializing this exact URL
    if (_currentUrl == url) {
      debugPrint('[RaisulTV] initialize() skipped — already on $url');
      return;
    }
    _currentUrl = url;
    debugPrint('[RaisulTV] initialize() called for $url');
    state = state.copyWith(status: PlayerStatus.loading);

// Stop old controller before disposing to prevent audio overlap
    final old = _videoController;
    _videoController = null;
    old?.setVolume(0);
    await old?.pause();
    await Future.delayed(const Duration(milliseconds: 150)); // let surface detach
    old?.dispose();

    try {
      debugPrint('[RaisulTV] Creating new controller for $url');
      await Future.delayed(const Duration(milliseconds: 50)); // let old dispose settle
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: kIsWeb ? false : true,
        ),
        httpHeaders: {
          'Connection': 'keep-alive',
        },
      );
      _videoController = controller;

      controller.addListener(() {
        final value = controller.value;
        if (value.hasError) {
          debugPrint('[RaisulTV] VideoPlayerController error: ${value.errorDescription}');
        }
        // Re-apply volume if audio focus change zeroes it out (Android emulator fix)
        if (!kIsWeb && value.isPlaying && value.volume == 0.0 && !_intentionallyMuted) {
          debugPrint('[RaisulTV] ⚠️ Volume was zeroed externally — restoring to 1.0');
          controller.setVolume(1.0);
        }
      });

      debugPrint('[RaisulTV] Calling controller.initialize()...');
      await controller.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Stream connection timed out');
        },
      );

      debugPrint('[RaisulTV] Controller initialized. status before play: ${state.status}');
      controller.setLooping(false);

// ✅ Only mute on very first load on web (autoplay policy)
      if (kIsWeb && !_hasUserInteracted) {
        await controller.setVolume(0.0);
        _intentionallyMuted = true;
        state = state.copyWith(isMuted: true);
      } else {
        // Android/iOS: always start at full volume
        _intentionallyMuted = false;
        state = state.copyWith(isMuted: false);
        await controller.setVolume(1.0);
      }

      await controller.play();

      debugPrint('[RaisulTV] Stream initialized & playing. Setting status=playing');
      // Check if this controller is still the current one (not replaced by a newer init)
      if (_videoController != controller) {
        debugPrint('[RaisulTV] ⚠️ Controller was replaced during init — discarding stale result');
        controller.dispose();
        return;
      }
      state = state.copyWith(status: PlayerStatus.playing, errorMessage: null);
      debugPrint('[RaisulTV] State after update: ${state.status}');
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    } catch (e) {
      debugPrint('[RaisulTV] Stream init error: $e');
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      state = state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Unable to load stream. Check your connection.',
      );
    }
  }

  void toggleMute() {
    _hasUserInteracted = true;
    final muted = !state.isMuted;
    _intentionallyMuted = muted;
    debugPrint(
        '[RaisulTV] toggleMute: isMuted=$muted, controller=${_videoController != null}, initialized=${_videoController?.value.isInitialized}, currentVolume=${_videoController?.value.volume}');
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.setVolume(muted ? 0.0 : 1.0).then((_) {
        debugPrint('[RaisulTV] setVolume done: volume=${_videoController?.value.volume}');
      }).catchError((e) {
        debugPrint('[RaisulTV] setVolume error: $e');
      });
    } else {
      debugPrint('[RaisulTV] ⚠️ setVolume skipped — controller not ready');
    }
    state = state.copyWith(isMuted: muted);
  }

  void togglePlayPause() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    _hasUserInteracted = true;
    debugPrint('[RaisulTV] togglePlayPause(). isPlaying=${controller.value.isPlaying}');
    try {
      if (controller.value.isPlaying) {
        controller.pause();
        WakelockPlus.disable();
        state = state.copyWith();
      } else {
        if (kIsWeb) {
          // On web, live HLS can't resume after pause — reinitialize
          _currentUrl = null;
          initialize(controller.dataSource);
        } else {
          // For live streams: reinitialize to jump to live edge instead of resuming from paused position
          _currentUrl = null;
          initialize(controller.dataSource);
        }
      }
    } catch (e) {
      debugPrint('[RaisulTV] togglePlayPause error: $e');
    }
  }

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls);
  }

  void setFullscreen(bool value) {
    state = state.copyWith(isFullscreen: value);
  }

  void retry(String url) {
    _currentUrl = null; // force reinit
    initialize(url);
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    _videoController?.dispose();
    super.dispose();
  }
}

final playerControllerProvider = StateNotifierProvider<PlayerController, PlayerState>((ref) {
  return PlayerController();
});

// ✅ Auto-initialize player when selected channel changes
final channelPlayerSyncProvider = Provider<void>((ref) {
  final channel = ref.watch(selectedChannelProvider);
  if (channel == null) return;
  // Only auto-play on idle — never interrupt loading or playing
  final playerState = ref.read(playerControllerProvider); // read, not watch
  if (playerState.status == PlayerStatus.idle) {
    Future.microtask(() {
      ref.read(playerControllerProvider.notifier).initialize(channel.streamUrl);
    });
  }
});

final networkTypeProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((results) => results.isNotEmpty ? results.first : ConnectivityResult.none);
});

final isWifiProvider = Provider<bool>((ref) {
  final network = ref.watch(networkTypeProvider);
  return network.when(
    data: (result) => result == ConnectivityResult.wifi || result == ConnectivityResult.ethernet,
    loading: () => true, // assume wifi while detecting
    error: (_, __) => false,
  );
});

/// True if device reports any active network interface (wifi/mobile/ethernet).
/// Note: this only reflects interface state, not actual internet reachability.
final hasNetworkConnectionProvider = Provider<bool>((ref) {
  final network = ref.watch(networkTypeProvider);
  return network.when(
    data: (result) => result != ConnectivityResult.none,
    loading: () => true, // assume connected while detecting
    error: (_, __) => false,
  );
});

/// Periodically verifies actual internet reachability (not just interface state)
/// Verifies actual internet reachability (not just interface state).
/// Strategy (matches how most production apps do it):
///  - Check immediately on connectivity *change* (event-driven, free).
///  - While online: light periodic backup check every 60s (catches "connected
///    to wifi but router has no internet" cases without constant pinging).
///  - While offline: faster retry every 5s so the "No Internet" dialog
///    dismisses quickly once connection is restored.
final internetReachableProvider = StreamProvider<bool>((ref) async* {
  Future<bool> check() async {
    // Use the same endpoint for all platforms — avoids CORS issues on web
    // and connectivity false-negatives on Android with 1.1.1.1/google.com
    try {
      final response = await http.get(Uri.parse(ALL_CHANNELS_URL)).timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  const onlineInterval = Duration(seconds: 60);
  const offlineRetryInterval = Duration(seconds: 5);

  bool lastResult = await check();
  yield lastResult;

  // Event-driven: re-check whenever the OS reports a connectivity change.
  final changeController = StreamController<void>();
  final connectivitySub = Connectivity().onConnectivityChanged.listen((_) {
    changeController.add(null);
  });

  // Merge connectivity-change events with an adaptive periodic timer.
  while (true) {
    final interval = lastResult ? onlineInterval : offlineRetryInterval;

    final timerFuture = Future.delayed(interval);
    final changeFuture = changeController.stream.first;

    // Whichever happens first (timer tick or connectivity change) triggers a check.
    await Future.any([timerFuture, changeFuture]);

    lastResult = await check();
    yield lastResult;
  }
});

final ispNameProvider = FutureProvider<String>((ref) async {
  // Try multiple APIs in order until one works
  final apis = [
    () async {
      final r = await http.get(Uri.parse('https://ipapi.co/json/')).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        return (d['org'] ?? d['isp'] ?? '') as String;
      }
      return '';
    },
    () async {
      final r = await http.get(Uri.parse('https://ipinfo.io/json')).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        return (d['org'] ?? '') as String;
      }
      return '';
    },
    () async {
      final r = await http.get(Uri.parse('https://ipwho.is/')).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        return (d['connection']?['isp'] ?? d['org'] ?? '') as String;
      }
      return '';
    },
  ];

  for (final api in apis) {
    try {
      final result = await api();
      if (result.isNotEmpty) {
        // Strip AS number prefix e.g. "AS12345 Link Tech IT" → "Link Tech IT"
        final clean = result.replaceFirst(RegExp(r'^AS\d+\s*'), '');
        debugPrint('[RaisulTV] ISP detected: $clean');
        return clean;
      }
    } catch (e) {
      debugPrint('[RaisulTV] ISP API error: $e');
    }
  }
  return 'Unknown ISP';
});
