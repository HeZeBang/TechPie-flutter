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
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    data.setUint32(4, 36 + subchunk2Size, Endian.little);
    buffer.setRange(8, 12, 'WAVE'.codeUnits);

    // 2. "fmt " sub-chunk
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    data.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    data.setUint16(20, 1, Endian.little); // AudioFormat (1 = Linear PCM)
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);

    // 3. "data" sub-chunk
    buffer.setRange(36, 40, 'data'.codeUnits);
    data.setUint32(40, subchunk2Size, Endian.little);

    // 4. Interleaved 16-bit signed PCM samples
    var offset = 44;
    for (var i = 0; i < numSamples; i++) {
      for (var ch = 0; ch < numChannels; ch++) {
        final floatSample = channels[ch][i].clamp(-1.0, 1.0);
        final int16 = (floatSample < 0 ? floatSample * 32768 : floatSample * 32767)
            .round()
            .clamp(-32768, 32767);
        data.setInt16(offset, int16, Endian.little);
        offset += 2;
      }
    }

    return buffer;
  }
}
