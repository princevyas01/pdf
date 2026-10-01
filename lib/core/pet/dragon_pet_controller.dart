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
  Timer? _returnTimer;
  bool _active = true;

  DragonPetState get state => _state;

  void setState(DragonPetState value, {Duration? returnToIdleAfter}) {
    if (!_active) return;
    _state = value;
    notifyListeners();
    _returnTimer?.cancel();
    if (returnToIdleAfter != null) {
      _returnTimer = Timer(returnToIdleAfter, () => setState(DragonPetState.idle));
    }
  }

  void pause() {
    _active = false;
    _returnTimer?.cancel();
  }

  void resume() {
    _active = true;
    if (_state == DragonPetState.sleeping || _state == DragonPetState.tired) {
      _state = DragonPetState.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    super.dispose();
  }
}
