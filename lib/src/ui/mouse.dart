library;

import 'dart:async';
import 'dart:math';

class MouseCursor {
  static const AUTO = 'auto';
  static const DEFAULT = 'default';
  static const POINTER = 'pointer';
  static const MOVE = 'move';
  static const CROSSHAIR = 'crosshair';
  static const TEXT = 'text';
  static const VERTICAL_TEXT = 'vertical-text';
  static const PROGRESS = 'progress';
  static const WAIT = 'wait';
  static const RESIZE_COLUMN = 'col-resize';
  static const RESIZE_ROW = 'row-resize';
  static const RESIZE_NORTH = 'n-resize';
  static const RESIZE_SOUTH = 's-resize';
  static const RESIZE_EAST = 'e-resize';
  static const RESIZE_WEST = 'w-resize';
  static const RESIZE_NORTHWEST = 'nw-resize';
  static const RESIZE_NORTHEAST = 'ne-resize';
  static const RESIZE_SOUTHWEST = 'sw-resize';
  static const RESIZE_SOUTHEAST = 'se-resize';
  static const NOT_ALLOWED = 'not-allowed';
  static const NO_DROP = 'no-drop';
  static const ALL_SCROLL = 'all-scroll';
}

class MouseCursorData {
  String url;
  Point<int> hotSpot;
  MouseCursorData(this.url, this.hotSpot);
}

/// Use the static properties of the [Mouse] class to control
/// the appearance of the mouse cursor.

class Mouse {
  static var _cursorHidden = false;
  static String _cursorName = MouseCursor.AUTO;
  static final _cursorDatas = <String, MouseCursorData>{};

  static final _cursorChangedEvent = StreamController<String>.broadcast();
  static Stream<String> onCursorChanged = _cursorChangedEvent.stream;

  //-------------------------------------------------------------------------------------------------
  //-------------------------------------------------------------------------------------------------

  static String get cursor => _cursorName;

  static set cursor(String cursorName) {
    _cursorName = cursorName;
    _cursorChangedEvent.add(cursorName);
  }

  //-------------------------------------------------------------------------------------------------

  static void registerCursor(String cursorName, MouseCursorData cursorData) {
    _cursorDatas[cursorName] = cursorData;
  }

  static void unregisterCursor(String cursorName) {
    _cursorDatas.remove(cursorName);
  }

  static void hide() {
    _cursorHidden = true;
    _cursorChangedEvent.add(_cursorName);
  }

  static void show() {
    _cursorHidden = false;
    _cursorChangedEvent.add(_cursorName);
  }

  //-------------------------------------------------------------------------------------------------

  static String getCursorStyle(String cursorName) {
    var style = cursorName;

    if (_cursorDatas.containsKey(cursorName)) {
      final cursorData = _cursorDatas[cursorName]!;
      final cursorDataUrl = cursorData.url;
      final cursorDataX = cursorData.hotSpot.x;
      final cursorDataY = cursorData.hotSpot.y;
      style = "url('$cursorDataUrl') $cursorDataX $cursorDataY, $style";
    }

    return _cursorHidden ? 'none' : style;
  }
}
