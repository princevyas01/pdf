import 'dart:async';
import 'package:flutter/foundation.dart';

enum DragonPetState {
  idle,
  blink,
  happy,
  reading,
  thinking,
  curious,
  sleeping,
  tired,
  excited,
  explaining,
  working,
  holdingBook,
}

class DragonPetController extends ChangeNotifier {
  DragonPetState _state = DragonPetState.idle;
  DragonPetState _previousContextState = DragonPetState.idle;
  Timer? _returnTimer;
  Timer? _sleepTimer;
  Timer? _idleTimer;
  bool _active = true;
  DateTime _lastInteraction = DateTime.now();

  DragonPetState get state => _state;
  DateTime get lastInteraction => _lastInteraction;

  void setState(
    DragonPetState value, {
    Duration? returnToPreviousAfter,
  }) {
    if (!_active) return;
    if (value != DragonPetState.blink && value != _state) {
      _previousContextState = _state == DragonPetState.blink
          ? _previousContextState
          : _state;
    }
    _returnTimer?.cancel();
    _state = value;
    _lastInteraction = DateTime.now();
    notifyListeners();
    if (returnToPreviousAfter != null) {
      _returnTimer = Timer(returnToPreviousAfter, () {
        if (!_active) return;
        _state = _previousContextState == DragonPetState.blink
            ? DragonPetState.idle
            : _previousContextState;
        notifyListeners();
      });
    }
  }

  void setContextState(DragonPetState value) {
    if (!_active) return;
    _previousContextState = value;
    _returnTimer?.cancel();
    _state = value;
    _lastInteraction = DateTime.now();
    notifyListeners();
  }

  void markInteraction() {
    _lastInteraction = DateTime.now();
    if (_state == DragonPetState.sleeping || _state == DragonPetState.tired) {
      setContextState(DragonPetState.idle);
    }
    _scheduleInactivityState();
  }

  void _scheduleInactivityState() {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(const Duration(minutes: 2), () {
      if (!_active) return;
      final inactive = DateTime.now().difference(_lastInteraction);
      if (inactive >= const Duration(minutes: 2)) {
        setContextState(DragonPetState.tired);
      }
      _idleTimer?.cancel();
      _idleTimer = Timer(const Duration(minutes: 5), () {
        if (!_active) return;
        final stillInactive = DateTime.now().difference(_lastInteraction);
        if (stillInactive >= const Duration(minutes: 5)) {
          setContextState(DragonPetState.sleeping);
        }
      });
    });
  }

  void pause() {
    _active = false;
    _returnTimer?.cancel();
    _sleepTimer?.cancel();
    _idleTimer?.cancel();
  }

  void resume() {
    _active = true;
    _lastInteraction = DateTime.now();
    _returnTimer?.cancel();
    _sleepTimer?.cancel();
    _idleTimer?.cancel();
    if (_state == DragonPetState.sleeping || _state == DragonPetState.tired) {
      _state = DragonPetState.idle;
      notifyListeners();
    }
    _scheduleInactivityState();
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    _sleepTimer?.cancel();
    _idleTimer?.cancel();
    super.dispose();
  }
}
