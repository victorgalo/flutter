// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'clipboard_utils.dart';
import 'keyboard_utils.dart';
import 'semantics_tester.dart';

Offset textOffsetToPosition(RenderParagraph paragraph, int offset) {
  const Rect caret = Rect.fromLTWH(0.0, 0.0, 2.0, 20.0);
  final Offset localOffset = paragraph.getOffsetForCaret(TextPosition(offset: offset), caret);
  return paragraph.localToGlobal(localOffset);
}

Offset globalize(Offset point, RenderBox box) {
  return box.localToGlobal(point);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final MockClipboard mockClipboard = MockClipboard();

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, mockClipboard.handleMethodCall);
    await Clipboard.setData(const ClipboardData(text: 'empty'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('SelectableRegion', () {
    testWidgets('mouse selection single click sends correct events', (WidgetTester tester) async {
      final UniqueKey spy = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: SelectionSpy(key: spy),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final RenderSelectionSpy renderSelectionSpy = tester.renderObject<RenderSelectionSpy>(find.byKey(spy));
      final TestGesture gesture = await tester.startGesture(const Offset(200.0, 200.0), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pumpAndSettle();
      renderSelectionSpy.events.clear();

      await gesture.moveTo(const Offset(200.0, 100.0));
      expect(renderSelectionSpy.events.length, 2);
      expect(renderSelectionSpy.events[0].type, SelectionEventType.startEdgeUpdate);
      final SelectionEdgeUpdateEvent startEdge = renderSelectionSpy.events[0] as SelectionEdgeUpdateEvent;
      expect(startEdge.globalPosition, const Offset(200.0, 200.0));
      expect(renderSelectionSpy.events[1].type, SelectionEventType.endEdgeUpdate);
      SelectionEdgeUpdateEvent endEdge = renderSelectionSpy.events[1] as SelectionEdgeUpdateEvent;
      expect(endEdge.globalPosition, const Offset(200.0, 100.0));
      renderSelectionSpy.events.clear();

      await gesture.moveTo(const Offset(100.0, 100.0));
      expect(renderSelectionSpy.events.length, 1);
      expect(renderSelectionSpy.events[0].type, SelectionEventType.endEdgeUpdate);
      endEdge = renderSelectionSpy.events[0] as SelectionEdgeUpdateEvent;
      expect(endEdge.globalPosition, const Offset(100.0, 100.0));

      await gesture.up();
    }, skip: kIsWeb); // https://github.com/flutter/flutter/issues/102410.

    testWidgets('mouse double click sends select-word event', (WidgetTester tester) async {
      final UniqueKey spy = UniqueKey();
      await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: SelectionSpy(key: spy),
            ),
          )
      );

      final RenderSelectionSpy renderSelectionSpy = tester.renderObject<RenderSelectionSpy>(find.byKey(spy));
      final TestGesture gesture = await tester.startGesture(const Offset(200.0, 200.0), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      renderSelectionSpy.events.clear();
      await gesture.down(const Offset(200.0, 200.0));
      await tester.pump();
      await gesture.up();
      expect(renderSelectionSpy.events.length, 1);
      expect(renderSelectionSpy.events[0], isA<SelectWordSelectionEvent>());
      final SelectWordSelectionEvent selectionEvent = renderSelectionSpy.events[0] as SelectWordSelectionEvent;
      expect(selectionEvent.globalPosition, const Offset(200.0, 200.0));
    });

    testWidgets('Does not crash when using Navigator pages', (WidgetTester tester) async {
      // Regression test for https://github.com/flutter/flutter/issues/119776
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            pages: <Page<void>> [
              MaterialPage<void>(
                child: Column(
                  children: <Widget>[
                    const Text('How are you?'),
                    SelectableRegion(
                      focusNode: FocusNode(),
                      selectionControls: materialTextSelectionControls,
                      child: const SelectAllWidget(child: SizedBox(width: 100, height: 100)),
                    ),
                    const Text('Fine, thank you.'),
                  ],
                ),
              ),
              const MaterialPage<void>(
                child: Scaffold(body: Text('Foreground Page')),
              ),
            ],
            onPopPage: (_, __) => false,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('can draw handles when they are at rect boundaries', (WidgetTester tester) async {
      final UniqueKey spy = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              const Text('How are you?'),
              SelectableRegion(
                focusNode: FocusNode(),
                selectionControls: materialTextSelectionControls,
                child: SelectAllWidget(key: spy, child: const SizedBox(width: 100, height: 100)),
              ),
              const Text('Fine, thank you.'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final TestGesture gesture = await tester.startGesture(tester.getCenter(find.byKey(spy)));
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump();

      final RenderSelectAll renderSpy = tester.renderObject<RenderSelectAll>(find.byKey(spy));
      expect(renderSpy.startHandle, isNotNull);
      expect(renderSpy.endHandle, isNotNull);
    });

    testWidgets('touch does not accept drag', (WidgetTester tester) async {
      final UniqueKey spy = UniqueKey();
      await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: SelectionSpy(key: spy),
            ),
          )
      );

      final RenderSelectionSpy renderSelectionSpy = tester.renderObject<RenderSelectionSpy>(find.byKey(spy));
      final TestGesture gesture = await tester.startGesture(const Offset(200.0, 200.0));
      addTearDown(gesture.removePointer);
      await gesture.moveTo(const Offset(200.0, 100.0));
      await gesture.up();
      expect(
        renderSelectionSpy.events.every((SelectionEvent element) => element is ClearSelectionEvent),
        isTrue
      );
    });

    testWidgets('does not merge semantics node of the children', (WidgetTester tester) async {
      final SemanticsTester semantics = SemanticsTester(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Line one'),
                    const Text('Line two'),
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('Button'),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        semantics,
        hasSemantics(
          TestSemantics.root(
            children: <TestSemantics>[
              TestSemantics(
                textDirection: TextDirection.ltr,
                children: <TestSemantics>[
                  TestSemantics(
                    children: <TestSemantics>[
                      TestSemantics(
                        flags: <SemanticsFlag>[SemanticsFlag.scopesRoute],
                        children: <TestSemantics>[
                          TestSemantics(
                            label: 'Line one',
                            textDirection: TextDirection.ltr,
                          ),
                          TestSemantics(
                            label: 'Line two',
                            textDirection: TextDirection.ltr,
                          ),
                          TestSemantics(
                            flags: <SemanticsFlag>[
                              SemanticsFlag.isButton,
                              SemanticsFlag.hasEnabledState,
                              SemanticsFlag.isEnabled,
                              SemanticsFlag.isFocusable
                            ],
                            actions: <SemanticsAction>[SemanticsAction.tap],
                            label: 'Button',
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          ignoreRect: true,
          ignoreTransform: true,
          ignoreId: true,
        ),
      );

      semantics.dispose();
    });

    testWidgets('mouse selection always cancels previous selection', (WidgetTester tester) async {
      final UniqueKey spy = UniqueKey();
      await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: SelectionSpy(key: spy),
            ),
          )
      );
      await tester.pumpAndSettle();

      final RenderSelectionSpy renderSelectionSpy = tester.renderObject<RenderSelectionSpy>(find.byKey(spy));
      final TestGesture gesture = await tester.startGesture(const Offset(200.0, 200.0), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pumpAndSettle();
      expect(renderSelectionSpy.events.length, 1);
      expect(renderSelectionSpy.events[0], isA<ClearSelectionEvent>());
    }, skip: kIsWeb); // https://github.com/flutter/flutter/issues/102410.

    testWidgets('touch long press sends select-word event', (WidgetTester tester) async {
      final UniqueKey spy = UniqueKey();
      await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: SelectionSpy(key: spy),
            ),
          )
      );
      await tester.pumpAndSettle();

      final RenderSelectionSpy renderSelectionSpy = tester.renderObject<RenderSelectionSpy>(find.byKey(spy));
      renderSelectionSpy.events.clear();
      final TestGesture gesture = await tester.startGesture(const Offset(200.0, 200.0));
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      expect(renderSelectionSpy.events.length, 1);
      expect(renderSelectionSpy.events[0], isA<SelectWordSelectionEvent>());
      final SelectWordSelectionEvent selectionEvent = renderSelectionSpy.events[0] as SelectWordSelectionEvent;
      expect(selectionEvent.globalPosition, const Offset(200.0, 200.0));
    });

    testWidgets('touch long press and drag sends correct events', (WidgetTester tester) async {
      final UniqueKey spy = UniqueKey();
      await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: SelectionSpy(key: spy),
            ),
          )
      );
      await tester.pumpAndSettle();

      final RenderSelectionSpy renderSelectionSpy = tester.renderObject<RenderSelectionSpy>(find.byKey(spy));
      renderSelectionSpy.events.clear();
      final TestGesture gesture = await tester.startGesture(const Offset(200.0, 200.0));
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      expect(renderSelectionSpy.events.length, 1);
      expect(renderSelectionSpy.events[0], isA<SelectWordSelectionEvent>());
      final SelectWordSelectionEvent selectionEvent = renderSelectionSpy.events[0] as SelectWordSelectionEvent;
      expect(selectionEvent.globalPosition, const Offset(200.0, 200.0));

      renderSelectionSpy.events.clear();
      await gesture.moveTo(const Offset(200.0, 50.0));
      await gesture.up();
      expect(renderSelectionSpy.events.length, 1);
      expect(renderSelectionSpy.events[0].type, SelectionEventType.endEdgeUpdate);
      final SelectionEdgeUpdateEvent edgeEvent = renderSelectionSpy.events[0] as SelectionEdgeUpdateEvent;
      expect(edgeEvent.globalPosition, const Offset(200.0, 50.0));
      expect(edgeEvent.granularity, TextGranularity.word);
    });

  testWidgets(
    'touch long press cancel does not send ClearSelectionEvent',
    (WidgetTester tester) async {
      final UniqueKey spy = UniqueKey();
      await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: SelectionSpy(key: spy),
            ),
          ),
      );
      await tester.pumpAndSettle();

      final RenderSelectionSpy renderSelectionSpy =
          tester.renderObject<RenderSelectionSpy>(find.byKey(spy));
      renderSelectionSpy.events.clear();
      final TestGesture gesture =
          await tester.startGesture(const Offset(200.0, 200.0));

      addTearDown(gesture.removePointer);

      await tester.pump(const Duration(milliseconds: 500));
      await gesture.cancel();
      expect(
        renderSelectionSpy.events.any((SelectionEvent element) => element is ClearSelectionEvent),
        isFalse,
      );
    },
  );

    testWidgets(
      'scrolling after the selection does not send ClearSelectionEvent',
      (WidgetTester tester) async {
        // Regression test for https://github.com/flutter/flutter/issues/128765
        final UniqueKey spy = UniqueKey();
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              height: 750,
              child: SingleChildScrollView(
                child: SizedBox(
                  height: 2000,
                  child: SelectableRegion(
                    focusNode: FocusNode(),
                    selectionControls: materialTextSelectionControls,
                    child: SelectionSpy(key: spy),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderSelectionSpy renderSelectionSpy = tester.renderObject<RenderSelectionSpy>(find.byKey(spy));
        renderSelectionSpy.events.clear();
        final TestGesture selectGesture = await tester.startGesture(const Offset(200.0, 200.0));
        addTearDown(selectGesture.removePointer);
        await tester.pump(const Duration(milliseconds: 500));
        await selectGesture.up();
        expect(renderSelectionSpy.events.length, 1);
        expect(renderSelectionSpy.events[0], isA<SelectWordSelectionEvent>());

        renderSelectionSpy.events.clear();
         final TestGesture scrollGesture =
            await tester.startGesture(const Offset(250.0, 850.0));
        await tester.pump(const Duration(milliseconds: 500));
        await scrollGesture.moveTo(Offset.zero);
        await scrollGesture.up();
        await tester.pumpAndSettle();
        expect(renderSelectionSpy.events.length, 0);
      },
    );

    testWidgets('mouse long press does not send select-word event', (WidgetTester tester) async {
      final UniqueKey spy = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: SelectionSpy(key: spy),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final RenderSelectionSpy renderSelectionSpy = tester.renderObject<RenderSelectionSpy>(find.byKey(spy));
      renderSelectionSpy.events.clear();
      final TestGesture gesture = await tester.startGesture(const Offset(200.0, 200.0), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      expect(
        renderSelectionSpy.events.every((SelectionEvent element) => element is ClearSelectionEvent),
        isTrue,
      );
    });
  });

  testWidgets('dragging handle or selecting word triggers haptic feedback on Android', (WidgetTester tester) async {
    final List<MethodCall> log = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
      log.add(methodCall);
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, mockClipboard.handleMethodCall);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SelectableRegion(
          focusNode: FocusNode(),
          selectionControls: materialTextSelectionControls,
          child: const Text('How are you?'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
    final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 6)); // at the 'r'
    addTearDown(gesture.removePointer);
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    // `are` is selected.
    expect(paragraph.selections[0], const TextSelection(baseOffset: 4, extentOffset: 7));
    expect(
      log.last,
      isMethodCall('HapticFeedback.vibrate', arguments: 'HapticFeedbackType.selectionClick'),
    );
    log.clear();
    final List<TextBox> boxes = paragraph.getBoxesForSelection(paragraph.selections[0]);
    expect(boxes.length, 1);
    final Offset handlePos = globalize(boxes[0].toRect().bottomRight, paragraph);
    await gesture.down(handlePos);
    final Offset endPos = Offset(textOffsetToPosition(paragraph, 8).dx, handlePos.dy);

    // Select 1 more character by dragging end handle to trigger feedback.
    await gesture.moveTo(endPos);
    expect(paragraph.selections[0], const TextSelection(baseOffset: 4, extentOffset: 8));
    // Only Android vibrate when dragging the handle.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        expect(
          log.last,
          isMethodCall('HapticFeedback.vibrate', arguments: 'HapticFeedbackType.selectionClick'),
        );
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        expect(log, isEmpty);
    }
    await gesture.up();
  }, variant: TargetPlatformVariant.all());

  group('SelectionArea integration', () {
    testWidgets('mouse can select single text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Center(
              child: Text('How are you'),
            ),
          ),
        ),
      );
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(textOffsetToPosition(paragraph, 4));
      await tester.pump();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 2, extentOffset: 4));

      await gesture.moveTo(textOffsetToPosition(paragraph, 6));
      await tester.pump();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 2, extentOffset: 6));

      // Check backward selection.
      await gesture.moveTo(textOffsetToPosition(paragraph, 1));
      await tester.pump();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 2, extentOffset: 1));

      // Start a new drag.
      await gesture.up();
      await gesture.down(textOffsetToPosition(paragraph, 5));
      await tester.pumpAndSettle();
      expect(paragraph.selections.isEmpty, isTrue);

      // Selecting across line should select to the end.
      await gesture.moveTo(textOffsetToPosition(paragraph, 5) + const Offset(0.0, 200.0));
      await tester.pump();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 5, extentOffset: 11));

      await gesture.up();
    });

    testWidgets('mouse can select word-by-word on double click drag', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Center(
              child: Text('How are you'),
            ),
          ),
        ),
      );
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      await gesture.down(textOffsetToPosition(paragraph, 2));
      await tester.pumpAndSettle();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));

      await gesture.moveTo(textOffsetToPosition(paragraph, 3));
      await tester.pumpAndSettle();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 4));

      await gesture.moveTo(textOffsetToPosition(paragraph, 4));
      await tester.pump();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 7));

      await gesture.moveTo(textOffsetToPosition(paragraph, 7));
      await tester.pump();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 8));

      await gesture.moveTo(textOffsetToPosition(paragraph, 8));
      await tester.pump();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 11));

      // Check backward selection.
      await gesture.moveTo(textOffsetToPosition(paragraph, 1));
      await tester.pump();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));

      // Start a new double-click drag.
      await gesture.up();
      await tester.pump();
      await gesture.down(textOffsetToPosition(paragraph, 5));
      await tester.pump();
      await gesture.up();
      expect(paragraph.selections.isEmpty, isTrue);
      await tester.pump(kDoubleTapTimeout);

      // Double-click.
      await gesture.down(textOffsetToPosition(paragraph, 5));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await gesture.down(textOffsetToPosition(paragraph, 5));
      await tester.pumpAndSettle();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 4, extentOffset: 7));

      // Selecting across line should select to the end.
      await gesture.moveTo(textOffsetToPosition(paragraph, 5) + const Offset(0.0, 200.0));
      await tester.pump();
      expect(paragraph.selections[0], const TextSelection(baseOffset: 4, extentOffset: 11));
      await gesture.up();
    }, skip: kIsWeb); // https://github.com/flutter/flutter/issues/125582.

    testWidgets('mouse can select multiple widgets on double click drag', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      await gesture.down(textOffsetToPosition(paragraph1, 2));
      await tester.pumpAndSettle();
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));

      await gesture.moveTo(textOffsetToPosition(paragraph1, 4));
      await tester.pump();
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 7));

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph2, 5));
      // Should select the rest of paragraph 1.
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 6));

      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph3, 6));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 14));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 0, extentOffset: 11));

      await gesture.up();
    }, skip: kIsWeb); // https://github.com/flutter/flutter/issues/125582.

    testWidgets('mouse can select multiple widgets on double click drag and return to origin word', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      await gesture.down(textOffsetToPosition(paragraph1, 2));
      await tester.pumpAndSettle();
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));

      await gesture.moveTo(textOffsetToPosition(paragraph1, 4));
      await tester.pump();
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 7));

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph2, 5));
      // Should select the rest of paragraph 1.
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 6));

      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph3, 6));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 14));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 0, extentOffset: 11));

      await gesture.moveTo(textOffsetToPosition(paragraph2, 5));
      // Should clear the selection on paragraph 3.
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 6));
      expect(paragraph3.selections.isEmpty, true);

      await gesture.moveTo(textOffsetToPosition(paragraph1, 4));
      // Should clear the selection on paragraph 2.
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 7));
      expect(paragraph2.selections.isEmpty, true);
      expect(paragraph3.selections.isEmpty, true);

      await gesture.up();
    }, skip: kIsWeb); // https://github.com/flutter/flutter/issues/125582.

    testWidgets('mouse can reverse selection across multiple widgets on double click drag', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph3, 10), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      await gesture.down(textOffsetToPosition(paragraph3, 10));
      await tester.pumpAndSettle();
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 6, extentOffset: 11));

      await gesture.moveTo(textOffsetToPosition(paragraph3, 4));
      await tester.pump();
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 11, extentOffset: 4));

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph2, 5));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 11, extentOffset: 0));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 14, extentOffset: 5));

      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph1, 6));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 11, extentOffset: 0));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 14, extentOffset: 0));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 12, extentOffset: 4));

      await gesture.up();
    }, skip: kIsWeb); // https://github.com/flutter/flutter/issues/125582.

    testWidgets('mouse can select multiple widgets', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(textOffsetToPosition(paragraph1, 4));
      await tester.pump();
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 2, extentOffset: 4));

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph2, 5));
      // Should select the rest of paragraph 1.
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 2, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 5));

      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph3, 6));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 2, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 14));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 0, extentOffset: 6));

      await gesture.up();
    });

    testWidgets('mouse can work with disabled container', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                SelectionContainer.disabled(child: Text('Good, and you?')),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(textOffsetToPosition(paragraph1, 4));
      await tester.pump();
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 2, extentOffset: 4));

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph2, 5));
      // Should select the rest of paragraph 1.
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 2, extentOffset: 12));
      // paragraph2 is in a disabled container.
      expect(paragraph2.selections.isEmpty, isTrue);

      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph3, 6));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 2, extentOffset: 12));
      expect(paragraph2.selections.isEmpty, isTrue);
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 0, extentOffset: 6));

      await gesture.up();
    });

    testWidgets('mouse can reverse selection', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph3, 10), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(textOffsetToPosition(paragraph3, 4));
      await tester.pump();
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 10, extentOffset: 4));

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph2, 5));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 10, extentOffset: 0));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 14, extentOffset: 5));

      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph1, 6));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 10, extentOffset: 0));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 14, extentOffset: 0));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 12, extentOffset: 6));

      await gesture.up();
    });

    testWidgets(
      'single tap on the previous selection toggles the toolbar on iOS',
      (WidgetTester tester) async {
        Set<ContextMenuButtonType> buttonTypes = <ContextMenuButtonType>{};
        final UniqueKey toolbarKey = UniqueKey();
        await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionHandleControls,
              contextMenuBuilder: (
                BuildContext context,
                SelectableRegionState selectableRegionState,
              ) {
                buttonTypes = selectableRegionState.contextMenuButtonItems
                  .map((ContextMenuButtonItem buttonItem) => buttonItem.type)
                  .toSet();
                return SizedBox.shrink(key: toolbarKey);
              },
              child: const Column(
                children: <Widget>[
                  Text('How are you?'),
                  Text('Good, and you?'),
                  Text('Fine, thank you.'),
                ],
              ),
            ),
          ),
        );

        expect(buttonTypes.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);

        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
        final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2));
        addTearDown(gesture.removePointer);
        await tester.pump(const Duration(milliseconds: 500));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));
        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        await gesture.down(textOffsetToPosition(paragraph, 2));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));
        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsNothing);

        await gesture.down(textOffsetToPosition(paragraph, 2));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));
        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        // Clear selection.
        await tester.tapAt(textOffsetToPosition(paragraph, 9));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      skip: kIsWeb, // [intended] Web uses its native context menu.
    );

    testWidgets(
      'right-click mouse can select word at position on Apple platforms',
      (WidgetTester tester) async {
        Set<ContextMenuButtonType> buttonTypes = <ContextMenuButtonType>{};
        final UniqueKey toolbarKey = UniqueKey();
        await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionHandleControls,
              contextMenuBuilder: (
                BuildContext context,
                SelectableRegionState selectableRegionState,
              ) {
                buttonTypes = selectableRegionState.contextMenuButtonItems
                  .map((ContextMenuButtonItem buttonItem) => buttonItem.type)
                  .toSet();
                return SizedBox.shrink(key: toolbarKey);
              },
              child: const Center(
                child: Text('How are you'),
              ),
            ),
          ),
        );

        expect(buttonTypes.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);

        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you'), matching: find.byType(RichText)));
        final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        addTearDown(gesture.removePointer);
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));

        await gesture.up();
        await tester.pump();

        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        await gesture.down(textOffsetToPosition(paragraph, 6));
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 4, extentOffset: 7));

        await gesture.up();
        await tester.pump();

        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        await gesture.down(textOffsetToPosition(paragraph, 9));
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 8, extentOffset: 11));

        await gesture.up();
        await tester.pump();

        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        // Clear selection.
        await tester.tapAt(textOffsetToPosition(paragraph, 1));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS, TargetPlatform.macOS }),
      skip: kIsWeb, // [intended] Web uses its native context menu.
    );

    testWidgets(
      'right-click mouse at the same position as previous right-click toggles the context menu on macOS',
      (WidgetTester tester) async {
        Set<ContextMenuButtonType> buttonTypes = <ContextMenuButtonType>{};
        final UniqueKey toolbarKey = UniqueKey();
        await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionHandleControls,
              contextMenuBuilder: (
                BuildContext context,
                SelectableRegionState selectableRegionState,
              ) {
                buttonTypes = selectableRegionState.contextMenuButtonItems
                  .map((ContextMenuButtonItem buttonItem) => buttonItem.type)
                  .toSet();
                return SizedBox.shrink(key: toolbarKey);
              },
              child: const Center(
                child: Text('How are you'),
              ),
            ),
          ),
        );

        expect(buttonTypes.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);

        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you'), matching: find.byType(RichText)));
        final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        addTearDown(gesture.removePointer);
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));

        await gesture.up();
        await tester.pump();

        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        await gesture.down(textOffsetToPosition(paragraph, 2));
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 3));

        await gesture.up();
        await tester.pump();

        // Right-click at same position will toggle the context menu off.
        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsNothing);

        await gesture.down(textOffsetToPosition(paragraph, 9));
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 8, extentOffset: 11));

        await gesture.up();
        await tester.pump();

        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        await gesture.down(textOffsetToPosition(paragraph, 9));
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 8, extentOffset: 11));

        await gesture.up();
        await tester.pump();

        // Right-click at same position will toggle the context menu off.
        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsNothing);

        await gesture.down(textOffsetToPosition(paragraph, 6));
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 4, extentOffset: 7));

        await gesture.up();
        await tester.pump();

        expect(buttonTypes, contains(ContextMenuButtonType.copy));
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        // Clear selection.
        await tester.tapAt(textOffsetToPosition(paragraph, 1));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      skip: kIsWeb, // [intended] Web uses its native context menu.
    );

    testWidgets(
      'right-click mouse shows the context menu at position on Android, Fucshia, and Windows',
      (WidgetTester tester) async {
        Set<ContextMenuButtonType> buttonTypes = <ContextMenuButtonType>{};
        final UniqueKey toolbarKey = UniqueKey();
        await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionHandleControls,
              contextMenuBuilder: (
                BuildContext context,
                SelectableRegionState selectableRegionState,
              ) {
                buttonTypes = selectableRegionState.contextMenuButtonItems
                  .map((ContextMenuButtonItem buttonItem) => buttonItem.type)
                  .toSet();
                return SizedBox.shrink(key: toolbarKey);
              },
              child: const Center(
                child: Text('How are you'),
              ),
            ),
          ),
        );

        expect(buttonTypes.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);

        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you'), matching: find.byType(RichText)));
        final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        addTearDown(gesture.removePointer);
        await tester.pump();
        // Selection is collapsed so none is reported.
        expect(paragraph.selections.isEmpty, true);

        await gesture.up();
        await tester.pump();

        expect(buttonTypes.length, 1);
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        await gesture.down(textOffsetToPosition(paragraph, 6));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);

        await gesture.up();
        await tester.pump();

        expect(buttonTypes.length, 1);
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        await gesture.down(textOffsetToPosition(paragraph, 9));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);

        await gesture.up();
        await tester.pump();

        expect(buttonTypes.length, 1);
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        // Clear selection.
        await tester.tapAt(textOffsetToPosition(paragraph, 1));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);

        // Create an uncollapsed selection by dragging.
        final TestGesture dragGesture = await tester.startGesture(textOffsetToPosition(paragraph, 0), kind: PointerDeviceKind.mouse);
        addTearDown(dragGesture.removePointer);
        await tester.pump();
        await dragGesture.moveTo(textOffsetToPosition(paragraph, 5));
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 5));
        await dragGesture.up();
        await tester.pump();

        // Right click on previous selection should not collapse the selection.
        await gesture.down(textOffsetToPosition(paragraph, 2));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 5));
        expect(find.byKey(toolbarKey), findsOneWidget);

        // Right click anywhere outside previous selection should collapse the
        // selection.
        await gesture.down(textOffsetToPosition(paragraph, 7));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);
        expect(find.byKey(toolbarKey), findsOneWidget);

        // Clear selection.
        await tester.tapAt(textOffsetToPosition(paragraph, 1));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.fuchsia, TargetPlatform.windows }),
      skip: kIsWeb, // [intended] Web uses its native context menu.
    );

    testWidgets(
      'right-click mouse toggles the context menu on Linux',
      (WidgetTester tester) async {
        Set<ContextMenuButtonType> buttonTypes = <ContextMenuButtonType>{};
        final UniqueKey toolbarKey = UniqueKey();
        await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionHandleControls,
              contextMenuBuilder: (
                BuildContext context,
                SelectableRegionState selectableRegionState,
              ) {
                buttonTypes = selectableRegionState.contextMenuButtonItems
                  .map((ContextMenuButtonItem buttonItem) => buttonItem.type)
                  .toSet();
                return SizedBox.shrink(key: toolbarKey);
              },
              child: const Center(
                child: Text('How are you'),
              ),
            ),
          ),
        );

        expect(buttonTypes.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);

        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you'), matching: find.byType(RichText)));
        final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        addTearDown(gesture.removePointer);
        await tester.pump();
        // Selection is collapsed so none is reported.
        expect(paragraph.selections.isEmpty, true);

        await gesture.up();
        await tester.pump();

        // Context menu toggled on.
        expect(buttonTypes.length, 1);
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        await gesture.down(textOffsetToPosition(paragraph, 6));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);

        await gesture.up();
        await tester.pump();

        // Context menu toggled off.
        expect(find.byKey(toolbarKey), findsNothing);

        await gesture.down(textOffsetToPosition(paragraph, 9));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);

        await gesture.up();
        await tester.pump();

        // Context menu toggled on.
        expect(buttonTypes.length, 1);
        expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
        expect(find.byKey(toolbarKey), findsOneWidget);

        // Clear selection.
        await tester.tapAt(textOffsetToPosition(paragraph, 1));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);

        final TestGesture dragGesture = await tester.startGesture(textOffsetToPosition(paragraph, 0), kind: PointerDeviceKind.mouse);
        addTearDown(dragGesture.removePointer);
        await tester.pump();
        await dragGesture.moveTo(textOffsetToPosition(paragraph, 5));
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 5));
        await dragGesture.up();
        await tester.pump();

        // Right click on previous selection should not collapse the selection.
        await gesture.down(textOffsetToPosition(paragraph, 2));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 5));
        expect(find.byKey(toolbarKey), findsOneWidget);

        // Right click anywhere outside previous selection should first toggle the context
        // menu off.
        await gesture.down(textOffsetToPosition(paragraph, 7));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(paragraph.selections[0], const TextSelection(baseOffset: 0, extentOffset: 5));
        expect(find.byKey(toolbarKey), findsNothing);

        // Right click again should collapse the selection and toggle the context
        // menu on.
        await gesture.down(textOffsetToPosition(paragraph, 7));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);
        expect(find.byKey(toolbarKey), findsOneWidget);

        // Clear selection.
        await tester.tapAt(textOffsetToPosition(paragraph, 1));
        await tester.pump();
        expect(paragraph.selections.isEmpty, true);
        expect(find.byKey(toolbarKey), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      skip: kIsWeb, // [intended] Web uses its native context menu.
    );

    testWidgets('can copy a selection made with the mouse', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      // Select from offset 2 of paragraph 1 to offset 6 of paragraph3.
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();

      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph3, 6));
      await gesture.up();

      // keyboard copy.
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyC, control: true));

      final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
      expect(clipboardData['text'], 'w are you?Good, and you?Fine, ');
    }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.fuchsia }));

    testWidgets(
      'does not override TextField keyboard shortcuts if the TextField is focused - non apple',
      (WidgetTester tester) async {
        final TextEditingController controller = TextEditingController(text: 'I am fine, thank you.');
        final FocusNode selectableRegionFocus = FocusNode();
        final FocusNode textFieldFocus = FocusNode();
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: SelectableRegion(
                focusNode: selectableRegionFocus,
                selectionControls: materialTextSelectionControls,
                child: Column(
                  children: <Widget>[
                    const Text('How are you?'),
                    const Text('Good, and you?'),
                    TextField(controller: controller, focusNode: textFieldFocus),
                  ],
                ),
              ),
            ),
          ),
        );
        textFieldFocus.requestFocus();
        await tester.pump();

        // Make sure keyboard select all works on TextField.
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyA, control: true));
        expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 21));

        // Make sure no selection in SelectableRegion.
        final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
        final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
        expect(paragraph1.selections.isEmpty, isTrue);
        expect(paragraph2.selections.isEmpty, isTrue);

        // Focus selectable region.
        selectableRegionFocus.requestFocus();
        await tester.pump();

        // Reset controller selection once the TextField is unfocused.
        controller.selection = const TextSelection.collapsed(offset: -1);

        // Make sure keyboard select all will be handled by selectable region now.
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyA, control: true));
        expect(controller.selection, const TextSelection.collapsed(offset: -1));
        expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 14));
        expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 12));
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.fuchsia }),
      skip: kIsWeb, // [intended] the web handles this on its own.
    );

    testWidgets(
      'does not override TextField keyboard shortcuts if the TextField is focused - apple',
      (WidgetTester tester) async {
        final TextEditingController controller = TextEditingController(text: 'I am fine, thank you.');
        final FocusNode selectableRegionFocus = FocusNode();
        final FocusNode textFieldFocus = FocusNode();
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: SelectableRegion(
                focusNode: selectableRegionFocus,
                selectionControls: materialTextSelectionControls,
                child: Column(
                  children: <Widget>[
                    const Text('How are you?'),
                    const Text('Good, and you?'),
                    TextField(controller: controller, focusNode: textFieldFocus),
                  ],
                ),
              ),
            ),
          ),
        );
        textFieldFocus.requestFocus();
        await tester.pump();

        // Make sure keyboard select all works on TextField.
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyA, meta: true));
        expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 21));

        // Make sure no selection in SelectableRegion.
        final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
        final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
        expect(paragraph1.selections.isEmpty, isTrue);
        expect(paragraph2.selections.isEmpty, isTrue);

        // Focus selectable region.
        selectableRegionFocus.requestFocus();
        await tester.pump();

        // Reset controller selection once the TextField is unfocused.
        controller.selection = const TextSelection.collapsed(offset: -1);

        // Make sure keyboard select all will be handled by selectable region now.
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyA, meta: true));
        expect(controller.selection, const TextSelection.collapsed(offset: -1));
        expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 14));
        expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 12));
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS, TargetPlatform.macOS }),
      skip: kIsWeb, // [intended] the web handles this on its own.
    );

    testWidgets('select all', (WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: focusNode,
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      focusNode.requestFocus();

      // keyboard select all.
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyA, control: true));

      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 0, extentOffset: 16));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 14));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 12));
    }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.fuchsia }));

    testWidgets(
      'mouse selection can handle widget span', (WidgetTester tester) async {
      final UniqueKey outerText = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: Center(
              child: Text.rich(
                const TextSpan(
                    children: <InlineSpan>[
                      TextSpan(text: 'How are you?'),
                      WidgetSpan(child: Text('Good, and you?')),
                      TextSpan(text: 'Fine, thank you.'),
                    ]
                ),
                key: outerText,
              ),
            ),
          ),
        ),
      );
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.byKey(outerText), matching: find.byType(RichText)).first);
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(textOffsetToPosition(paragraph, 17)); // right after `Fine`.
      await gesture.up();

      // keyboard copy.
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyC, control: true));
      final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
      expect(clipboardData['text'], 'w are you?Good, and you?Fine');
    },
      variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.fuchsia }),
      skip: isBrowser, // https://github.com/flutter/flutter/issues/61020
    );

    testWidgets(
      'can select word when a selectables rect is completely inside of another selectables rect', (WidgetTester tester) async {
      // Regression test for https://github.com/flutter/flutter/issues/127076.
      final UniqueKey outerText = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: Scaffold(
              body: Center(
                child: Text.rich(
                  const TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text:
                              'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
                        ),
                        WidgetSpan(child: Text('Some text in a WidgetSpan. ')),
                        TextSpan(text: 'Hello, world.'),
                      ],
                  ),
                  key: outerText,
                ),
              ),
            ),
          ),
        ),
      );
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.byKey(outerText), matching: find.byType(RichText)).first);

      // Adjust `textOffsetToPosition` result because it returns the wrong vertical position (wrong line).
      // TODO(bleroux): Remove when https://github.com/flutter/flutter/issues/133637 is fixed.
      final Offset gestureOffset = textOffsetToPosition(paragraph, 125).translate(0, 10);

      // Right click to select word at position.
      final TestGesture gesture = await tester.startGesture(gestureOffset, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      // Should select "Hello".
      expect(paragraph.selections[0], const TextSelection(baseOffset: 124, extentOffset: 129));
    },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      skip: isBrowser, // https://github.com/flutter/flutter/issues/61020
    );

    testWidgets(
      'widget span is ignored if it does not contain text - non Apple',
      (WidgetTester tester) async {
        final UniqueKey outerText = UniqueKey();
        await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: Center(
                child: Text.rich(
                  const TextSpan(
                      children: <InlineSpan>[
                        TextSpan(text: 'How are you?'),
                        WidgetSpan(child: Placeholder()),
                        TextSpan(text: 'Fine, thank you.'),
                      ]
                  ),
                  key: outerText,
                ),
              ),
            ),
          ),
        );
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.byKey(outerText), matching: find.byType(RichText)).first);
        final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2), kind: PointerDeviceKind.mouse);
        addTearDown(gesture.removePointer);
        await tester.pump();
        await gesture.moveTo(textOffsetToPosition(paragraph, 17)); // right after `Fine`.
        await gesture.up();

        // keyboard copy.
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyC, control: true));
        final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
        expect(clipboardData['text'], 'w are you?Fine');
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.fuchsia }),
      skip: isBrowser, // https://github.com/flutter/flutter/issues/61020
    );

    testWidgets(
      'widget span is ignored if it does not contain text - Apple',
          (WidgetTester tester) async {
        final UniqueKey outerText = UniqueKey();
        await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: Center(
                child: Text.rich(
                  const TextSpan(
                      children: <InlineSpan>[
                        TextSpan(text: 'How are you?'),
                        WidgetSpan(child: Placeholder()),
                        TextSpan(text: 'Fine, thank you.'),
                      ]
                  ),
                  key: outerText,
                ),
              ),
            ),
          ),
        );
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.byKey(outerText), matching: find.byType(RichText)).first);
        final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph, 2), kind: PointerDeviceKind.mouse);
        addTearDown(gesture.removePointer);
        await tester.pump();
        await gesture.moveTo(textOffsetToPosition(paragraph, 17)); // right after `Fine`.
        await gesture.up();

        // keyboard copy.
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyC, meta: true));
        final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
        expect(clipboardData['text'], 'w are you?Fine');
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS, TargetPlatform.macOS }),
      skip: isBrowser, // https://github.com/flutter/flutter/issues/61020
    );

    testWidgets('mouse can select across bidi text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('جيد وانت؟', textDirection: TextDirection.rtl),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(textOffsetToPosition(paragraph1, 4));
      await tester.pump();
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 2, extentOffset: 4));

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('جيد وانت؟'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph2, 5));
      // Should select the rest of paragraph 1.
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 2, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 5));

      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      // Add a little offset to cross the boundary between paragraph 2 and 3.
      await gesture.moveTo(textOffsetToPosition(paragraph3, 6) + const Offset(0, 1));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 2, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 9));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 0, extentOffset: 6));

      await gesture.up();
    }, skip: isBrowser); // https://github.com/flutter/flutter/issues/61020

    testWidgets('long press and drag touch moves selection word by word', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 6)); // at the 'r'
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      // `are` is selected.
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 4, extentOffset: 7));

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph2, 7));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 4, extentOffset: 12));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 9));
      await gesture.up();
    });

    testWidgets('can drag end handle when not covering entire screen', (WidgetTester tester) async {
      // Regression test for https://github.com/flutter/flutter/issues/104620.
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              const Text('How are you?'),
              SelectableRegion(
                focusNode: FocusNode(),
                selectionControls: materialTextSelectionControls,
                child: const Text('Good, and you?'),
              ),
              const Text('Fine, thank you.'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph2, 7)); // at the 'a'
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 6, extentOffset: 9));
      final List<TextBox> boxes = paragraph2.getBoxesForSelection(paragraph2.selections[0]);
      expect(boxes.length, 1);

      final Offset handlePos = globalize(boxes[0].toRect().bottomRight, paragraph2);
      await gesture.down(handlePos);

      await gesture.moveTo(textOffsetToPosition(paragraph2, 11) + Offset(0, paragraph2.size.height / 2));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 6, extentOffset: 11));
      await gesture.up();
    });

    testWidgets('can drag start handle when not covering entire screen', (WidgetTester tester) async {
      // Regression test for https://github.com/flutter/flutter/issues/104620.
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              const Text('How are you?'),
              SelectableRegion(
                focusNode: FocusNode(),
                selectionControls: materialTextSelectionControls,
                child: const Text('Good, and you?'),
              ),
              const Text('Fine, thank you.'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph2, 7)); // at the 'a'
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 6, extentOffset: 9));
      final List<TextBox> boxes = paragraph2.getBoxesForSelection(paragraph2.selections[0]);
      expect(boxes.length, 1);

      final Offset handlePos = globalize(boxes[0].toRect().bottomLeft, paragraph2);
      await gesture.down(handlePos);

      await gesture.moveTo(textOffsetToPosition(paragraph2, 11) + Offset(0, paragraph2.size.height / 2));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 11, extentOffset: 9));
      await gesture.up();
    });

    testWidgets('can drag start selection handle', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph3, 7)); // at the 'h'
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 6, extentOffset: 11));
      final List<TextBox> boxes = paragraph3.getBoxesForSelection(paragraph3.selections[0]);
      expect(boxes.length, 1);

      final Offset handlePos = globalize(boxes[0].toRect().bottomLeft, paragraph3);
      await gesture.down(handlePos);
      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph2, 5) + Offset(0, paragraph2.size.height / 2));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 0, extentOffset: 11));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 5, extentOffset: 14));

      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      await gesture.moveTo(textOffsetToPosition(paragraph1, 6) + Offset(0, paragraph1.size.height / 2));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 0, extentOffset: 11));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 14));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 6, extentOffset: 12));
      await gesture.up();
    });

    testWidgets('can drag start selection handle across end selection handle', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph3, 7)); // at the 'h'
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 6, extentOffset: 11));
      final List<TextBox> boxes = paragraph3.getBoxesForSelection(paragraph3.selections[0]);
      expect(boxes.length, 1);

      final Offset handlePos = globalize(boxes[0].toRect().bottomLeft, paragraph3);
      await gesture.down(handlePos);
      await gesture.moveTo(textOffsetToPosition(paragraph3, 14) + Offset(0, paragraph3.size.height / 2));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 14, extentOffset: 11));

      await gesture.moveTo(textOffsetToPosition(paragraph3, 4) + Offset(0, paragraph3.size.height / 2));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 4, extentOffset: 11));
      await gesture.up();
    });

    testWidgets('can drag end selection handle across start selection handle', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph3, 7)); // at the 'h'
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 6, extentOffset: 11));
      final List<TextBox> boxes = paragraph3.getBoxesForSelection(paragraph3.selections[0]);
      expect(boxes.length, 1);

      final Offset handlePos = globalize(boxes[0].toRect().bottomRight, paragraph3);
      await gesture.down(handlePos);
      await gesture.moveTo(textOffsetToPosition(paragraph3, 4) + Offset(0, paragraph3.size.height / 2));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 6, extentOffset: 4));

      await gesture.moveTo(textOffsetToPosition(paragraph3, 12) + Offset(0, paragraph3.size.height / 2));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 6, extentOffset: 12));
      await gesture.up();
    });

    testWidgets('can select all from toolbar', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph3, 7)); // at the 'h'
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 6, extentOffset: 11));
      expect(find.text('Select all'), findsOneWidget);

      await tester.tap(find.text('Select all'));
      await tester.pump();

      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 0, extentOffset: 16));
      expect(paragraph2.selections[0], const TextSelection(baseOffset: 0, extentOffset: 14));
      expect(paragraph1.selections[0], const TextSelection(baseOffset: 0, extentOffset: 12));
    }, skip: kIsWeb); // [intended] Web uses its native context menu.

    testWidgets('can copy from toolbar', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph3, 7)); // at the 'h'
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paragraph3.selections[0], const TextSelection(baseOffset: 6, extentOffset: 11));
      expect(find.text('Copy'), findsOneWidget);

      await tester.tap(find.text('Copy'));
      await tester.pump();

      // Selection should be cleared.
      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      expect(paragraph3.selections.isEmpty, isTrue);
      expect(paragraph2.selections.isEmpty, isTrue);
      expect(paragraph1.selections.isEmpty, isTrue);

      final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
      expect(clipboardData['text'], 'thank');
    }, skip: kIsWeb); // [intended] Web uses its native context menu.

    testWidgets('can use keyboard to granularly extend selection - character', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      // Select from offset 2 of paragraph1 to offset 6 of paragraph1.
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(textOffsetToPosition(paragraph1, 6));
      await gesture.up();
      await tester.pump();

      // Ho[w ar]e you?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 6);

      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true));
      await tester.pump();
      // Ho[w are] you?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 7);

      for (int i = 0; i < 5; i += 1) {
        await sendKeyCombination(tester,
            const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true));
        await tester.pump();
        expect(paragraph1.selections.length, 1);
        expect(paragraph1.selections[0].start, 2);
        expect(paragraph1.selections[0].end, 8 + i);
      }

      for (int i = 0; i < 5; i += 1) {
        await sendKeyCombination(tester,
            const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true));
        await tester.pump();
        expect(paragraph1.selections.length, 1);
        expect(paragraph1.selections[0].start, 2);
        expect(paragraph1.selections[0].end, 11 - i);
      }
    }, variant: TargetPlatformVariant.all());

    testWidgets('can use keyboard to granularly extend selection - word', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      // Select from offset 2 of paragraph1 to offset 6 of paragraph1.
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(textOffsetToPosition(paragraph1, 6));
      await gesture.up();
      await tester.pump();

      final bool alt;
      final bool control;
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          alt = false;
          control = true;
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          alt = true;
          control = false;
      }

      // Ho[w ar]e you?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 6);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, alt: alt, control: control));
      await tester.pump();
      // Ho[w are] you?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 7);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, alt: alt, control: control));
      await tester.pump();
      // Ho[w are you]?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 11);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, alt: alt, control: control));
      await tester.pump();
      // Ho[w are you?]
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 12);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, alt: alt, control: control));
      await tester.pump();
      // Ho[w are you?
      // Good], and you?
      // Fine, thank you.
      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 12);
      expect(paragraph2.selections.length, 1);
      expect(paragraph2.selections[0].start, 0);
      expect(paragraph2.selections[0].end, 4);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true, alt: alt, control: control));
      await tester.pump();
      // Ho[w are you?
      // ]Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 12);
      expect(paragraph2.selections.length, 0);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true, alt: alt, control: control));
      await tester.pump();
      // Ho[w are ]you?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 8);
      expect(paragraph2.selections.length, 0);
    }, variant: TargetPlatformVariant.all());

    testWidgets('can use keyboard to granularly extend selection - line', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      // Select from offset 2 of paragraph1 to offset 6 of paragraph1.
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(textOffsetToPosition(paragraph1, 6));
      await gesture.up();
      await tester.pump();

      final bool alt;
      final bool meta;
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          meta = false;
          alt = true;
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          meta = true;
          alt = false;
      }

      // Ho[w ar]e you?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 6);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, alt: alt, meta: meta));
      await tester.pump();
      // Ho[w are you?]
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 12);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, alt: alt, meta: meta));
      await tester.pump();
      // Ho[w are you?
      // Good, and you?]
      // Fine, thank you.
      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 12);
      expect(paragraph2.selections.length, 1);
      expect(paragraph2.selections[0].start, 0);
      expect(paragraph2.selections[0].end, 14);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true, alt: alt, meta: meta));
      await tester.pump();
      // Ho[w are you?]
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 12);
      expect(paragraph2.selections.length, 0);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true, alt: alt, meta: meta));
      await tester.pump();
      // [Ho]w are you?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 0);
      expect(paragraph1.selections[0].end, 2);
    }, variant: TargetPlatformVariant.all());

    testWidgets('can use keyboard to granularly extend selection - document', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      // Select from offset 2 of paragraph1 to offset 6 of paragraph1.
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(textOffsetToPosition(paragraph1, 6));
      await gesture.up();
      await tester.pump();

      final bool alt;
      final bool meta;
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          meta = false;
          alt = true;
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          meta = true;
          alt = false;
      }

      // Ho[w ar]e you?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 6);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowDown, shift: true, meta: meta, alt: alt));
      await tester.pump();
      // Ho[w are you?
      // Good, and you?
      // Fine, thank you.]
      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 12);
      expect(paragraph2.selections.length, 1);
      expect(paragraph2.selections[0].start, 0);
      expect(paragraph2.selections[0].end, 14);
      expect(paragraph3.selections.length, 1);
      expect(paragraph3.selections[0].start, 0);
      expect(paragraph3.selections[0].end, 16);

      await sendKeyCombination(tester, SingleActivator(LogicalKeyboardKey.arrowUp, shift: true, meta: meta, alt: alt));
      await tester.pump();
      // [Ho]w are you?
      // Good, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 0);
      expect(paragraph1.selections[0].end, 2);
      expect(paragraph2.selections.length, 0);
      expect(paragraph3.selections.length, 0);
    }, variant: TargetPlatformVariant.all());

    testWidgets('can use keyboard to directionally extend selection', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Column(
              children: <Widget>[
                Text('How are you?'),
                Text('Good, and you?'),
                Text('Fine, thank you.'),
              ],
            ),
          ),
        ),
      );
      // Select from offset 2 of paragraph2 to offset 6 of paragraph2.
      final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
      final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph2, 2), kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(textOffsetToPosition(paragraph2, 6));
      await gesture.up();
      await tester.pump();

      // How are you?
      // Go[od, ]and you?
      // Fine, thank you.
      expect(paragraph2.selections.length, 1);
      expect(paragraph2.selections[0].start, 2);
      expect(paragraph2.selections[0].end, 6);

      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true));
      await tester.pump();
      // How are you?
      // Go[od, and you?
      // Fine, t]hank you.
      final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
      expect(paragraph2.selections.length, 1);
      expect(paragraph2.selections[0].start, 2);
      expect(paragraph2.selections[0].end, 14);
      expect(paragraph3.selections.length, 1);
      expect(paragraph3.selections[0].start, 0);
      expect(paragraph3.selections[0].end, 7);

      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true));
      await tester.pump();
      // How are you?
      // Go[od, and you?
      // Fine, thank you.]
      expect(paragraph2.selections.length, 1);
      expect(paragraph2.selections[0].start, 2);
      expect(paragraph2.selections[0].end, 14);
      expect(paragraph3.selections.length, 1);
      expect(paragraph3.selections[0].start, 0);
      expect(paragraph3.selections[0].end, 16);

      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true));
      await tester.pump();
      // How are you?
      // Go[od, ]and you?
      // Fine, thank you.
      expect(paragraph2.selections.length, 1);
      expect(paragraph2.selections[0].start, 2);
      expect(paragraph2.selections[0].end, 6);
      expect(paragraph3.selections.length, 0);

      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true));
      await tester.pump();
      // How a[re you?
      // Go]od, and you?
      // Fine, thank you.
      final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 5);
      expect(paragraph1.selections[0].end, 12);
      expect(paragraph2.selections.length, 1);
      expect(paragraph2.selections[0].start, 0);
      expect(paragraph2.selections[0].end, 2);

      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true));
      await tester.pump();
      // [How are you?
      // Go]od, and you?
      // Fine, thank you.
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 0);
      expect(paragraph1.selections[0].end, 12);
      expect(paragraph2.selections.length, 1);
      expect(paragraph2.selections[0].start, 0);
      expect(paragraph2.selections[0].end, 2);
    }, variant: TargetPlatformVariant.all());

    group('magnifier', () {
      late ValueNotifier<MagnifierInfo> magnifierInfo;
      final Widget fakeMagnifier = Container(key: UniqueKey());

      testWidgets('Can drag handles to show, unshow, and update magnifier',
          (WidgetTester tester) async {
        const String text = 'Monkeys and rabbits in my soup';

        await tester.pumpWidget(
          MaterialApp(
            home: SelectableRegion(
              magnifierConfiguration: TextMagnifierConfiguration(
                magnifierBuilder: (_,
                    MagnifierController controller,
                    ValueNotifier<MagnifierInfo>
                        localMagnifierInfo) {
                  magnifierInfo = localMagnifierInfo;
                  return fakeMagnifier;
                },
              ),
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: const Text(text),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
                of: find.text(text), matching: find.byType(RichText)));

        // Show the selection handles.
        final TestGesture activateSelectionGesture = await tester
            .startGesture(textOffsetToPosition(paragraph, text.length ~/ 2));
        addTearDown(activateSelectionGesture.removePointer);
        await tester.pump(const Duration(milliseconds: 500));
        await activateSelectionGesture.up();
        await tester.pump(const Duration(milliseconds: 500));

        // Drag the handle around so that the magnifier shows.
        final TextBox selectionBox =
            paragraph.getBoxesForSelection(paragraph.selections.first).first;
        final Offset leftHandlePos =
            globalize(selectionBox.toRect().bottomLeft, paragraph);
        final TestGesture gesture = await tester.startGesture(leftHandlePos);
        await gesture.moveTo(textOffsetToPosition(paragraph, text.length - 2));
        await tester.pump();

        // Expect the magnifier to show and then store it's position.
        expect(find.byKey(fakeMagnifier.key!), findsOneWidget);
        final Offset firstDragGesturePosition =
            magnifierInfo.value.globalGesturePosition;

        await gesture.moveTo(textOffsetToPosition(paragraph, text.length));
        await tester.pump();

        // Expect the position the magnifier gets to have moved.
        expect(firstDragGesturePosition,
            isNot(magnifierInfo.value.globalGesturePosition));

        // Lift the pointer and expect the magnifier to disappear.
        await gesture.up();
        await tester.pump();

        expect(find.byKey(fakeMagnifier.key!), findsNothing);
      });
    });
  });

  testWidgets('toolbar is hidden on mobile when orientation changes', (WidgetTester tester) async {
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: SelectableRegion(
          focusNode: FocusNode(),
          selectionControls: materialTextSelectionControls,
          child: const Text('How are you?'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
    final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 6)); // at the 'r'
    addTearDown(gesture.removePointer);
    await tester.pump(const Duration(milliseconds: 500));
    // `are` is selected.
    expect(paragraph1.selections[0], const TextSelection(baseOffset: 4, extentOffset: 7));
    await tester.pumpAndSettle();
    // Text selection toolbar has appeared.
    expect(find.text('Copy'), findsOneWidget);

    // Hide the toolbar by changing orientation.
    tester.view.physicalSize = const Size(1800.0, 2400.0);
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);

    // Handles should be hidden as well on Android
    expect(
      find.descendant(
        of: find.byType(CompositedTransformFollower),
        matching: find.byType(Padding),
      ),
      defaultTargetPlatform == TargetPlatform.android ? findsNothing : findsNWidgets(2),
    );
  },
    skip: kIsWeb, // [intended] Web uses its native context menu.
    variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS, TargetPlatform.android }),
  );

  testWidgets('the selection behavior when clicking `Copy` item in mobile platforms', (WidgetTester tester) async {
    List<ContextMenuButtonItem> buttonItems = <ContextMenuButtonItem>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SelectableRegion(
          focusNode: FocusNode(),
          selectionControls: materialTextSelectionHandleControls,
          contextMenuBuilder: (
            BuildContext context,
            SelectableRegionState selectableRegionState,
          ) {
            buttonItems = selectableRegionState.contextMenuButtonItems;
            return const SizedBox.shrink();
          },
          child: const Text('How are you?'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
    await tester.longPressAt(textOffsetToPosition(paragraph1, 6)); // at the 'r'
    await tester.pump(kLongPressTimeout);
    // `are` is selected.
    expect(paragraph1.selections[0], const TextSelection(baseOffset: 4, extentOffset: 7));

    expect(buttonItems.length, 2);
    expect(buttonItems[0].type, ContextMenuButtonType.copy);

    // Press `Copy` item
    buttonItems[0].onPressed?.call();

    final SelectableRegionState regionState = tester.state<SelectableRegionState>(find.byType(SelectableRegion));

    // In Android copy should clear the selection.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        expect(regionState.selectionOverlay, isNull);
        expect(regionState.selectionOverlay?.startHandleLayerLink, isNull);
        expect(regionState.selectionOverlay?.endHandleLayerLink, isNull);
      case TargetPlatform.iOS:
        expect(regionState.selectionOverlay, isNotNull);
        expect(regionState.selectionOverlay?.startHandleLayerLink, isNotNull);
        expect(regionState.selectionOverlay?.endHandleLayerLink, isNotNull);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        expect(regionState.selectionOverlay, isNotNull);
    }
  },
    skip: kIsWeb, // [intended]
  );

  testWidgets('the handles do not disappear when clicking `Select all` item in mobile platforms', (WidgetTester tester) async {
    List<ContextMenuButtonItem> buttonItems = <ContextMenuButtonItem>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SelectableRegion(
          focusNode: FocusNode(),
          selectionControls: materialTextSelectionHandleControls,
          contextMenuBuilder: (
            BuildContext context,
            SelectableRegionState selectableRegionState,
          ) {
            buttonItems = selectableRegionState.contextMenuButtonItems;
            return const SizedBox.shrink();
          },
          child: const Text('How are you?'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
    await tester.longPressAt(textOffsetToPosition(paragraph1, 6)); // at the 'r'
    await tester.pump(kLongPressTimeout);
    // `are` is selected.
    expect(paragraph1.selections[0], const TextSelection(baseOffset: 4, extentOffset: 7));

    expect(buttonItems.length, 2);
    expect(buttonItems[1].type, ContextMenuButtonType.selectAll);

    // Press `Select All` item
    buttonItems[1].onPressed?.call();

    final SelectableRegionState regionState = tester.state<SelectableRegionState>(find.byType(SelectableRegion));

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        expect(regionState.selectionOverlay, isNotNull);
        expect(regionState.selectionOverlay?.startHandleLayerLink, isNotNull);
        expect(regionState.selectionOverlay?.endHandleLayerLink, isNotNull);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        // Test doesn't run these platforms.
        break;
    }

  },
    skip: kIsWeb, // [intended]
    variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.fuchsia }),
  );

  testWidgets('builds the correct button items', (WidgetTester tester) async {
    Set<ContextMenuButtonType> buttonTypes = <ContextMenuButtonType>{};
    await tester.pumpWidget(
      MaterialApp(
        home: SelectableRegion(
          focusNode: FocusNode(),
          selectionControls: materialTextSelectionHandleControls,
          contextMenuBuilder: (
            BuildContext context,
            SelectableRegionState selectableRegionState,
          ) {
            buttonTypes = selectableRegionState.contextMenuButtonItems
              .map((ContextMenuButtonItem buttonItem) => buttonItem.type)
              .toSet();
            return const SizedBox.shrink();
          },
          child: const Text('How are you?'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);

    final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
    final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 6)); // at the 'r'
    addTearDown(gesture.removePointer);
    await tester.pump(const Duration(milliseconds: 500));
    // `are` is selected.
    expect(paragraph1.selections[0], const TextSelection(baseOffset: 4, extentOffset: 7));
    await tester.pumpAndSettle();

    expect(buttonTypes, contains(ContextMenuButtonType.copy));
    expect(buttonTypes, contains(ContextMenuButtonType.selectAll));
  },
    variant: TargetPlatformVariant.all(),
    skip: kIsWeb, // [intended]
  );

  testWidgets('onSelectionChange is called when the selection changes through gestures', (WidgetTester tester) async {
    SelectedContent? content;

    await tester.pumpWidget(
      MaterialApp(
        home: SelectableRegion(
          onSelectionChanged: (SelectedContent? selectedContent) => content = selectedContent,
          focusNode: FocusNode(),
          selectionControls: materialTextSelectionControls,
          child: const Center(
            child: Text('How are you'),
          ),
        ),
      ),
    );

    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you'), matching: find.byType(RichText)));
    final TestGesture mouseGesture = await tester.startGesture(textOffsetToPosition(paragraph, 4), kind: PointerDeviceKind.mouse);
    final TestGesture touchGesture = await tester.createGesture();

    expect(content, isNull);
    addTearDown(mouseGesture.removePointer);
    addTearDown(touchGesture.removePointer);
    await tester.pump();

    // Called on drag.
    await mouseGesture.moveTo(textOffsetToPosition(paragraph, 7));
    await tester.pumpAndSettle();
    expect(content, isNotNull);
    expect(content!.plainText, 'are');

    // Updates on drag.
    await mouseGesture.moveTo(textOffsetToPosition(paragraph, 10));
    await tester.pumpAndSettle();
    expect(content, isNotNull);
    expect(content!.plainText, 'are yo');

    // Called on drag end.
    await mouseGesture.up();
    await tester.pump();
    expect(content, isNotNull);
    expect(content!.plainText, 'are yo');

    // Backwards selection.
    await mouseGesture.down(textOffsetToPosition(paragraph, 3));
    await tester.pumpAndSettle();
    expect(content, isNull);

    await mouseGesture.moveTo(textOffsetToPosition(paragraph, 0));
    await tester.pumpAndSettle();
    expect(content, isNotNull);
    expect(content!.plainText, 'How');

    await mouseGesture.up();
    await tester.pump();
    expect(content, isNotNull);
    expect(content!.plainText, 'How');

    // Called on double tap.
    await mouseGesture.down(textOffsetToPosition(paragraph, 6));
    await tester.pump();
    await mouseGesture.up();
    await tester.pump();
    await mouseGesture.down(textOffsetToPosition(paragraph, 6));
    await tester.pumpAndSettle();
    expect(content, isNotNull);
    expect(content!.plainText, 'are');
    await mouseGesture.up();
    await tester.pumpAndSettle();

    // Called on tap.
    await mouseGesture.down(textOffsetToPosition(paragraph, 0));
    await tester.pumpAndSettle();
    expect(content, isNull);
    await mouseGesture.up();
    await tester.pumpAndSettle();

    // With touch gestures.

    // Called on long press start.
    await touchGesture.down(textOffsetToPosition(paragraph, 0));
    await tester.pumpAndSettle(kLongPressTimeout);
    expect(content, isNotNull);
    expect(content!.plainText, 'How');

    // Called on long press update.
    await touchGesture.moveTo(textOffsetToPosition(paragraph, 5));
    await tester.pumpAndSettle();
    expect(content, isNotNull);
    expect(content!.plainText, 'How are');

    // Called on long press end.
    await touchGesture.up();
    await tester.pumpAndSettle();
    expect(content, isNotNull);
    expect(content!.plainText, 'How are');

    // Long press to select 'you'.
    await touchGesture.down(textOffsetToPosition(paragraph, 9));
    await tester.pumpAndSettle(kLongPressTimeout);
    expect(content, isNotNull);
    expect(content!.plainText, 'you');
    await touchGesture.up();
    await tester.pumpAndSettle();

    // Called while moving selection handles.
    final List<TextBox> boxes = paragraph.getBoxesForSelection(paragraph.selections[0]);
    expect(boxes.length, 1);
    final Offset startHandlePos = globalize(boxes[0].toRect().bottomLeft, paragraph);
    final Offset endHandlePos = globalize(boxes[0].toRect().bottomRight, paragraph);
    final Offset startPos = Offset(textOffsetToPosition(paragraph, 4).dx, startHandlePos.dy);
    final Offset endPos = Offset(textOffsetToPosition(paragraph, 6).dx, endHandlePos.dy);

    // Start handle.
    await touchGesture.down(startHandlePos);
    await touchGesture.moveTo(startPos);
    await tester.pumpAndSettle();
    expect(content, isNotNull);
    expect(content!.plainText, 'are you');
    await touchGesture.up();
    await tester.pumpAndSettle();

    // End handle.
    await touchGesture.down(endHandlePos);
    await touchGesture.moveTo(endPos);
    await tester.pumpAndSettle();
    expect(content, isNotNull);
    expect(content!.plainText, 'ar');
    await touchGesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('onSelectionChange is called when the selection changes through keyboard actions', (WidgetTester tester) async {
    SelectedContent? content;

    await tester.pumpWidget(
      MaterialApp(
        home: SelectableRegion(
          onSelectionChanged: (SelectedContent? selectedContent) => content = selectedContent,
          focusNode: FocusNode(),
          selectionControls: materialTextSelectionControls,
          child: const Column(
            children: <Widget>[
              Text('How are you?'),
              Text('Good, and you?'),
              Text('Fine, thank you.'),
            ],
          ),
        ),
      ),
    );

    expect(content, isNull);
    await tester.pump();

    final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('How are you?'), matching: find.byType(RichText)));
    final RenderParagraph paragraph2 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Good, and you?'), matching: find.byType(RichText)));
    final RenderParagraph paragraph3 = tester.renderObject<RenderParagraph>(find.descendant(of: find.text('Fine, thank you.'), matching: find.byType(RichText)));
    final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 2), kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(textOffsetToPosition(paragraph1, 6));
    await gesture.up();
    await tester.pump();

    expect(paragraph1.selections.length, 1);
    expect(paragraph1.selections[0].start, 2);
    expect(paragraph1.selections[0].end, 6);
    expect(content, isNotNull);
    expect(content!.plainText, 'w ar');

    await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true));
    await tester.pump();
    expect(paragraph1.selections.length, 1);
    expect(paragraph1.selections[0].start, 2);
    expect(paragraph1.selections[0].end, 7);
    expect(content, isNotNull);
    expect(content!.plainText, 'w are');

    for (int i = 0; i < 5; i += 1) {
      await sendKeyCombination(tester,
          const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true));
      await tester.pump();
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 8 + i);
      expect(content, isNotNull);
    }
    expect(content, isNotNull);
    expect(content!.plainText, 'w are you?');

    for (int i = 0; i < 5; i += 1) {
      await sendKeyCombination(tester,
          const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true));
      await tester.pump();
      expect(paragraph1.selections.length, 1);
      expect(paragraph1.selections[0].start, 2);
      expect(paragraph1.selections[0].end, 11 - i);
      expect(content, isNotNull);
    }
    expect(content, isNotNull);
    expect(content!.plainText, 'w are');

    await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true));
    await tester.pump();
    expect(paragraph1.selections.length, 1);
    expect(paragraph1.selections[0].start, 2);
    expect(paragraph1.selections[0].end, 12);
    expect(paragraph2.selections.length, 1);
    expect(paragraph2.selections[0].start, 0);
    expect(paragraph2.selections[0].end, 8);
    expect(content, isNotNull);
    expect(content!.plainText, 'w are you?Good, an');

    await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true));
    await tester.pump();
    expect(paragraph1.selections.length, 1);
    expect(paragraph1.selections[0].start, 2);
    expect(paragraph1.selections[0].end, 12);
    expect(paragraph2.selections.length, 1);
    expect(paragraph2.selections[0].start, 0);
    expect(paragraph2.selections[0].end, 14);
    expect(paragraph3.selections.length, 1);
    expect(paragraph3.selections[0].start, 0);
    expect(paragraph3.selections[0].end, 9);
    expect(content, isNotNull);
    expect(content!.plainText, 'w are you?Good, and you?Fine, tha');

    await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true));
    await tester.pump();
    expect(paragraph1.selections.length, 1);
    expect(paragraph1.selections[0].start, 2);
    expect(paragraph1.selections[0].end, 12);
    expect(paragraph2.selections.length, 1);
    expect(paragraph2.selections[0].start, 0);
    expect(paragraph2.selections[0].end, 14);
    expect(paragraph3.selections.length, 1);
    expect(paragraph3.selections[0].start, 0);
    expect(paragraph3.selections[0].end, 16);
    expect(content, isNotNull);
    expect(content!.plainText, 'w are you?Good, and you?Fine, thank you.');

    await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true));
    await tester.pump();
    expect(paragraph1.selections.length, 1);
    expect(paragraph1.selections[0].start, 2);
    expect(paragraph1.selections[0].end, 12);
    expect(paragraph2.selections.length, 1);
    expect(paragraph2.selections[0].start, 0);
    expect(paragraph2.selections[0].end, 8);
    expect(paragraph3.selections.length, 0);
    expect(content, isNotNull);
    expect(content!.plainText, 'w are you?Good, an');

    await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true));
    await tester.pump();
    expect(paragraph1.selections.length, 1);
    expect(paragraph1.selections[0].start, 2);
    expect(paragraph1.selections[0].end, 7);
    expect(paragraph2.selections.length, 0);
    expect(paragraph3.selections.length, 0);
    expect(content, isNotNull);
    expect(content!.plainText, 'w are');

    await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true));
    await tester.pump();
    expect(paragraph1.selections.length, 1);
    expect(paragraph1.selections[0].start, 0);
    expect(paragraph1.selections[0].end, 2);
    expect(paragraph2.selections.length, 0);
    expect(paragraph3.selections.length, 0);
    expect(content, isNotNull);
    expect(content!.plainText, 'Ho');
  });

  group('BrowserContextMenu', () {
    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.contextMenu, (MethodCall call) {
        // Just complete successfully, so that BrowserContextMenu thinks that
        // the engine successfully received its call.
        return Future<void>.value();
      });
      await BrowserContextMenu.disableContextMenu();
    });

    tearDown(() async {
      await BrowserContextMenu.enableContextMenu();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.contextMenu, null);
    });

    testWidgets('web can show flutter context menu when the browser context menu is disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectableRegion(
            onSelectionChanged: (SelectedContent? selectedContent) {},
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: const Center(
              child: Text('How are you'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final SelectableRegionState state =
          tester.state<SelectableRegionState>(find.byType(SelectableRegion));
      expect(find.text('Copy'), findsNothing);

      state.selectAll(SelectionChangedCause.toolbar);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);

      state.hideToolbar();
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsNothing);
    },
      skip: !kIsWeb, // [intended]
    );
  });

  testWidgets('Multiple selectables on a single line should be in screen order', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/127942.
    final UniqueKey outerText = UniqueKey();
    const TextStyle textStyle = TextStyle(fontSize: 10);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectableRegion(
          focusNode: FocusNode(),
          selectionControls: materialTextSelectionControls,
          child: Scaffold(
            body: Center(
              child: Text.rich(
                const TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: 'Hello my name is ', style: textStyle),
                    WidgetSpan(
                      child: Text('Dash', style: textStyle),
                      alignment: PlaceholderAlignment.middle,
                    ),
                    TextSpan(text: '.', style: textStyle),
                  ],
                ),
                key: outerText,
              ),
            ),
          ),
        ),
      ),
    );
    final RenderParagraph paragraph1 = tester.renderObject<RenderParagraph>(find.descendant(of: find.byKey(outerText), matching: find.byType(RichText)).first);
    final TestGesture gesture = await tester.startGesture(textOffsetToPosition(paragraph1, 0), kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.up();

    // Select all.
    await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyA, control: true));

    // keyboard copy.
    await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyC, control: true));

    final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
    expect(clipboardData['text'], 'Hello my name is Dash.');
  });
}

