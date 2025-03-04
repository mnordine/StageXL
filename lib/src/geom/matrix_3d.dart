library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'matrix.dart';
import 'point.dart';
import 'rectangle.dart';

class Matrix3D {
  final Float32List _data = Float32List(16);

  Matrix3D.fromIdentity() {
    setIdentity();
  }

  Matrix3D.fromZero() {
    setZero();
  }

  Matrix3D.fromMatrix2D(Matrix matrix) {
    copyFrom2D(matrix);
  }

  Matrix3D.fromMatrix3D(Matrix3D matrix) {
    copyFrom(matrix);
  }

  Matrix3D clone() => Matrix3D.fromMatrix3D(this);

  //-----------------------------------------------------------------------------------------------

  Float32List get data => _data;

  double get m00 => _data[00];
  double get m10 => _data[01];
  double get m20 => _data[02];
  double get m30 => _data[03];
  double get m01 => _data[04];
  double get m11 => _data[05];
  double get m21 => _data[06];
  double get m31 => _data[07];
  double get m02 => _data[08];
  double get m12 => _data[09];
  double get m22 => _data[10];
  double get m32 => _data[11];
  double get m03 => _data[12];
  double get m13 => _data[13];
  double get m23 => _data[14];
  double get m33 => _data[15];

  //-----------------------------------------------------------------------------------------------

  Point<num> transformPoint(math.Point<num> point, [Point<num>? returnPoint]) {
    final px = point.x.toDouble();
    final py = point.y.toDouble();

    final td = m03 * px + m13 * py + m33;
    final tx = m00 * px + m10 * py + m30;
    final ty = m01 * px + m11 * py + m31;

    if (returnPoint is Point) {
      returnPoint.setTo(tx / td, ty / td);
      return returnPoint;
    } else {
      return Point<num>(tx / td, ty / td);
    }
  }

  Point<num> transformPointInverse(math.Point<num> point,
      [Point<num>? returnPoint]) {
    final px = point.x.toDouble();
    final py = point.y.toDouble();

    final td = px * (m01 * m13 - m03 * m11) +
        py * (m10 * m03 - m00 * m13) +
        m00 * m11 -
        m10 * m01;
    final tx = px * (m11 * m33 - m13 * m31) +
        py * (m30 * m13 - m10 * m33) +
        m10 * m31 -
        m30 * m11;
    final ty = px * (m03 * m31 - m01 * m33) +
        py * (m00 * m33 - m30 * m03) +
        m30 * m01 -
        m00 * m31;

    if (returnPoint is Point) {
      returnPoint.setTo(tx / td, ty / td);
      return returnPoint;
    } else {
      return Point<num>(tx / td, ty / td);
    }
  }

  //-----------------------------------------------------------------------------------------------

  Rectangle<num> transformRectangle(math.Rectangle<num> rectangle,
      [Rectangle<num>? returnRectangle]) {
    final num rl = rectangle.left.toDouble();
    final num rr = rectangle.right.toDouble();
    final num rt = rectangle.top.toDouble();
    final num rb = rectangle.bottom.toDouble();

    // transform rectangle corners

    final num d1 = m03 * rl + m13 * rt + m33;
    final num x1 = (m00 * rl + m10 * rt + m30) / d1;
    final num y1 = (m01 * rl + m11 * rt + m31) / d1;
    final num d2 = m03 * rr + m13 * rt + m33;
    final num x2 = (m00 * rr + m10 * rt + m30) / d2;
    final num y2 = (m01 * rr + m11 * rt + m31) / d2;
    final num d3 = m03 * rr + m13 * rb + m33;
    final num x3 = (m00 * rr + m10 * rb + m30) / d3;
    final num y3 = (m01 * rr + m11 * rb + m31) / d3;
    final num d4 = m03 * rl + m13 * rb + m33;
    final num x4 = (m00 * rl + m10 * rb + m30) / d4;
    final num y4 = (m01 * rl + m11 * rb + m31) / d4;

    // find minima and maxima

    var left = x1;
    if (left > x2) left = x2;
    if (left > x3) left = x3;
    if (left > x4) left = x4;

    var top = y1;
    if (top > y2) top = y2;
    if (top > y3) top = y3;
    if (top > y4) top = y4;

    var right = x1;
    if (right < x2) right = x2;
    if (right < x3) right = x3;
    if (right < x4) right = x4;

    var bottom = y1;
    if (bottom < y2) bottom = y2;
    if (bottom < y3) bottom = y3;
    if (bottom < y4) bottom = y4;

    final width = right - left;
    final heigth = bottom - top;

    if (returnRectangle is Rectangle) {
      returnRectangle.setTo(left, top, width, heigth);
      return returnRectangle;
    } else {
      return Rectangle<num>(left, top, width, heigth);
    }
  }

