import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// ConstraintLayoutBuilder: A direct RenderObject-based alternative to LayoutBuilder.
///
/// Flutter's LayoutBuilder uses an Element with didChangeDependencies() that calls
/// markNeedsBuild(). When the element is reactivated from cache during a layout pass,
/// this causes "scheduleLayoutCallback during layout" crash.
///
/// This widget bypasses that by using a custom RenderObject that directly exposes
/// constraints to the build method without the problematic Element lifecycle hooks.
class ConstraintLayoutBuilder extends StatelessWidget {
  const ConstraintLayoutBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext context, BoxConstraints constraints)
      builder;

  @override
  Widget build(BuildContext context) {
    return _ConstraintLayoutBuilderWidget(builder: builder);
  }
}

/// Internal widget that uses custom RenderObject
class _ConstraintLayoutBuilderWidget extends RenderObjectWidget {
  const _ConstraintLayoutBuilderWidget({required this.builder});

  final Widget Function(BuildContext context, BoxConstraints constraints)
      builder;

  @override
  RenderObjectElement createElement() => _ConstraintLayoutBuilderElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderConstraintLayoutBuilder();
  }
}

/// Custom Element that does NOT call markNeedsBuild in didChangeDependencies
class _ConstraintLayoutBuilderElement extends RenderObjectElement {
  _ConstraintLayoutBuilderElement(_ConstraintLayoutBuilderWidget super.widget);

  Element? _child;

  @override
  _ConstraintLayoutBuilderWidget get widget =>
      super.widget as _ConstraintLayoutBuilderWidget;

  @override
  _RenderConstraintLayoutBuilder get renderObject =>
      super.renderObject as _RenderConstraintLayoutBuilder;

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null) {
      visitor(_child!);
    }
  }

  @override
  void forgetChild(Element child) {
    assert(child == _child);
    _child = null;
    super.forgetChild(child);
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject._updateCallback(_layoutCallback);
  }

  @override
  void update(RenderObjectWidget newWidget) {
    super.update(newWidget);
    renderObject._updateCallback(_layoutCallback);
    // Force rebuild with new widget's builder
    renderObject.markNeedsBuild();
  }

  @override
  void performRebuild() {
    // Just mark the render object as needing build
    renderObject.markNeedsBuild();
    super.performRebuild();
  }

  @override
  void unmount() {
    renderObject._updateCallback(null);
    super.unmount();
  }

  // CRITICAL: Do NOT override didChangeDependencies to call markNeedsBuild!
  // This is what causes the crash in standard LayoutBuilder.

  void _layoutCallback(BoxConstraints constraints) {
    // Rebuild whenever the render object requests it (markNeedsBuild) OR when
    // constraints change.
    //
    // The render object guarantees this callback only runs when either:
    // - constraints changed, or
    // - markNeedsBuild() was called.
    //
    // Therefore we must NOT ignore calls with identical constraints, otherwise
    // state changes in parents won't be reflected until constraints change.
    // Build the child widget with the new constraints
    owner!.buildScope(this, () {
      Widget built;
      try {
        built = widget.builder(this, constraints);
      } catch (e) {
        built = ErrorWidget(e);
      }
      _child = updateChild(_child, built, null);
    });
  }

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    final RenderObjectWithChildMixin<RenderObject> renderObject =
        this.renderObject;
    assert(slot == null);
    renderObject.child = child as RenderBox;
  }

  @override
  void moveRenderObjectChild(
      RenderObject child, Object? oldSlot, Object? newSlot) {
    assert(false);
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    final _RenderConstraintLayoutBuilder renderObject = this.renderObject;
    assert(renderObject.child == child);
    renderObject.child = null;
  }
}

/// Custom RenderObject that provides constraints to the builder
class _RenderConstraintLayoutBuilder extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  void Function(BoxConstraints)? _callback;
  bool _needsBuild = true;

  void _updateCallback(void Function(BoxConstraints)? callback) {
    if (_callback != callback) {
      _callback = callback;
      markNeedsLayout();
    }
  }

  void markNeedsBuild() {
    _needsBuild = true;
    markNeedsLayout();
  }

  BoxConstraints? _previousConstraints;

  void _rebuild(BoxConstraints constraints) {
    if (_needsBuild || _previousConstraints != constraints) {
      _needsBuild = false;
      _previousConstraints = constraints;
      invokeLayoutCallback((constraints) {
        _callback?.call(constraints as BoxConstraints);
      });
    }
  }

  @override
  void performLayout() {
    _rebuild(constraints);
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return child?.getMinIntrinsicWidth(height) ?? 0.0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return child?.getMaxIntrinsicWidth(height) ?? 0.0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return child?.getMinIntrinsicHeight(width) ?? 0.0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return child?.getMaxIntrinsicHeight(width) ?? 0.0;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return child?.hitTest(result, position: position) ?? false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      context.paintChild(child!, offset);
    }
  }
}

/// An even safer version that doesn't use LayoutBuilder at all for simple cases.
/// Uses MediaQuery for screen-size-based layouts instead.
///
/// Use this for responsive layouts that only need to know screen dimensions,
/// not actual parent constraints.
class MediaQueryLayoutBuilder extends StatelessWidget {
  const MediaQueryLayoutBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext context, BoxConstraints constraints)
      builder;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Create synthetic constraints based on MediaQuery
    final constraints = BoxConstraints(
      maxWidth: size.width,
      maxHeight: size.height,
      minWidth: 0,
      minHeight: 0,
    );
    return builder(context, constraints);
  }
}

/// Alias for backward compatibility
typedef SafeLayoutBuilder = ConstraintLayoutBuilder;

/// Alias for backward compatibility
typedef DeferredLayoutBuilder = ConstraintLayoutBuilder;
