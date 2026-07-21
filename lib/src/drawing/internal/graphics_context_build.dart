part of '../../drawing.dart';

class _GraphicsContextBuild extends _GraphicsContextBase {
  final RenderBuildContext buildContext;

  _GraphicsContextBuild(this.buildContext);

  @override
  void fillColor(int color) => _path.collectColor(buildContext, color);

  @override
  void fillGradient(GraphicsGradient gradient) =>
      buildContext.addDrawOperation(_GraphicsGradientOperation(_path, gradient));

  @override
  void fillPattern(GraphicsPattern pattern) => _path.collectPattern(buildContext, pattern);

  @override
  void strokeColor(int color, double width, JointStyle jointStyle, CapsStyle capsStyle) =>
      _GraphicsStroke(_path, width, jointStyle, capsStyle).collectColor(buildContext, color);

  @override
  void strokeGradient(
    GraphicsGradient gradient,
    double width,
    JointStyle jointStyle,
    CapsStyle capsStyle,
  ) =>
      buildContext.addDrawOperation(
        _GraphicsGradientOperation(_GraphicsStroke(_path, width, jointStyle, capsStyle), gradient),
      );

  @override
  void strokePattern(GraphicsPattern pattern, double width, JointStyle jointStyle, CapsStyle capsStyle) =>
      _GraphicsStroke(_path, width, jointStyle, capsStyle).collectPattern(buildContext, pattern);

  @override
  void meshColor(_GraphicsCommandMeshColor command) => command.mesh.collectColor(buildContext, command.color);

  @override
  void meshGradient(_GraphicsCommandMeshGradient command) => buildContext.addDrawOperation(command);

  @override
  void meshPattern(_GraphicsCommandMeshPattern command) => command.mesh.collectPattern(buildContext, command.pattern);
}

final class _GraphicsGradientOperation implements RenderDrawOperation {
  final _GraphicsMesh mesh;
  final GraphicsGradient gradient;

  _GraphicsGradientOperation(this.mesh, this.gradient);

  @override
  void executeDraw(RenderState renderState) => mesh.fillGradient(renderState, gradient);
}
