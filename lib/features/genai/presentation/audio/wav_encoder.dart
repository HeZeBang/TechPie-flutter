import 'dart:typed_data';

/// Encodes uncompressed audio samples into standard 16-bit linear PCM RIFF/WAVE bytes.
final class WavEncoder {
  const WavEncoder._();

  /// Encodes multi-channel Float32 normalized audio samples ([-1.0, 1.0])
  /// into a standard 16-bit PCM RIFF/WAVE byte buffer.
  static Uint8List encodeFloat32({
    required List<Float32List> channels,
    required int sampleRate,
  }) {
    if (channels.isEmpty || channels.first.isEmpty || sampleRate <= 0) {
      return Uint8List(0);
    }

    final numChannels = channels.length;
    final numSamples = channels.first.length;
    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    final blockAlign = numChannels * bytesPerSample;
    final byteRate = sampleRate * blockAlign;
    final subchunk2Size = numSamples * blockAlign;
    final totalSize = 44 + subchunk2Size;

    final buffer = Uint8List(totalSize);
    final data = ByteData.view(buffer.buffer);

    // 1. "RIFF" chunk descriptor
    data.setUint8(0, 0x52); // 'R'
    data.setUint8(1, 0x49); // 'I'
    data.setUint8(2, 0x46); // 'F'
    data.setUint8(3, 0x46); // 'F'
    data.setUint32(4, 36 + subchunk2Size, Endian.little);
    data.setUint8(8, 0x57); // 'W'
    data.setUint8(9, 0x41); // 'A'
    data.setUint8(10, 0x56); // 'V'
    data.setUint8(11, 0x45); // 'E'

    // 2. "fmt " sub-chunk
    data.setUint8(12, 0x66); // 'f'
    data.setUint8(13, 0x6D); // 'm'
    data.setUint8(14, 0x74); // 't'
    data.setUint8(15, 0x20); // ' '
    data.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    data.setUint16(20, 1, Endian.little); // AudioFormat (1 = Linear PCM)
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);

    // 3. "data" sub-chunk
    data.setUint8(36, 0x64); // 'd'
    data.setUint8(37, 0x61); // 'a'
    data.setUint8(38, 0x74); // 't'
    data.setUint8(39, 0x61); // 'a'
    data.setUint32(40, subchunk2Size, Endian.little);

    // 4. Interleaved 16-bit signed PCM samples
    var offset = 44;
    for (var i = 0; i < numSamples; i++) {
      for (var ch = 0; ch < numChannels; ch++) {
        final floatSample = channels[ch][i].clamp(-1.0, 1.0);
        final int16 =
            (floatSample < 0 ? floatSample * 32768 : floatSample * 32767)
                .round()
                .clamp(-32768, 32767);
        data.setInt16(offset, int16, Endian.little);
        offset += 2;
      }
    }

    return buffer;
  }

  /// Encodes 16-bit linear PCM integer samples ([-32768, 32767])
  /// into a standard 16-bit PCM RIFF/WAVE byte buffer.
  static Uint8List encodePcm16({
    required List<int> samples,
    required int sampleRate,
    int numChannels = 1,
  }) {
    if (samples.isEmpty || sampleRate <= 0 || numChannels <= 0) {
      return Uint8List(0);
    }

    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    final blockAlign = numChannels * bytesPerSample;
    final byteRate = sampleRate * blockAlign;
    final subchunk2Size = samples.length * bytesPerSample;
    final totalSize = 44 + subchunk2Size;

    final buffer = Uint8List(totalSize);
    final data = ByteData.view(buffer.buffer);

    // "RIFF" header
    data.setUint8(0, 0x52);
    data.setUint8(1, 0x49);
    data.setUint8(2, 0x46);
    data.setUint8(3, 0x46);
    data.setUint32(4, 36 + subchunk2Size, Endian.little);
    data.setUint8(8, 0x57);
    data.setUint8(9, 0x41);
    data.setUint8(10, 0x56);
    data.setUint8(11, 0x45);

    // "fmt " chunk
    data.setUint8(12, 0x66);
    data.setUint8(13, 0x6D);
    data.setUint8(14, 0x74);
    data.setUint8(15, 0x20);
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);

    // "data" chunk
    data.setUint8(36, 0x64);
    data.setUint8(37, 0x61);
    data.setUint8(38, 0x74);
    data.setUint8(39, 0x61);
    data.setUint32(40, subchunk2Size, Endian.little);

    var offset = 44;
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i].clamp(-32768, 32767);
      data.setInt16(offset, s, Endian.little);
      offset += 2;
    }

    return buffer;
  }
}