  //-----------------------------------------------------------------------------------------------

  void setIdentity() {
    _data[00] = 1.0;
    _data[01] = 0.0;
    _data[02] = 0.0;
    _data[03] = 0.0;
    _data[04] = 0.0;
    _data[05] = 1.0;
    _data[06] = 0.0;
    _data[07] = 0.0;
    _data[08] = 0.0;
    _data[09] = 0.0;
    _data[10] = 1.0;
    _data[11] = 0.0;
    _data[12] = 0.0;
    _data[13] = 0.0;
    _data[14] = 0.0;
    _data[15] = 1.0;
  }

  void setZero() {
    _data[00] = 0.0;
    _data[01] = 0.0;
    _data[02] = 0.0;
    _data[03] = 0.0;
    _data[04] = 0.0;
    _data[05] = 0.0;
    _data[06] = 0.0;
    _data[07] = 0.0;
    _data[08] = 0.0;
    _data[09] = 0.0;
    _data[10] = 0.0;
    _data[11] = 0.0;
    _data[12] = 0.0;
    _data[13] = 0.0;
    _data[14] = 0.0;
    _data[15] = 0.0;
  }

  //-----------------------------------------------------------------------------------------------

  void scale(num scaleX, num scaleY, num scaleZ) {
    _data[00] *= scaleX;
    _data[01] *= scaleX;
    _data[02] *= scaleX;
    _data[03] *= scaleX;

    _data[04] *= scaleY;
    _data[05] *= scaleY;
    _data[06] *= scaleY;
    _data[07] *= scaleY;

    _data[08] *= scaleZ;
    _data[09] *= scaleZ;
    _data[10] *= scaleZ;
    _data[11] *= scaleZ;
  }

  //-----------------------------------------------------------------------------------------------

  void translate(num translationX, num translationY, num translationZ) {
    _data[03] += translationX;
    _data[07] += translationY;
    _data[11] += translationZ;
  }

  void prependTranslation(
      num translationX, num translationY, num translationZ) {
    _data[03] += m00 * translationX + m10 * translationY + m20 * translationZ;
    _data[07] += m01 * translationX + m11 * translationY + m21 * translationZ;
    _data[11] += m02 * translationX + m12 * translationY + m22 * translationZ;
    _data[15] += m03 * translationX + m13 * translationY + m23 * translationZ;
  }

  //-----------------------------------------------------------------------------------------------

  void rotateX(num angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final m01 = this.m01;
    final m11 = this.m11;
    final m21 = this.m21;
    final m31 = this.m31;
    final m02 = this.m02;
    final m12 = this.m12;
    final m22 = this.m22;
    final m32 = this.m32;

    _data[04] = m01 * cos + m02 * sin;
    _data[05] = m11 * cos + m12 * sin;
    _data[06] = m21 * cos + m22 * sin;
    _data[07] = m31 * cos + m32 * sin;
    _data[08] = m02 * cos - m01 * sin;
    _data[09] = m12 * cos - m11 * sin;
    _data[10] = m22 * cos - m21 * sin;
    _data[11] = m32 * cos - m31 * sin;
  }

  void rotateY(num angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final m00 = this.m00;
    final m10 = this.m10;
    final m20 = this.m20;
    final m30 = this.m30;
    final m02 = this.m02;
    final m12 = this.m12;
    final m22 = this.m22;
    final m32 = this.m32;

    _data[00] = m00 * cos + m02 * sin;
    _data[01] = m10 * cos + m12 * sin;
    _data[02] = m20 * cos + m22 * sin;
    _data[03] = m30 * cos + m32 * sin;
    _data[08] = m02 * cos - m00 * sin;
    _data[09] = m12 * cos - m10 * sin;
    _data[10] = m22 * cos - m20 * sin;
    _data[11] = m32 * cos - m30 * sin;
  }

