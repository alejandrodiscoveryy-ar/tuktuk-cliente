// Claxon de vehiculo incluido en la WebApp: Mixkit SFX 719.
// El navegador puede requerir interaccion del usuario para reproducir.
import 'dart:html' as html;

html.AudioElement? _player;

Future<bool> playArrivalClaxon() async {
  try {
    if (_player == null) {
      _player = html.AudioElement(
        'assets/assets/sounds/tuktuk-car-double-horn.wav',
      )..preload = 'auto';
    }
    final audio = _player!;
    audio.volume = 1.0;
    audio.pause();
    try {
      audio.currentTime = 0;
    } catch (_) {
      // El recurso puede no estar listo en el primer intento.
    }
    await audio.play();
    return true;
  } catch (_) {
    return false;
  }
}
