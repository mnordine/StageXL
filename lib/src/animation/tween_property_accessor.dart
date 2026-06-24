part of '../animation.dart';

/// The abstract base class for [TweenPropertyAccessor2D] and
/// [TweenPropertyAccessor3D]. Those accessors are returned by
/// the [Tween.animate] and [Tween.animate3D] getters.

abstract class TweenPropertyAccessor {
  num _getValue(int propertyID);
  void _setValue(int propertyID, num value);
}

/// The [TweenPropertyAccessor2D] is used to access the animatable
/// properties of a [TweenObject2D]. This class is return by the
/// [Tween.animate] getter.

class TweenPropertyAccessor2D implements TweenPropertyAccessor {
  final Tween _tween;
  final TweenObject2D _tweenObject;

  TweenPropertyAccessor2D._(this._tween, this._tweenObject);

  TweenProperty get x => _tween._createTweenProperty(this, 0);
  TweenProperty get y => _tween._createTweenProperty(this, 1);
  TweenProperty get pivotX => _tween._createTweenProperty(this, 2);
  TweenProperty get pivotY => _tween._createTweenProperty(this, 3);
  TweenProperty get scaleX => _tween._createTweenProperty(this, 4);
  TweenProperty get scaleY => _tween._createTweenProperty(this, 5);
  TweenProperty get skewX => _tween._createTweenProperty(this, 6);
  TweenProperty get skewY => _tween._createTweenProperty(this, 7);
  TweenProperty get rotation => _tween._createTweenProperty(this, 8);
  TweenProperty get alpha => _tween._createTweenProperty(this, 9);

  @override
  num _getValue(int propertyID) => switch (propertyID) {
    0 => _tweenObject.x,
    1 => _tweenObject.y,
    2 => _tweenObject.pivotX,
    3 => _tweenObject.pivotY,
    4 => _tweenObject.scaleX,
    5 => _tweenObject.scaleY,
    6 => _tweenObject.skewX,
    7 => _tweenObject.skewY,
    8 => _tweenObject.rotation,
    9 => _tweenObject.alpha,
    _ => 0.0,
  };

  @override
  void _setValue(int propertyID, num value) {
    switch (propertyID) {
      case 0:
        _tweenObject.x = value;
      case 1:
        _tweenObject.y = value;
      case 2:
        _tweenObject.pivotX = value;
      case 3:
        _tweenObject.pivotY = value;
      case 4:
        _tweenObject.scaleX = value;
      case 5:
        _tweenObject.scaleY = value;
      case 6:
        _tweenObject.skewX = value;
      case 7:
        _tweenObject.skewY = value;
      case 8:
        _tweenObject.rotation = value;
      case 9:
        _tweenObject.alpha = value;
    }
  }
}

/// The [TweenPropertyAccessor3D] is used to access the animatable
/// properties of a [TweenObject3D]. This class is return by the
/// [Tween.animate3D] getter.

class TweenPropertyAccessor3D implements TweenPropertyAccessor {
  final Tween _tween;
  final TweenObject3D _tweenObject;

  TweenPropertyAccessor3D._(this._tween, this._tweenObject);

  TweenProperty get offsetX => _tween._createTweenProperty(this, 0);
  TweenProperty get offsetY => _tween._createTweenProperty(this, 1);
  TweenProperty get offsetZ => _tween._createTweenProperty(this, 2);
  TweenProperty get rotationX => _tween._createTweenProperty(this, 3);
  TweenProperty get rotationY => _tween._createTweenProperty(this, 4);
  TweenProperty get rotationZ => _tween._createTweenProperty(this, 5);

  @override
  num _getValue(int propertyID) =>  switch (propertyID) {
    0 => _tweenObject.offsetX,
    1 => _tweenObject.offsetY,
    2 => _tweenObject.offsetZ,
    3 => _tweenObject.rotationX,
    4 => _tweenObject.rotationY,
    5 => _tweenObject.rotationZ,
    _ => 0.0,
  };

  @override
  void _setValue(int propertyID, num value) {
    switch (propertyID) {
      case 0:
        _tweenObject.offsetX = value;
      case 1:
        _tweenObject.offsetY = value;
      case 2:
        _tweenObject.offsetZ = value;
      case 3:
        _tweenObject.rotationX = value;
      case 4:
        _tweenObject.rotationY = value;
      case 5:
        _tweenObject.rotationZ = value;
    }
  }
}
