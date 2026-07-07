// ignore_for_file: non_constant_identifier_names

part of '../engine.dart';

class RenderTextureWrapping {
  final int value;

  RenderTextureWrapping(this.value);

  static final REPEAT = RenderTextureWrapping(WebGL.REPEAT);
  static final CLAMP = RenderTextureWrapping(WebGL.CLAMP_TO_EDGE);
}
