// Sonido corto generado en memoria: sin descargas, servicios ni dependencias.
// Los navegadores pueden bloquear la reproducción sin interacción previa.
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

String? _cachedWav;

String _wavUri() {
  if (_cachedWav != null) return _cachedWav!;
  const rate = 16000;
  const duration = 0.65;
  final samples = (rate * duration).round();
  final bytes = ByteData(44 + samples * 2);
  bytes.setUint32(0, 0x46464952, Endian.little); // RIFF
  bytes.setUint32(4, 36 + samples * 2, Endian.little);
  bytes.setUint32(8, 0x45564157, Endian.little); // WAVE
  bytes.setUint32(12, 0x20746d66, Endian.little); // fmt
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  bytes.setUint32(36, 0x61746164, Endian.little); // data
  bytes.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    final t = i / rate;
    final pulseTime = t < .27 ? t : (t >= .35 && t < .62 ? t - .35 : -1.0);
    var amplitude = 0.0;
    if (pulseTime >= 0 && pulseTime < .27) {
      final attack = math.min(1.0, pulseTime / .018);
      final release = math.min(1.0, (.27 - pulseTime) / .045);
      final frequency = t < .27 ? 570.0 : 445.0;
      final fundamental = math.sin(2 * math.pi * frequency * pulseTime);
      final harmonic = math.sin(2 * math.pi * frequency * 1.33 * pulseTime);
      amplitude = .32 * attack * release * (fundamental + .3 * harmonic);
    }
    bytes.setInt16(
        44 + i * 2,
        (amplitude * 32767).round().clamp(-32768, 32767).toInt(),
        Endian.little);
  }
  _cachedWav =
      'data:audio/wav;base64,${base64Encode(bytes.buffer.asUint8List())}';
  return _cachedWav!;
}

Future<bool> playArrivalClaxon() async {
  try {
    final audio = html.AudioElement(_wavUri())..preload = 'auto';
    audio.volume = 0.95;
    await audio.play();
    return true;
  } catch (_) {
    return false; // Siempre queda el aviso visible.
  }
}
