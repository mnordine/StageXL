@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

void main() {
  for (final createEvent in <BroadcastEvent Function()>[
    () => EnterFrameEvent(0.25),
    ExitFrameEvent.new,
    RenderEvent.new,
  ]) {
    final type = createEvent().type;

    test('$type releases its previous recipient on an empty broadcast', () async {
      final owner = Sprite();
      final event = createEvent();
      var calls = 0;
      final subscription = _stream(owner, type).listen((received) {
        calls++;
        expect(received, same(event));
        expect(received.target, same(owner));
        expect(received.currentTarget, same(owner));
        expect(received.eventPhase, EventPhase.AT_TARGET);
      });
      addTearDown(subscription.cancel);

      event.dispatch();
      expect(calls, 1);
      expect(event.target, same(owner));
      expect(event.currentTarget, same(owner));

      await subscription.cancel();
      event.dispatch();
      expect(calls, 1);
      expect(event.target, isNull);
      expect(event.currentTarget, isNull);
    });

    test('$type preserves target data for first futures', () async {
      final owner = Sprite();
      final event = createEvent();
      final future = _stream(owner, type).first;

      event.dispatch();
      final received = await future;
      expect(received, same(event));
      expect(received.target, same(owner));
      expect(received.currentTarget, same(owner));

      event.dispatch();
      expect(event.target, isNull);
      expect(event.currentTarget, isNull);
    });

    test('$type releases a failed callback recipient on the next empty broadcast', () async {
      final owner = Sprite();
      final event = createEvent();
      final subscription = _stream(owner, type).listen((_) => throw StateError('listener failed'));
      addTearDown(subscription.cancel);

      expect(event.dispatch, throwsStateError);
      await subscription.cancel();
      event.dispatch();
      expect(event.target, isNull);
      expect(event.currentTarget, isNull);
    });
  }
}

EventStream<BroadcastEvent> _stream(Sprite owner, String type) => switch (type) {
  Event.ENTER_FRAME => owner.onEnterFrame,
  Event.EXIT_FRAME => owner.onExitFrame,
  Event.RENDER => owner.onRender,
  _ => throw ArgumentError.value(type),
};
