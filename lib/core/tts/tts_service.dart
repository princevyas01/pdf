import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TtsState { playing, paused, stopped }

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  TtsState _state = TtsState.stopped;
  VoidCallback? _onCompletion;

  List<String> _chunks = [];
  int _currentChunkIndex = 0;
  int _speechGeneration = 0;
  static const int _maxChunkLength = 250;

  TtsState get state => _state;

  Future<void> init() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      _handleChunkCompletion();
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint('TTS engine error: $msg');
      _state = TtsState.stopped;
    });

    _flutterTts.setPauseHandler(() {
      _state = TtsState.paused;
    });

    _flutterTts.setContinueHandler(() {
      _state = TtsState.playing;
    });
  }

  Future<void> setSpeechRate(double rate) async {
    await _flutterTts.setSpeechRate(rate);
  }

  List<String> _splitIntoSentences(String text) {
    final RegExp sentenceRegex = RegExp(r'(?<=[.!?\n])\s+');
    final rawSentences = text.split(sentenceRegex);
    final List<String> result = [];

    for (var sentence in rawSentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.length <= _maxChunkLength) {
        result.add(trimmed);
      } else {
        final words = trimmed.split(RegExp(r'\s+'));
        final StringBuffer buffer = StringBuffer();

        for (var word in words) {
          if (buffer.length + word.length + 1 > _maxChunkLength) {
            if (buffer.isNotEmpty) {
              result.add(buffer.toString().trim());
              buffer.clear();
            }
          }
          if (buffer.isNotEmpty) buffer.write(' ');
          buffer.write(word);
        }
        if (buffer.isNotEmpty) {
          result.add(buffer.toString().trim());
        }
      }
    }
    return result;
  }

  Future<void> speak(String text, {VoidCallback? onCompletion}) async {
    _speechGeneration++;
    final currentGen = _speechGeneration;
    _onCompletion = onCompletion;

    if (text.trim().isEmpty) {
      _state = TtsState.stopped;
      return;
    }

    await _flutterTts.stop();
    _chunks = _splitIntoSentences(text);
    if (_chunks.isEmpty) {
      _chunks = [text.trim()];
    }
    _currentChunkIndex = 0;

    await _speakCurrentChunk(currentGen);
  }

  Future<void> _speakCurrentChunk(int generation) async {
    if (generation != _speechGeneration) return;
    if (_currentChunkIndex >= _chunks.length) {
      _state = TtsState.stopped;
      if (_onCompletion != null) _onCompletion!();
      return;
    }

    final chunkText = _chunks[_currentChunkIndex];
    final result = await _flutterTts.speak(chunkText);
    if (generation != _speechGeneration) return;

    if (result == 1) {
      _state = TtsState.playing;
    } else {
      _state = TtsState.stopped;
    }
  }

  void _handleChunkCompletion() {
    final gen = _speechGeneration;
    if (_state == TtsState.playing) {
      _currentChunkIndex++;
      if (_currentChunkIndex < _chunks.length) {
        _speakCurrentChunk(gen);
      } else {
        _state = TtsState.stopped;
        if (_onCompletion != null) {
          _onCompletion!();
        }
      }
    }
  }

  Future<void> pause() async {
    _speechGeneration++;
    await _flutterTts.stop();
    _state = TtsState.paused;
  }

  Future<void> resume() async {
    if (_state == TtsState.paused &&
        _chunks.isNotEmpty &&
        _currentChunkIndex < _chunks.length) {
      _speechGeneration++;
      final gen = _speechGeneration;
      _state = TtsState.playing;
      await _speakCurrentChunk(gen);
    } else {
      _state = TtsState.stopped;
    }
  }

  Future<void> stop() async {
    _speechGeneration++;
    await _flutterTts.stop();
    _state = TtsState.stopped;
  }

  void dispose() {
    _speechGeneration++;
    _flutterTts.stop();
    _state = TtsState.stopped;
  }
}
