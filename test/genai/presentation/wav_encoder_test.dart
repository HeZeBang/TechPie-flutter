import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/audio/wav_encoder.dart';

void main() {
  group('WavEncoder', () {
    test('encodeFloat32 with empty input returns empty buffer', () {
      expect(
        WavEncoder.encodeFloat32(channels: [], sampleRate: 16000),
        isEmpty,
      );
      expect(
        WavEncoder.encodeFloat32(
          channels: [Float32List(0)],
          sampleRate: 16000,
        ),
        isEmpty,
      );
      expect(
        WavEncoder.encodeFloat32(
          channels: [Float32List(10)],
          sampleRate: 0,
        ),
        isEmpty,
      );
    });

    test('encodeFloat32 writes valid 16-bit mono PCM WAVE header and samples', () {
      final samples = Float32List.fromList([0.0, 1.0, -1.0, 0.5, -0.5]);
      final wav = WavEncoder.encodeFloat32(
        channels: [samples],
        sampleRate: 16000,
      );

      expect(wav.length, 44 + 5 * 2);
      final view = ByteData.view(wav.buffer);

      // RIFF header
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(view.getUint32(4, Endian.little), 36 + 10);
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');

      // fmt sub-chunk
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(view.getUint32(16, Endian.little), 16); // PCM chunk size
      expect(view.getUint16(20, Endian.little), 1); // Linear PCM
      expect(view.getUint16(22, Endian.little), 1); // 1 channel
      expect(view.getUint32(24, Endian.little), 16000); // 16kHz
      expect(view.getUint32(28, Endian.little), 32000); // Byte rate
      expect(view.getUint16(32, Endian.little), 2); // Block align
      expect(view.getUint16(34, Endian.little), 16); // 16 bits

      // data sub-chunk
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(view.getUint32(40, Endian.little), 10);

      // Samples
      expect(view.getInt16(44, Endian.little), 0);
      expect(view.getInt16(46, Endian.little), 32767);
      expect(view.getInt16(48, Endian.little), -32768);
      expect(view.getInt16(50, Endian.little), (0.5 * 32767).round());
      expect(view.getInt16(52, Endian.little), (-0.5 * 32768).round());
    });

    test('encodeFloat32 handles stereo interleaving correctly', () {
      final left = Float32List.fromList([1.0, -1.0]);
      final right = Float32List.fromList([0.0, 0.5]);
      final wav = WavEncoder.encodeFloat32(
        channels: [left, right],
        sampleRate: 44100,
      );

      expect(wav.length, 44 + 4 * 2);
      final view = ByteData.view(wav.buffer);
      expect(view.getUint16(22, Endian.little), 2); // 2 channels
      expect(view.getUint32(24, Endian.little), 44100);

      // Interleaved: L0, R0, L1, R1
      expect(view.getInt16(44, Endian.little), 32767);
      expect(view.getInt16(46, Endian.little), 0);
      expect(view.getInt16(48, Endian.little), -32768);
      expect(view.getInt16(50, Endian.little), (0.5 * 32767).round());
    });
  });
}
