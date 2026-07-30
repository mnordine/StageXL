@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

void main() {
  test('render texture disposal returns diagnostics to baseline', () {
    final baseline = ResourceDiagnostics.snapshot();
    final renderTexture = RenderTexture(8, 8, 0);

    expect(
      ResourceDiagnostics.snapshot().difference(baseline),
      {StageXLResourceType.renderTexture: 1},
    );

    renderTexture.dispose();

    expect(ResourceDiagnostics.snapshot().growthSince(baseline), isEmpty);
    expect(renderTexture.dispose, returnsNormally);
  });

  test('resource manager disposal returns entries to baseline', () {
    final baseline = ResourceDiagnostics.snapshot();
    final resources = ResourceManager()..addText('value', 'text');

    expect(
      ResourceDiagnostics.snapshot()[StageXLResourceType.resourceManagerEntry],
      baseline[StageXLResourceType.resourceManagerEntry] + 1,
    );

    resources.dispose();

    expect(ResourceDiagnostics.snapshot().growthSince(baseline), isEmpty);
  });
}