  void rotateZ(num angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final m00 = this.m00;
    final m10 = this.m10;
    final m20 = this.m20;
    final m30 = this.m30;
    final m01 = this.m01;
    final m11 = this.m11;
    final m21 = this.m21;
    final m31 = this.m31;

    _data[00] = m00 * cos + m01 * sin;
    _data[01] = m10 * cos + m11 * sin;
    _data[02] = m20 * cos + m21 * sin;
    _data[03] = m30 * cos + m31 * sin;
    _data[04] = m01 * cos - m00 * sin;
    _data[05] = m11 * cos - m10 * sin;
    _data[06] = m21 * cos - m20 * sin;
    _data[07] = m31 * cos - m30 * sin;
  }

  //-------------------------------------------------------------------------------------------------

  void copyFrom2D(Matrix matrix) {
    _data[00] = matrix.a;
    _data[01] = matrix.c;
    _data[02] = 0.0;
    _data[03] = matrix.tx;
    _data[04] = matrix.b;
    _data[05] = matrix.d;
    _data[06] = 0.0;
    _data[07] = matrix.ty;
    _data[08] = 0.0;
    _data[09] = 0.0;
    _data[10] = 1.0;
    _data[11] = 0.0;
    _data[12] = 0.0;
    _data[13] = 0.0;
    _data[14] = 0.0;
    _data[15] = 1.0;
  }

  void copyFrom(Matrix3D matrix) {
    _data[00] = matrix.m00;
    _data[01] = matrix.m10;
    _data[02] = matrix.m20;
    _data[03] = matrix.m30;
    _data[04] = matrix.m01;
    _data[05] = matrix.m11;
    _data[06] = matrix.m21;
    _data[07] = matrix.m31;
    _data[08] = matrix.m02;
    _data[09] = matrix.m12;
    _data[10] = matrix.m22;
    _data[11] = matrix.m32;
    _data[12] = matrix.m03;
    _data[13] = matrix.m13;
    _data[14] = matrix.m23;
    _data[15] = matrix.m33;
  }

  //-----------------------------------------------------------------------------------------------

  void invert() {
    final a00 = _data[00];
    final a10 = _data[01];
    final a20 = _data[02];
    final a30 = _data[03];
    final a01 = _data[04];
    final a11 = _data[05];
    final a21 = _data[06];
    final a31 = _data[07];
    final a02 = _data[08];
    final a12 = _data[09];
    final a22 = _data[10];
    final a32 = _data[11];
    final a03 = _data[12];
    final a13 = _data[13];
    final a23 = _data[14];
    final a33 = _data[15];

    final b00 = a00 * a11 - a01 * a10;
    final b01 = a00 * a12 - a02 * a10;
    final b02 = a00 * a13 - a03 * a10;
    final b03 = a01 * a12 - a02 * a11;
    final b04 = a01 * a13 - a03 * a11;
    final b05 = a02 * a13 - a03 * a12;
    final b06 = a20 * a31 - a21 * a30;
    final b07 = a20 * a32 - a22 * a30;
    final b08 = a20 * a33 - a23 * a30;
    final b09 = a21 * a32 - a22 * a31;
    final b10 = a21 * a33 - a23 * a31;
    final b11 = a22 * a33 - a23 * a32;

    final det =
        b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;

    if (det != 0.0) {
      final invDet = 1.0 / det;
      _data[00] = (a11 * b11 - a12 * b10 + a13 * b09) * invDet;
      _data[01] = (-a10 * b11 + a12 * b08 - a13 * b07) * invDet;
      _data[02] = (a10 * b10 - a11 * b08 + a13 * b06) * invDet;
      _data[03] = (-a10 * b09 + a11 * b07 - a12 * b06) * invDet;
      _data[04] = (-a01 * b11 + a02 * b10 - a03 * b09) * invDet;
      _data[05] = (a00 * b11 - a02 * b08 + a03 * b07) * invDet;
      _data[06] = (-a00 * b10 + a01 * b08 - a03 * b06) * invDet;
      _data[07] = (a00 * b09 - a01 * b07 + a02 * b06) * invDet;
      _data[08] = (a31 * b05 - a32 * b04 + a33 * b03) * invDet;
      _data[09] = (-a30 * b05 + a32 * b02 - a33 * b01) * invDet;
      _data[10] = (a30 * b04 - a31 * b02 + a33 * b00) * invDet;
      _data[11] = (-a30 * b03 + a31 * b01 - a32 * b00) * invDet;
      _data[12] = (-a21 * b05 + a22 * b04 - a23 * b03) * invDet;
      _data[13] = (a20 * b05 - a22 * b02 + a23 * b01) * invDet;
      _data[14] = (-a20 * b04 + a21 * b02 - a23 * b00) * invDet;
      _data[15] = (a20 * b03 - a21 * b01 + a22 * b00) * invDet;
    }
  }

