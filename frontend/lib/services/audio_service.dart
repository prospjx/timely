import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:kairos/core/constants.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(service.dispose);
  return service;
});

class AudioService {
  AudioService()
      : _player = AudioPlayer(),
        _tts = FlutterTts() {
    _configureTts();
  }

  final AudioPlayer _player;
  final FlutterTts _tts;
  final Dio _dio = Dio();
  bool _isSpeaking = false;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  bool get isPlaying => _player.playing;
  bool get isSpeaking => _isSpeaking;

  Future<void> playBrief(String url) async {
    final resolvedUrl = _resolveAudioUrl(url);
    final response = await _dio.get<List<int>>(
      resolvedUrl,
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Downloaded brief audio was empty');
    }

    final filePath = await _writeTempAudio(bytes);
    await _player.setFilePath(filePath);
    await _player.play();
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();
  Future<void> stop() => _player.stop();

  Future<void> speakBriefText(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }

    await _player.stop();
    await _tts.stop();
    _isSpeaking = true;
    await _tts.speak(normalized);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  Future<void> dispose() async {
    await _tts.stop();
    await _player.dispose();
  }

  void _configureTts() {
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.48);
    _tts.setVolume(1.0);
    _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      _isSpeaking = true;
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    _tts.setCancelHandler(() {
      _isSpeaking = false;
    });
    _tts.setErrorHandler((_) {
      _isSpeaking = false;
    });
  }

  String _resolveAudioUrl(String url) {
    if (url.startsWith('/audio/')) {
      final api = Uri.parse(AppConstants.apiBaseUrl);
      final origin = '${api.scheme}://${api.host}${api.hasPort ? ':${api.port}' : ''}';
      return '$origin$url';
    }

    if (url.startsWith('http://localhost:')) {
      return url.replaceFirst('http://localhost:', 'http://10.0.2.2:');
    }

    if (url.startsWith('https://localhost:')) {
      return url.replaceFirst('https://localhost:', 'https://10.0.2.2:');
    }

    return url;
  }

  Future<String> _writeTempAudio(List<int> bytes) async {
    final tempFile = File('${Directory.systemTemp.path}/kairos_brief_${DateTime.now().microsecondsSinceEpoch}.mp3');
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempFile.path;
  }
}
