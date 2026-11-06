import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

class MediaVolumeMenu extends StatelessWidget {
  const MediaVolumeMenu({super.key, required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
        stream: player.stream.volume,
        initialData: player.state.volume,
        builder: (context, snapshot) {
          final volume = snapshot.data ?? 100;
          return PopupMenuButton<int>(
            tooltip: '音量',
            position: PopupMenuPosition.over,
            offset: const Offset(0, -252),
            padding: EdgeInsets.zero,
            onSelected: (value) => unawaited(player.setVolume(value.toDouble())),
            itemBuilder: (context) => [
              for (final level in const [100, 75, 50, 25, 0])
                CheckedPopupMenuItem<int>(
                  value: level,
                  checked: volume == level,
                  child: Text('$level%'),
                ),
            ],
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(
                  volume == 0
                      ? Icons.volume_off
                      : volume < 50
                          ? Icons.volume_down
                          : Icons.volume_up,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          );
        },
      );
}