  //-----------------------------------------------------------------------------------------------

  void concat(Matrix3D matrix) {
    copyFromAndConcat(this, matrix);
  }

  void prepend(Matrix3D matrix) {
    copyFromAndConcat(matrix, this);
  }

  void concat2D(Matrix matrix) {
    final m00 = this.m00;
    final m10 = this.m10;
    final m20 = this.m20;
    final m30 = this.m30;
    final m01 = this.m01;
    final m11 = this.m11;
    final m21 = this.m21;
    final m31 = this.m31;
    final m03 = this.m03;
    final m13 = this.m13;
    final m23 = this.m23;
    final m33 = this.m33;

    final n00 = matrix.a;
    final n10 = matrix.c;
    final n30 = matrix.tx;
    final n01 = matrix.b;
    final n11 = matrix.d;
    final n31 = matrix.ty;

    _data[00] = m00 * n00 + m01 * n10 + m03 * n30;
    _data[01] = m10 * n00 + m11 * n10 + m13 * n30;
    _data[02] = m20 * n00 + m21 * n10 + m23 * n30;
    _data[03] = m30 * n00 + m31 * n10 + m33 * n30;
    _data[04] = m00 * n01 + m01 * n11 + m03 * n31;
    _data[05] = m10 * n01 + m11 * n11 + m13 * n31;
    _data[06] = m20 * n01 + m21 * n11 + m23 * n31;
    _data[07] = m30 * n01 + m31 * n11 + m33 * n31;
  }

  void concatInverse2D(Matrix matrix) {
    final m00 = this.m00;
    final m10 = this.m10;
    final m20 = this.m20;
    final m30 = this.m30;
    final m01 = this.m01;
    final m11 = this.m11;
    final m21 = this.m21;
    final m31 = this.m31;
    final m03 = this.m03;
    final m13 = this.m13;
    final m23 = this.m23;
    final m33 = this.m33;

    final num n00 = 0.0 + matrix.d / matrix.det;
    final num n10 = 0.0 - matrix.c / matrix.det;
    final num n30 = 0.0 - matrix.tx * n00 - matrix.ty * n10;
    final num n01 = 0.0 - matrix.b / matrix.det;
    final num n11 = 0.0 + matrix.a / matrix.det;
    final num n31 = 0.0 - matrix.tx * n01 - matrix.ty * n11;

    _data[00] = m00 * n00 + m01 * n10 + m03 * n30;
    _data[01] = m10 * n00 + m11 * n10 + m13 * n30;
    _data[02] = m20 * n00 + m21 * n10 + m23 * n30;
    _data[03] = m30 * n00 + m31 * n10 + m33 * n30;
    _data[04] = m00 * n01 + m01 * n11 + m03 * n31;
    _data[05] = m10 * n01 + m11 * n11 + m13 * n31;
    _data[06] = m20 * n01 + m21 * n11 + m23 * n31;
    _data[07] = m30 * n01 + m31 * n11 + m33 * n31;
  }

  void prepend2D(Matrix matrix) {
    final m00 = matrix.a;
    final m10 = matrix.c;
    final m30 = matrix.tx;
    final m01 = matrix.b;
    final m11 = matrix.d;
    final m31 = matrix.ty;

    final n00 = this.m00;
    final n10 = this.m10;
    final n30 = this.m30;
    final n01 = this.m01;
    final n11 = this.m11;
    final n31 = this.m31;
    final n02 = m02;
    final n12 = m12;
    final n32 = m32;
    final n03 = m03;
    final n13 = m13;
    final n33 = m33;

    _data[00] = m00 * n00 + m01 * n10;
    _data[01] = m10 * n00 + m11 * n10;
    _data[03] = m30 * n00 + m31 * n10 + n30;
    _data[04] = m00 * n01 + m01 * n11;
    _data[05] = m10 * n01 + m11 * n11;
    _data[07] = m30 * n01 + m31 * n11 + n31;
    _data[08] = m00 * n02 + m01 * n12;
    _data[09] = m10 * n02 + m11 * n12;
    _data[11] = m30 * n02 + m31 * n12 + n32;
    _data[12] = m00 * n03 + m01 * n13;
    _data[13] = m10 * n03 + m11 * n13;
    _data[15] = m30 * n03 + m31 * n13 + n33;
  }

