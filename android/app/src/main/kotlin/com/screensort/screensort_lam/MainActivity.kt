package com.screensort.screensort_lam

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the one device question Dart cannot answer for itself: whether Android
 * classes this device as low on memory.
 *
 * `ActivityManager.isLowRamDevice()` is a framework property with no Flutter or
 * Dart binding, so it is asked for here and nowhere else. SIFT never computes a
 * verdict of its own — a hand-rolled reading of `ActivityManager.MemoryInfo`
 * would be a guess about a value the platform already publishes, and a guess
 * that wrongly blocks a capable phone is the expensive kind of wrong.
 *
 * The channel is deliberately the only thing this activity adds: it registers
 * no engine, starts no transfer, and reads no model weights.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // `notImplemented` for anything else, which Dart reads as a
                    // `MissingPluginException` and treats as "no answer" — the
                    // same outcome as a device that is not low on memory.
                    "isLowRamDevice" -> result.success(isLowRamDevice())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Android's own low-memory verdict for this device.
     *
     * It is a class property on the Kotlin side, exposed from the Java
     * `isLowRamDevice()` getter. The system service is requested per call
     * rather than cached across the activity's life: `getSystemService` on
     * `Context.ACTIVITY_SERVICE` returns a process-wide manager instance, so
     * caching it would save a lookup that costs nothing and would tie a
     * process-lifetime object to a shorter-lived activity.
     */
    private fun isLowRamDevice(): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return manager.isLowRamDevice
    }

    private companion object {
        const val CHANNEL = "screensort_lam/device_memory"
    }
}