class SelectionSpy extends LeafRenderObjectWidget {
  const SelectionSpy({
    super.key,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSelectionSpy(
      SelectionContainer.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) { }
}

class RenderSelectionSpy extends RenderProxyBox
    with Selectable, SelectionRegistrant {
  RenderSelectionSpy(
      SelectionRegistrar? registrar,
      ) {
    this.registrar = registrar;
  }

  final Set<VoidCallback> listeners = <VoidCallback>{};
  List<SelectionEvent> events = <SelectionEvent>[];

  @override
  Size get size => _size;
  Size _size = Size.zero;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _size = Size(constraints.maxWidth, constraints.maxHeight);
    return _size;
  }

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    events.add(event);
    return SelectionResult.end;
  }

  @override
  SelectedContent? getSelectedContent() {
    return const SelectedContent(plainText: 'content');
  }

  @override
  final SelectionGeometry value = const SelectionGeometry(
    hasContent: true,
    status: SelectionStatus.uncollapsed,
    startSelectionPoint: SelectionPoint(
      localPosition: Offset.zero,
      lineHeight: 0.0,
      handleType: TextSelectionHandleType.left,
    ),
    endSelectionPoint: SelectionPoint(
      localPosition: Offset.zero,
      lineHeight: 0.0,
      handleType: TextSelectionHandleType.left,
    ),
  );

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) { }
}

