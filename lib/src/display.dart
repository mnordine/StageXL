/// The main classes for the display list. This are the most important class
/// you will need to build your application.
///
/// The [Stage] is the main rendering surface of your application. All objects
/// of the display list do inherit the properties from [DisplayObject]. Your
/// images and artworks are stored in [BitmapData] objects and added to the
/// display list by creating [Bitmap] instances. To group your display objects
/// please use the [Sprite] or [DisplayObjectContainer] base class.
///
/// To get more information about the display list and how to create a stage,
/// please read the wiki article about the basics of StageXL here:
/// [Introducing StageXL](http://www.stagexl.org/docs/wiki-articles.html?article=introduction)
///
library;

import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'shared/power_prefs.dart';
import 'package:web/web.dart' as html;
import 'package:web/web.dart' show HTMLCanvasElement, HTMLImageElement, HTMLVideoElement, ImageBitmap;
import 'dart:math' hide Point, Rectangle;
import 'dart:math' as math show Point;
import 'dart:typed_data';

import 'animation.dart';
import 'drawing.dart';
import 'engine.dart';
import 'events.dart';
import 'geom.dart';
import 'internal/environment.dart' as env;
import 'internal/image_bitmap_loader.dart';
import 'internal/image_loader.dart';
import 'internal/tools.dart';
import 'resources.dart' show AssetManifest;
import 'ui.dart';

part 'display/bitmap.dart';
part 'display/bitmap_container.dart';
part 'display/bitmap_data.dart';
part 'display/bitmap_data_channel.dart';
part 'display/bitmap_data_load_info.dart';
part 'display/bitmap_data_load_options.dart';
part 'display/bitmap_data_update_batch.dart';
part 'display/bitmap_drawable.dart';
part 'display/bitmap_filter.dart';
part 'display/color_transform.dart';
part 'display/display_object.dart';
part 'display/display_object_cache.dart';
part 'display/display_object_children.dart';
part 'display/display_object_container.dart';
part 'display/display_object_container_3d.dart';
part 'display/display_object_parent.dart';
part 'display/interactive_object.dart';
part 'display/mask.dart';
part 'display/render_loop.dart';
part 'display/shape.dart';
part 'display/simple_button.dart';
part 'display/sprite.dart';
part 'display/sprite_3d.dart';
part 'display/stage.dart';
part 'display/stage_console.dart';
part 'display/stage_options.dart';
part 'display/stage_tools.dart';

final Matrix _identityMatrix = Matrix.fromIdentity();
