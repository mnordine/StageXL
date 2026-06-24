part of '../events.dart';

/// The [TouchEvent] class lets you handle events on devices that detect user
/// contact with the device (such as a finger on a touch screen).
///
/// You have to opt-in for touch events by setting the InputEventMode
/// to `TouchOnly` or `MouseAndTouch` in the stage options like this:
///
///     StageXL.stageOptions.inputEventMode = InputEventMode.MouseAndTouch;

class TouchEvent extends InputEvent {
  static const TOUCH_BEGIN = 'touchBegin';
  static const TOUCH_END = 'touchEnd';
  static const TOUCH_CANCEL = 'touchCancel';
  static const TOUCH_MOVE = 'touchMove';

  static const TOUCH_OVER = 'touchOver';
  static const TOUCH_OUT = 'touchOut';

  static const TOUCH_ROLL_OUT = 'touchRollOut';
  static const TOUCH_ROLL_OVER = 'touchRollOver';
  static const TOUCH_TAP = 'touchTap';

  //---------------------------------------------------------------------------

  /// A unique identification number assigned to the touch point.

  final int touchPointID;

  /// Indicates whether the first point of contact is mapped to mouse events.

  final bool isPrimaryTouchPoint;

  /// Creates a new [TouchEvent].

  TouchEvent(
      super.type,
      super.bubbles,
      super.localX,
      super.localY,
      super.stageX,
      super.stageY,
      super.altKey,
      super.ctrlKey,
      super.shiftKey,
      this.touchPointID,
      this.isPrimaryTouchPoint);
}
