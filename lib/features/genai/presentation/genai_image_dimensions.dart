import 'package:flutter/material.dart';

/// Resolves the first decoded frame without retaining its image handle.
/// Notifications are deferred so cached streams cannot mutate a building tree.
class GenAiImageDimensions extends StatefulWidget {
  const GenAiImageDimensions({
    super.key,
    required this.image,
    required this.builder,
    this.onSize,
  });

  final ImageProvider<Object> image;
  final Widget Function(BuildContext, Size?) builder;
  final ValueChanged<Size?>? onSize;

  @override
  State<GenAiImageDimensions> createState() => _GenAiImageDimensionsState();
}

class _GenAiImageDimensionsState extends State<GenAiImageDimensions> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _size;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant GenAiImageDimensions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _size = null;
      _resolve();
    }
  }

  void _resolve() {
    _stop();
    final generation = ++_generation;
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    void complete(Size? size) {
      if (!mounted || generation != _generation) return;
      _stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _generation) return;
        if (_size != size) setState(() => _size = size);
        widget.onSize?.call(size);
      });
    }

    final listener = ImageStreamListener(
      (info, _) {
        final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
        info.dispose();
        complete(size);
      },
      onError: (Object error, StackTrace? stackTrace) => complete(null),
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _stop() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _size);
}
