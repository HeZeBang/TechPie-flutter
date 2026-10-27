import 'package:flutter/material.dart';

/// Reuses the app icon for demo results without shipping a separate test fixture.
class GenAiDemoImage extends StatelessWidget {
  const GenAiDemoImage({super.key, this.fit = BoxFit.contain});

  static const assetName = 'assets/icon/icon.png';
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              assetName,
              fit: fit,
              semanticLabel: '本地演示占位图',
              errorBuilder: (_, __, ___) => const Center(
                child: Text('本地测试图片加载失败'),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .68),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  child: Text(
                    '本地测试图片',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
