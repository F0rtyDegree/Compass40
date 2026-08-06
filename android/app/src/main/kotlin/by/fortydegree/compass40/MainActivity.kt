package by.fortydegree.compass40

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "by.fortydegree.compass40/intent"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("MainActivity", "onCreate called")
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d("MainActivity", "onNewIntent called")
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "configureFlutterEngine called")
    }

    private fun handleIntent(intent: Intent) {
        val action = intent.action
        Log.d("MainActivity", "handleIntent action: $action")
        if (action == null) return

        val engine = flutterEngine
        if (engine == null) {
            Log.d("MainActivity", "flutterEngine is null, cannot send to Dart")
            return
        }
        Log.d("MainActivity", "Sending intent to Dart channel")
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .invokeMethod(action, null)
    }
}