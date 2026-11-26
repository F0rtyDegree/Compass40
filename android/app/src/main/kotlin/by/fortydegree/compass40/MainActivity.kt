package by.fortydegree.compass40

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
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
    private val SCREEN_CHANNEL = "by.fortydegree.compass40/screen"
    private val BROUTER_CHANNEL = "by.fortydegree.compass40/brouter"
    private val NOTIFICATION_ID = 888

    private var screenReceiver: android.content.BroadcastReceiver? = null

    companion object {
        @JvmStatic
        var isMapScreenActive = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        setupControlChannel()
        setupNotificationChannel()
        setupScreenReceiver()
        setupBRouterChannel()
    }

    private fun setupScreenReceiver() {
        screenReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(
                context: android.content.Context?,
                intent: android.content.Intent?
            ) {
                val action = intent?.action ?: return
                val state = when (action) {
                    android.content.Intent.ACTION_SCREEN_ON -> "on"
                    android.content.Intent.ACTION_SCREEN_OFF -> "off"
                    else -> return
                }
                flutterEngine?.let { engine ->
                    MethodChannel(
                        engine.dartExecutor.binaryMessenger,
                        SCREEN_CHANNEL
                    ).invokeMethod(state, null)
                }
            }
        }
        val filter = android.content.IntentFilter().apply {
            addAction(android.content.Intent.ACTION_SCREEN_ON)
            addAction(android.content.Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(screenReceiver, filter)
    }

    override fun onDestroy() {
        screenReceiver?.let { unregisterReceiver(it) }
        screenReceiver = null
        super.onDestroy()
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
                            val title = call.argument<String>("title") ?: "Режим - Компас"
                            val content = call.argument<String>("content") ?: ""
                            updateForegroundNotification(title, content)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }

    private fun setupBRouterChannel() {
        flutterEngine?.let { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, BROUTER_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isInstalled" -> {
                            result.success(isBRouterInstalled())
                        }
                        "getRoute" -> {
                            val lats = call.argument<List<Double>>("lats")?.toDoubleArray()
                            val lons = call.argument<List<Double>>("lons")?.toDoubleArray()
                            val profile = call.argument<String>("v") ?: "foot"
                            val remoteProfilePath = call.argument<String>("remoteProfilePath")
                            if (lats == null || lons == null || lats.size < 2 || lons.size < 2) {
                                result.success("Error: Некорректные координаты")
                                return@setMethodCallHandler
                            }
                            getBRouterRoute(lats, lons, profile, remoteProfilePath, result)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }

    private fun isBRouterInstalled(): Boolean {
        return try {
            packageManager.getPackageInfo("btools.routingapp", 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun getBRouterRoute(
        lats: DoubleArray,
        lons: DoubleArray,
        profile: String,
        remoteProfilePath: String?,
        result: MethodChannel.Result
    ) {
        val intent = Intent().apply {
            component = ComponentName("btools.routingapp", "btools.routingapp.BRouterService")
        }

        var replied = false
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                Thread {
                    var track: String? = null
                    try {
                        val params = Bundle().apply {
                            putDoubleArray("lats", lats)
                            putDoubleArray("lons", lons)
                            putString("trackFormat", "gpx")
                            putString("maxRunningTime", "15")
                            // Увеличиваем порог привязки к дороге с 250 м до 1000 м
                            putString("extraParams", "waypointCatchingRange=1000")

                            if (!remoteProfilePath.isNullOrBlank()) {
                                val file = java.io.File(remoteProfilePath)
                                if (!file.exists() || !file.canRead()) {
                                    track = "Error: Файл профиля не найден (${file.name})"
                                } else {
                                    putString("remoteProfile", file.readText(Charsets.UTF_8))
                                }
                            } else {
                                putString("v", profile)
                            }
                        }
                        if (track == null && service != null) {
                            val data = Parcel.obtain()
                            val reply = Parcel.obtain()
                            try {
                                data.writeInterfaceToken("btools.routingapp.IBRouterService")
                                data.writeInt(1)
                                params.writeToParcel(data, 0)
                                service.transact(IBinder.FIRST_CALL_TRANSACTION, data, reply, 0)
                                reply.readException()
                                track = reply.readString()
                            } finally {
                                reply.recycle()
                                data.recycle()
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "BRouter getTrackFromParams error", e)
                        track = "Error: ${e.message ?: "Ошибка вызова BRouter"}"
                    } finally {
                        try {
                            unbindService(this)
                        } catch (_: Exception) {
                        }
                    }
                    runOnUiThread {
                        if (!replied) {
                            replied = true
                            result.success(track ?: "Error: Пустой ответ BRouter")
                        }
                    }
                }.start()
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                if (!replied) {
                    replied = true
                    result.success("Error: Сервис BRouter отключился")
                }
            }
        }

        val bound = try {
            bindService(intent, connection, Context.BIND_AUTO_CREATE)
        } catch (e: Exception) {
            Log.e("MainActivity", "BRouter bindService failed", e)
            false
        }

        if (!bound) {
            try {
                unbindService(connection)
            } catch (_: Exception) {
            }
            if (!replied) {
                replied = true
                result.success("Error: Не удалось запустить сервис BRouter")
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
                .setSmallIcon(R.drawable.ic_bg_service_small)
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
        // Передаём extras во Flutter как Map<String, Any>.
        // Если extras нет — arguments = null, обрабатывается на стороне Dart.
        val args: Map<String, Any>? = intent.extras?.let { bundle ->
            bundle.keySet().associateWith { key ->
                bundle.get(key) as Any
            }
        }
        flutterEngine?.let { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, INTENT_CHANNEL)
                .invokeMethod(action, args)
        }
    }
}