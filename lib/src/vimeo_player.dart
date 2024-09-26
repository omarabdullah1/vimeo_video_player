import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flick_video_player/flick_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'model/vimeo_video_config.dart';

class VimeoVideoPlayer extends StatefulWidget {
  final String url;
  final List<SystemUiOverlay> systemUiOverlay;
  final List<DeviceOrientation> deviceOrientation;
  final Duration? startAt;
  final void Function(Duration timePoint)? onProgress;
  final VoidCallback? onFinished;
  final bool autoPlay;
  final Options? dioOptionsForVimeoVideoConfig;

  const VimeoVideoPlayer({
    required this.url,
    this.systemUiOverlay = const [SystemUiOverlay.top, SystemUiOverlay.bottom],
    this.deviceOrientation = const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ],
    this.startAt,
    this.onProgress,
    this.onFinished,
    this.autoPlay = false,
    this.dioOptionsForVimeoVideoConfig,
    super.key,
  });

  @override
  State<VimeoVideoPlayer> createState() => _VimeoVideoPlayerState();
}

class _VimeoVideoPlayerState extends State<VimeoVideoPlayer> {
  VideoPlayerController? _videoPlayerController;
  final VideoPlayerController _emptyVideoPlayerController =
      VideoPlayerController.networkUrl(Uri.parse(''));

  FlickManager? _flickManager;
  ValueNotifier<bool> isVimeoVideoLoaded = ValueNotifier(false);

  final RegExp _vimeoRegExp = RegExp(
    r'^(?:http|https)?:?/?/?(?:www\.)?(?:player\.)?vimeo\.com/(?:channels/(?:\w+/)?|groups/[^/]*/videos/|video/|)(\d+)(?:|/\?)?$',
    caseSensitive: false,
    multiLine: false,
  );

  bool _isSeekedVideo = false;

  bool get _isVimeoVideo {
    final match = _vimeoRegExp.firstMatch(widget.url);
    return match != null && match.groupCount >= 1;
  }

  @override
  void initState() {
    super.initState();
    if (_isVimeoVideo) {
      if (_videoId.isEmpty) {
        throw Exception(
            'Unable to extract video id from the given Vimeo video url: ${widget.url}');
      }
      _videoPlayer();
    } else {
      throw Exception('Invalid Vimeo video url: ${widget.url}');
    }
  }

  @override
  void deactivate() {
    _videoPlayerController?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    _flickManager = null;
    _flickManager?.dispose();
    _videoPlayerController = null;
    _videoPlayerController?.dispose();
    _emptyVideoPlayerController.dispose();
    isVimeoVideoLoaded.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: ValueListenableBuilder(
        valueListenable: isVimeoVideoLoaded,
        builder: (context, bool isVideo, child) => Container(
          child: isVideo
              ? FlickVideoPlayer(
                  key: ObjectKey(_flickManager),
                  flickManager: _flickManager ??
                      FlickManager(
                          videoPlayerController: _emptyVideoPlayerController),
                  systemUIOverlay: widget.systemUiOverlay,
                  preferredDeviceOrientation: widget.deviceOrientation,
                  flickVideoWithControls: const FlickVideoWithControls(
                    videoFit: BoxFit.fitWidth,
                    controls: FlickPortraitControls(),
                  ),
                  flickVideoWithControlsFullscreen:
                      const FlickVideoWithControls(
                    controls: FlickLandscapeControls(),
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(
                    color: Colors.grey,
                    backgroundColor: Colors.white,
                  ),
                ),
        ),
      ),
      onPopInvoked: (didPop) {
        _videoPlayerController?.pause();
      },
    );
  }

  void _setVideoInitialPosition() {
    final Duration? startAt = widget.startAt;
    if (startAt != null && _videoPlayerController != null) {
      _videoPlayerController!.addListener(() {
        final videoData = _videoPlayerController!.value;
        if (videoData.isInitialized &&
            videoData.duration > startAt &&
            !_isSeekedVideo) {
          _videoPlayerController!.seekTo(startAt);
          _isSeekedVideo = true;
        }
      });
    }
  }

  void _setVideoListeners() {
    final onProgressCallback = widget.onProgress;
    final onFinishCallback = widget.onFinished;

    if (_videoPlayerController != null &&
        (onProgressCallback != null || onFinishCallback != null)) {
      _videoPlayerController!.addListener(() {
        final videoData = _videoPlayerController!.value;
        if (videoData.isInitialized) {
          if (videoData.isPlaying) {
            if (onProgressCallback != null) {
              onProgressCallback.call(videoData.position);
            }
          } else if (videoData.duration == videoData.position) {
            if (onFinishCallback != null) {
              onFinishCallback.call();
            }
          }
        }
      });
    }
  }

  void _videoPlayer() {
    _getVimeoVideoConfigFromUrl(widget.url).then((value) async {
      final progressiveList = value?.request?.files?.progressive;
      var vimeoMp4Video = '';

      if (progressiveList != null && progressiveList.isNotEmpty) {
        progressiveList.map((element) {
          if (element != null &&
              element.url != null &&
              element.url != '' &&
              vimeoMp4Video == '') {
            vimeoMp4Video = element.url ?? '';
          }
        }).toList();

        if (vimeoMp4Video.isEmpty) {
          showAlertDialog(context);
        }
      }

      _videoPlayerController =
          VideoPlayerController.networkUrl(Uri.parse(vimeoMp4Video));
      _setVideoInitialPosition();
      _setVideoListeners();

      _flickManager = FlickManager(
        videoPlayerController:
            _videoPlayerController ?? _emptyVideoPlayerController,
        autoPlay: widget.autoPlay,
      );

      if (mounted) {
        isVimeoVideoLoaded.value = !isVimeoVideoLoaded.value;
      }
    });
  }

  Future<VimeoVideoConfig?> _getVimeoVideoConfigFromUrl(
    String url, {
    bool trimWhitespaces = true,
  }) async {
    if (trimWhitespaces) url = url.trim();

    final response = await _getVimeoVideoConfig(vimeoVideoId: _videoId);
    return (response != null) ? response : null;
  }

  Future<VimeoVideoConfig?> _getVimeoVideoConfig({
    required String vimeoVideoId,
  }) async {
    try {
      Options dioOptions = Options(
        headers: {
          'Authorization':
              'Bearer YOUR_BEARER_TOKEN', // Replace with actual token
        },
      );

      Response responseData = await Dio().get(
        'https://player.vimeo.com/video/$vimeoVideoId/config',
        options: widget.dioOptionsForVimeoVideoConfig ?? dioOptions,
      );

      var vimeoVideo = VimeoVideoConfig.fromJson(responseData.data);
      return vimeoVideo;
    } catch (e) {
      log('Error: $e');
      return null;
    }
  }
}

extension _ShowAlertDialog on _VimeoVideoPlayerState {
  void showAlertDialog(BuildContext context) {
    AlertDialog alert = AlertDialog(
      title: const Text("Alert"),
      content: const Text("Something went wrong with this URL"),
      actions: [
        TextButton(
          child: const Text("OK"),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );

    showDialog(
        context: context,
        builder: (BuildContext context) {
          return alert;
        });
  }

  String get _videoId {
    RegExpMatch? match = _vimeoRegExp.firstMatch(widget.url);
    return match?.group(1) ?? '';
  }
}
