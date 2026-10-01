import 'dart:async';
import 'package:flutter/material.dart';
import '../core/pet/dragon_pet_controller.dart';

class DragonPetWidget extends StatefulWidget {
  final double size;
  final VoidCallback? onTap;
  final DragonPetState state;
  final bool enabled;

  const DragonPetWidget({
    super.key,
    this.size = 56,
    this.onTap,
    this.state = DragonPetState.idle,
    this.enabled = true,
  });

  @override
  State<DragonPetWidget> createState() => _DragonPetWidgetState();
}

class _DragonPetWidgetState extends State<DragonPetWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _idleController;
  Timer? _blinkTimer;
  DragonPetState _visualState = DragonPetState.idle;

  static const _assets = <DragonPetState, String>{
    DragonPetState.idle: 'assets/images/dragon/dragon_idle.png',
    DragonPetState.blink: 'assets/images/dragon/dragon_blink.png',
    DragonPetState.happy: 'assets/images/dragon/dragon_happy.png',
    DragonPetState.reading: 'assets/images/dragon/dragon_reading.png',
    DragonPetState.thinking: 'assets/images/dragon/dragon_thinking.png',
    DragonPetState.curious: 'assets/images/dragon/dragon_curious.png',
    DragonPetState.sleeping: 'assets/images/dragon/dragon_sleeping.png',
    DragonPetState.tired: 'assets/images/dragon/dragon_tired.png',
    DragonPetState.excited: 'assets/images/dragon/dragon_excited.png',
    DragonPetState.explaining: 'assets/images/dragon/dragon_explaining.png',
    DragonPetState.working: 'assets/images/dragon/dragon_working.png',
    DragonPetState.holdingBook: 'assets/images/dragon/dragon_holding_book.png',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _visualState = widget.state;
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: 3000 + DateTime.now().millisecond % 2500), () {
      if (!mounted || !widget.enabled || _visualState != DragonPetState.idle) return;
      setState(() => _visualState = DragonPetState.blink);
      Timer(const Duration(milliseconds: 160), () {
        if (mounted && widget.enabled && _visualState == DragonPetState.blink) {
          setState(() => _visualState = DragonPetState.idle);
          _scheduleBlink();
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant DragonPetWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _visualState = widget.state;
      _scheduleBlink();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _idleController.stop();
      _blinkTimer?.cancel();
    } else if (state == AppLifecycleState.resumed && !_idleController.isAnimating) {
      _idleController.repeat(reverse: true);
      _scheduleBlink();
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _idleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final asset = _assets[_visualState] ?? _assets[DragonPetState.idle]!;
    return Semantics(
      button: true,
      label: 'Study companion',
      hint: 'Open study companion actions',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _idleController,
          builder: (context, child) {
            final t = _visualState == DragonPetState.idle
                ? (_idleController.value * 0.5 - 0.25)
                : 0.0;
            final scale = _visualState == DragonPetState.happy || _visualState == DragonPetState.excited
                ? 1.0 + (_idleController.value * 0.02)
                : 1.0;
            return Transform.translate(
              offset: Offset(0, t),
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Image.asset(
              asset,
              key: ValueKey(asset),
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}
