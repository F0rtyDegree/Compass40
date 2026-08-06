package by.fortydegree.compass40

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val INTENT_CHANNEL = "by.fortydegree.compass40/intent"
    private val CONTROL_CHANNEL = "by.fortydegree.compass40/control"

    companion object {
        @JvmStatic
        var isMapScreenActive = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        setupControlChannel()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "configureFlutterEngine called")
    }

    private fun setupControlChannel() {
        flutterEngine?.let { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setMapActive" -> {
                            val active = call.arguments as? Boolean ?: false
                            isMapScreenActive = active
                            Log.d("MainActivity", "setMapActive: $active")
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (isMapScreenActive) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    Log.d("MainActivity", "Volume key intercepted, map active")
                    return true // предотвращаем изменение громкости
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun handleIntent(intent: Intent) {
        val action = intent.action ?: return
        flutterEngine?.let { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, INTENT_CHANNEL)
                .invokeMethod(action, null)
        }
    }
}