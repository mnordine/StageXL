part of '../animation.dart';

/// The [AnimationChain] class is used to animate multiple [Animatable]s.
///
/// Those animatables are animated one after the other and the [onComplete]
/// callback is called when the last animatable has completed.
///
/// See also: [Juggler], [AnimationChain], [Animatable]
///
/// Examples:
///
///     var ac = new AnimationChain();
///     ac.add(new Tween(sprite, 2.0, Transition.easeOutBounce)..animate.x.to(700));
///     ac.add(new Tween(sprite, 2.0, Transition.linear)..animate.y.to(500));
///     ac.delay = 1.0;
///     ac.onStart = () => print("start");
///     ac.onComplete = () => print("complete");
///     juggler.add(ac);
///
///     juggler.addChain([
///         new Tween(sprite, 2.0, Transition.easeOutBounce)..animate.x.to(700),
///         new Tween(sprite, 2.0, Transition.linear)..animate.y.to(500)])
///        ..onComplete = () => print("complete");
///
class AnimationChain implements Animatable {
  final List<Animatable> _animatables = <Animatable>[];

  void Function()? _onStart;
  void Function()? _onComplete;

  num _time = 0.0;
  num _delay = 0.0;
  bool _started = false;
  bool _completed = false;
  final _completer = Completer<AnimationChain>();

  Future<AnimationChain> get done => _completer.future;

  //----------------------------------------------------------------------------

  /// Adds the [animatable] to this [AnimationChain].
  void add(Animatable animatable) {
    _animatables.add(animatable);
  }

  @override
  bool advanceTime(num time) {
    _time += time;

    if (_started == false) {
      if (_time > _delay) {
        _started = true;
        if (_onStart != null) _onStart!();
      } else {
        return true;
      }
    }

    if (_animatables.isNotEmpty) {
      if (_animatables[0].advanceTime(time) == false) {
        _animatables.removeAt(0);
      }
    }

    if (_animatables.isEmpty) {
      _completed = true;
      if (_onComplete != null) _onComplete!();
      if (!_completer.isCompleted) _completer.complete(this);
      return false;
    } else {
      return true;
    }
  }

  //----------------------------------------------------------------------------

  /// The delay this [AnimatableChain] waits until it starts animating.
  ///
  /// The delay may be changed as long as the animation has not been started.
  num get delay => _delay;

  set delay(num value) {
    if (_started == false) {
      _time = _time + _delay - value;
      _delay = value;
    }
  }

  /// Indicates if this [AnimatableChain] is completed.
  bool get isComplete => _completed;

  //----------------------------------------------------------------------------

  /// The function that is called when an [AnimationChain] starts.
  ///
  /// This happens after the specified [delay].
  set onStart(void Function() function) {
    _onStart = function;
  }

  /// The function that is called when an [AnimationChain] is completed.
  set onComplete(void Function() function) {
    _onComplete = function;
  }
}