  void prependInverse2D(Matrix matrix) {
    final m00 = 0.0 + matrix.d / matrix.det;
    final m10 = 0.0 - matrix.c / matrix.det;
    final m30 = 0.0 - matrix.tx * m00 - matrix.ty * m10;
    final m01 = 0.0 - matrix.b / matrix.det;
    final m11 = 0.0 + matrix.a / matrix.det;
    final m31 = 0.0 - matrix.tx * m01 - matrix.ty * m11;

    final n00 = this.m00;
    final n10 = this.m10;
    final n30 = this.m30;
    final n01 = this.m01;
    final n11 = this.m11;
    final n31 = this.m31;
    final n02 = m02;
    final n12 = m12;
    final n32 = m32;
    final n03 = m03;
    final n13 = m13;
    final n33 = m33;

    _data[00] = m00 * n00 + m01 * n10;
    _data[01] = m10 * n00 + m11 * n10;
    _data[03] = m30 * n00 + m31 * n10 + n30;
    _data[04] = m00 * n01 + m01 * n11;
    _data[05] = m10 * n01 + m11 * n11;
    _data[07] = m30 * n01 + m31 * n11 + n31;
    _data[08] = m00 * n02 + m01 * n12;
    _data[09] = m10 * n02 + m11 * n12;
    _data[11] = m30 * n02 + m31 * n12 + n32;
    _data[12] = m00 * n03 + m01 * n13;
    _data[13] = m10 * n03 + m11 * n13;
    _data[15] = m30 * n03 + m31 * n13 + n33;
  }

  void copyFromAndConcat2D(Matrix3D copyMatrix, Matrix concatMatrix) {
    final m00 = copyMatrix.m00;
    final m10 = copyMatrix.m10;
    final m20 = copyMatrix.m20;
    final m30 = copyMatrix.m30;
    final m01 = copyMatrix.m01;
    final m11 = copyMatrix.m11;
    final m21 = copyMatrix.m21;
    final m31 = copyMatrix.m31;
    final m02 = copyMatrix.m02;
    final m12 = copyMatrix.m12;
    final m22 = copyMatrix.m22;
    final m32 = copyMatrix.m32;
    final m03 = copyMatrix.m03;
    final m13 = copyMatrix.m13;
    final m23 = copyMatrix.m23;
    final m33 = copyMatrix.m33;

    final n00 = concatMatrix.a;
    final n10 = concatMatrix.c;
    final n30 = concatMatrix.tx;
    final n01 = concatMatrix.b;
    final n11 = concatMatrix.d;
    final n31 = concatMatrix.ty;

    _data[00] = m00 * n00 + m01 * n10 + m03 * n30;
    _data[01] = m10 * n00 + m11 * n10 + m13 * n30;
    _data[02] = m20 * n00 + m21 * n10 + m23 * n30;
    _data[03] = m30 * n00 + m31 * n10 + m33 * n30;
    _data[04] = m00 * n01 + m01 * n11 + m03 * n31;
    _data[05] = m10 * n01 + m11 * n11 + m13 * n31;
    _data[06] = m20 * n01 + m21 * n11 + m23 * n31;
    _data[07] = m30 * n01 + m31 * n11 + m33 * n31;
    _data[08] = m02;
    _data[09] = m12;
    _data[10] = m22;
    _data[11] = m32;
    _data[12] = m03;
    _data[13] = m13;
    _data[14] = m23;
    _data[15] = m33;
  }

