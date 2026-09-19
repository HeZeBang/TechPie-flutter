import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/haptics.dart';

/// The two designed patterns pair a waveform with a sound. The waveform itself
/// is pinned by the dictionary test; this checks that the sound those two name is
/// a real, short, mono PCM file and that the length the dictionary declares is
/// the length the file has — the player keeps its session alive for that long.
void main() {
  final designed = AppHaptics.all.values
      .where((waveform) => waveform.soundAsset != null)
      .toList();

  test('the designed patterns carry a sound the assets actually hold', () {
    expect(
      designed.map((waveform) => waveform.id).toSet(),
      {'paymentSuccess', 'networkDisconnected'},
    );
    for (final waveform in designed) {
      final file = File(waveform.soundAsset!);
      expect(file.existsSync(), isTrue, reason: waveform.soundAsset!);
      final bytes = file.readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF', reason: waveform.id);
      expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE', reason: waveform.id);
      expect(data.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(data.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(data.getUint32(24, Endian.little), 44100, reason: '44.1 kHz');
      expect(data.getUint16(34, Endian.little), 16, reason: '16 bit');
      var offset = 12;
      var pcmBytes = 0;
      while (offset + 8 <= bytes.length) {
        final size = data.getUint32(offset + 4, Endian.little);
        if (ascii.decode(bytes.sublist(offset, offset + 4)) == 'data') {
          pcmBytes = size;
          break;
        }
        offset += 8 + size + size % 2;
      }
      final durationMs = pcmBytes / (44100 * 2) * 1000;
      expect(durationMs, inInclusiveRange(900, 1500), reason: waveform.id);
      expect(
        (waveform.soundDurationMs! - durationMs).abs(),
        lessThanOrEqualTo(2),
        reason: '${waveform.id} must declare the length the file has',
      );
      expect(
        waveform.durationMs,
        lessThan(durationMs),
        reason: '${waveform.id}: the vibration sits inside the sound, not past it',
      );
    }
  });
}
