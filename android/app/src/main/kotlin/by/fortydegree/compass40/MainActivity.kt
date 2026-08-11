package by.fortydegree.compass40

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val INTENT_CHANNEL = "by.fortydegree.compass40/intent"
    private val CONTROL_CHANNEL = "by.fortydegree.compass40/control"
    private val NOTIFICATION_CHANNEL = "by.fortydegree.compass40/notification"
    private val NOTIFICATION_ID = 888

    companion object {
        @JvmStatic
        var isMapScreenActive = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        setupControlChannel()
        setupNotificationChannel()
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

    private fun setupNotificationChannel() {
        flutterEngine?.let { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "updateNotification" -> {
                            val title = call.argument<String>("title") ?: "Compass 40°"
                            val content = call.argument<String>("content") ?: "Компас активен"
                            updateForegroundNotification(title, content)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }

    private fun updateForegroundNotification(title: String, content: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val intent = Intent(this, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(this, "compass40_tracking_channel")
                .setContentTitle(title)
                .setContentText(content)
                .setSmallIcon(android.R.drawable.ic_menu_compass) // замените на свою иконку
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

            notificationManager.notify(NOTIFICATION_ID, notification)
            Log.d("MainActivity", "Notification updated: $title - $content")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to update notification", e)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (isMapScreenActive) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    Log.d("MainActivity", "Volume key intercepted, map active")
                    return true
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