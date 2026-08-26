package com.example.acoustic_twin

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "acoustic_twin/recorder")
            .setMethodCallHandler { call, result ->
                if (call.method == "recordSeconds") {
                    val secs = call.argument<Double>("seconds") ?: 6.0
                    Thread {
                        try {
                            val bytes = record(secs)
                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("REC", e.message, null) }
                        }
                    }.start()
                } else result.notImplemented()
            }
    }

    private fun record(seconds: Double): ByteArray {
        val sr = 16000
        val buf = AudioRecord.getMinBufferSize(sr, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, sr,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buf * 4)
        val total = (sr * seconds).toInt()
        val data = ShortArray(total)
        rec.startRecording()
        var off = 0
        while (off < total) {
            val n = rec.read(data, off, minOf(buf, total - off))
            if (n < 0) break
            off += n
        }
        rec.stop(); rec.release()
        val bytes = ByteArray(off * 2)
        for (i in 0 until off) {
            bytes[2 * i] = (data[i].toInt() and 0xFF).toByte()
            bytes[2 * i + 1] = ((data[i].toInt() shr 8) and 0xFF).toByte()
        }
        return bytes
    }
}
