package com.vrixora.tuktukcliente

import android.media.MediaPlayer
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var arrivalPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tuktuk/customer_arrival_claxon")
            .setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    arrivalPlayer?.release()
                    arrivalPlayer = null
                    val assetPath = FlutterInjector.instance().flutterLoader()
                        .getLookupKeyForAsset("assets/sounds/tuktuk-car-double-horn.wav")
                    val audioFile = File(cacheDir, "tuktuk-arrival-claxon.wav")
                    if (!audioFile.exists() || audioFile.length() == 0L) {
                        assets.open(assetPath).use { input ->
                            audioFile.outputStream().use { output -> input.copyTo(output) }
                        }
                    }
                    val player = MediaPlayer()
                    player.setDataSource(audioFile.absolutePath)
                    player.setOnCompletionListener { completed ->
                        if (arrivalPlayer === completed) arrivalPlayer = null
                        completed.release()
                    }
                    player.prepare()
                    player.start()
                    arrivalPlayer = player
                    result.success(true)
                } catch (_: Exception) {
                    arrivalPlayer?.release()
                    arrivalPlayer = null
                    result.success(false)
                }
            }
    }

    override fun onDestroy() {
        arrivalPlayer?.release()
        arrivalPlayer = null
        super.onDestroy()
    }
}