class SelectAllWidget extends SingleChildRenderObjectWidget {
  const SelectAllWidget({
    super.key,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSelectAll(
      SelectionContainer.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) { }
}

class RenderSelectAll extends RenderProxyBox
    with Selectable, SelectionRegistrant {
  RenderSelectAll(
    SelectionRegistrar? registrar,
  ) {
    this.registrar = registrar;
  }

  final Set<VoidCallback> listeners = <VoidCallback>{};
  LayerLink? startHandle;
  LayerLink? endHandle;

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    value = SelectionGeometry(
      hasContent: true,
      status: SelectionStatus.uncollapsed,
      startSelectionPoint: SelectionPoint(
        localPosition: Offset(0, size.height),
        lineHeight: 0.0,
        handleType: TextSelectionHandleType.left,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: Offset(size.width, size.height),
        lineHeight: 0.0,
        handleType: TextSelectionHandleType.left,
      ),
    );
    return SelectionResult.end;
  }

  @override
  SelectedContent? getSelectedContent() {
    return const SelectedContent(plainText: 'content');
  }

  @override
  SelectionGeometry get value => _value;
  SelectionGeometry _value = const SelectionGeometry(
    hasContent: true,
    status: SelectionStatus.uncollapsed,
    startSelectionPoint: SelectionPoint(
      localPosition: Offset.zero,
      lineHeight: 0.0,
      handleType: TextSelectionHandleType.left,
    ),
    endSelectionPoint: SelectionPoint(
      localPosition: Offset.zero,
      lineHeight: 0.0,
      handleType: TextSelectionHandleType.left,
    ),
  );
  set value(SelectionGeometry other) {
    if (other == _value) {
      return;
    }
    _value = other;
    for (final VoidCallback callback in listeners) {
      callback();
    }
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    this.startHandle = startHandle;
    this.endHandle = endHandle;
  }
}