  void copyFrom2DAndConcat(Matrix copyMatrix, Matrix3D concatMatrix) {
    final m00 = copyMatrix.a;
    final m10 = copyMatrix.c;
    final m30 = copyMatrix.tx;
    final m01 = copyMatrix.b;
    final m11 = copyMatrix.d;
    final m31 = copyMatrix.ty;

    final n00 = concatMatrix.m00;
    final n10 = concatMatrix.m10;
    final n20 = concatMatrix.m20;
    final n30 = concatMatrix.m30;
    final n01 = concatMatrix.m01;
    final n11 = concatMatrix.m11;
    final n21 = concatMatrix.m21;
    final n31 = concatMatrix.m31;
    final n02 = concatMatrix.m02;
    final n12 = concatMatrix.m12;
    final n22 = concatMatrix.m22;
    final n32 = concatMatrix.m32;
    final n03 = concatMatrix.m03;
    final n13 = concatMatrix.m13;
    final n23 = concatMatrix.m23;
    final n33 = concatMatrix.m33;

    _data[00] = m00 * n00 + m01 * n10;
    _data[01] = m10 * n00 + m11 * n10;
    _data[02] = n20;
    _data[03] = m30 * n00 + m31 * n10 + n30;
    _data[04] = m00 * n01 + m01 * n11;
    _data[05] = m10 * n01 + m11 * n11;
    _data[06] = n21;
    _data[07] = m30 * n01 + m31 * n11 + n31;
    _data[08] = m00 * n02 + m01 * n12;
    _data[09] = m10 * n02 + m11 * n12;
    _data[10] = n22;
    _data[11] = m30 * n02 + m31 * n12 + n32;
    _data[12] = m00 * n03 + m01 * n13;
    _data[13] = m10 * n03 + m11 * n13;
    _data[14] = n23;
    _data[15] = m30 * n03 + m31 * n13 + n33;
  }

  void copyFromAndConcat(Matrix3D copyMatrix, Matrix3D concatMatrix) {
    final m00 = copyMatrix.m00;
    final m10 = copyMatrix.m10;
    final m20 = copyMatrix.m20;
    final m30 = copyMatrix.m30;
    final m01 = copyMatrix.m01;
    final m11 = copyMatrix.m11;
    final m21 = copyMatrix.m21;
    final m31 = copyMatrix.m31;
    final m02 = copyMatrix.m02;
    final m12 = copyMatrix.m12;
    final m22 = copyMatrix.m22;
    final m32 = copyMatrix.m32;
    final m03 = copyMatrix.m03;
    final m13 = copyMatrix.m13;
    final m23 = copyMatrix.m23;
    final m33 = copyMatrix.m33;

    final n00 = concatMatrix.m00;
    final n10 = concatMatrix.m10;
    final n20 = concatMatrix.m20;
    final n30 = concatMatrix.m30;
    final n01 = concatMatrix.m01;
    final n11 = concatMatrix.m11;
    final n21 = concatMatrix.m21;
    final n31 = concatMatrix.m31;
    final n02 = concatMatrix.m02;
    final n12 = concatMatrix.m12;
    final n22 = concatMatrix.m22;
    final n32 = concatMatrix.m32;
    final n03 = concatMatrix.m03;
    final n13 = concatMatrix.m13;
    final n23 = concatMatrix.m23;
    final n33 = concatMatrix.m33;

    _data[00] = m00 * n00 + m01 * n10 + m02 * n20 + m03 * n30;
    _data[01] = m10 * n00 + m11 * n10 + m12 * n20 + m13 * n30;
    _data[02] = m20 * n00 + m21 * n10 + m22 * n20 + m23 * n30;
    _data[03] = m30 * n00 + m31 * n10 + m32 * n20 + m33 * n30;
    _data[04] = m00 * n01 + m01 * n11 + m02 * n21 + m03 * n31;
    _data[05] = m10 * n01 + m11 * n11 + m12 * n21 + m13 * n31;
    _data[06] = m20 * n01 + m21 * n11 + m22 * n21 + m23 * n31;
    _data[07] = m30 * n01 + m31 * n11 + m32 * n21 + m33 * n31;
    _data[08] = m00 * n02 + m01 * n12 + m02 * n22 + m03 * n32;
    _data[09] = m10 * n02 + m11 * n12 + m12 * n22 + m13 * n32;
    _data[10] = m20 * n02 + m21 * n12 + m22 * n22 + m23 * n32;
    _data[11] = m30 * n02 + m31 * n12 + m32 * n22 + m33 * n32;
    _data[12] = m00 * n03 + m01 * n13 + m02 * n23 + m03 * n33;
    _data[13] = m10 * n03 + m11 * n13 + m12 * n23 + m13 * n33;
    _data[14] = m20 * n03 + m21 * n13 + m22 * n23 + m23 * n33;
    _data[15] = m30 * n03 + m31 * n13 + m32 * n23 + m33 * n33;
  }
}
