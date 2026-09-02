package com.example.gps_info

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.GeomagneticField
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.location.OnNmeaMessageListener
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.PluginRegistry
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class GpsInfoPlugin : FlutterPlugin, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val TAG = "GpsInfoPlugin"
    }

    private var activity: Activity? = null
    private lateinit var locationManager: LocationManager
    private var eventSink: EventChannel.EventSink? = null
    private val GPS_DATA_CHANNEL_NAME = "com.example.gps_info/gps_data_stream"
    private val LOCATION_PERMISSION_REQUEST_CODE = 34

    private var satellitesUsed = 0
    private var satellitesInView = 0
    private var lastLocation: Location? = null
    private var mslAltitude: Double? = null
    private var magneticDeclination: Float? = null
    private var updateInterval: Long = 1000L

    private var isListening = false
    private var lastSentTime: Long = 0L

    override fun onAttachedToEngine(
        flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    ) {
        println("GpsInfoPlugin: onAttachedToEngine")
        val eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            GPS_DATA_CHANNEL_NAME
        )
        locationManager = flutterPluginBinding.applicationContext
            .getSystemService(Context.LOCATION_SERVICE) as LocationManager

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                println("GpsInfoPlugin: onListen called")
                eventSink = events
                if (arguments is Int) {
                    updateInterval = arguments.toLong() * 1000L
                    println("GpsInfoPlugin: updateInterval set to $updateInterval ms")
                }
                startGpsListener()
            }

            override fun onCancel(arguments: Any?) {
                println("GpsInfoPlugin: onCancel called")
                stopGpsListener()
                eventSink = null
            }
        })
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        println("GpsInfoPlugin: onAttachedToActivity")
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        println("GpsInfoPlugin: onDetachedFromActivity")
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(
        binding: ActivityPluginBinding
    ) {
        println("GpsInfoPlugin: onReattachedToActivityForConfigChanges")
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        println("GpsInfoPlugin: onDetachedFromActivityForConfigChanges")
        onDetachedFromActivity()
    }

    private fun hasLocationPermission(): Boolean {
        return activity?.let {
            ContextCompat.checkSelfPermission(
                it,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } ?: false
    }

    private fun requestLocationPermission() {
        println("GpsInfoPlugin: requestLocationPermission")
        activity?.let {
            ActivityCompat.requestPermissions(
                it,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                LOCATION_PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        println("GpsInfoPlugin: onRequestPermissionsResult requestCode=$requestCode")
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            ) {
                println("GpsInfoPlugin: Location permission granted")
                startGpsListener()
                return true
            } else {
                println("GpsInfoPlugin ERROR: Location permission denied")
                eventSink?.error(
                    "PERMISSION_DENIED",
                    "Location permission not granted.",
                    null
                )
            }
        }
        return false
    }

private fun sendDataUpdate() {
    // Проверяем, существует ли подписчик на события (eventSink).
    // Если eventSink равен null, значит, Flutter-часть не слушает обновления,
    // и мы выходим из функции, чтобы не выполнять лишнюю работу.
    if (eventSink == null) return

    // Получаем текущее системное время в миллисекундах.
    // Это используется для ограничения частоты отправки данных.
    val now = System.currentTimeMillis()

    // Проверяем, прошло ли достаточно времени с момента последней отправки.
    // `updateInterval` - это минимальный интервал между обновлениями (в мс).
    // Если времени прошло меньше, чем `updateInterval`, выходим из функции.
    // Это предотвращает слишком частую отправку данных.
    if (now - lastSentTime < updateInterval) {
        return
    }
    // Обновляем время последней отправки на текущее.
    lastSentTime = now

    // Создаем HashMap для хранения данных, которые будут отправлены во Flutter.
    val data = HashMap<String, Any?>()

    // Добавляем данные о спутниках.
    // Эти переменные (satellitesUsed, satellitesInView) обновляются в другом месте
    // (в gnssStatusCallback).
    data["satellitesUsed"] = satellitesUsed
    data["satellitesInView"] = satellitesInView
    // Добавляем временную метку
    data["time"] = now
    var gpsLatency: Long? = null

    // Создаем форматер для времени, чтобы выводить его в лог в читаемом виде.
    val sdf = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.getDefault())
    val formattedAppTime = sdf.format(Date(now))
    var formattedGpsTime = "N/A" // Значение по умолчанию, если данных GPS еще нет

    // ШАГ 2: Использование сохраненных данных.
    // `lastLocation` — это переменная, в которую мы сохранили данные от GPS на ШАГЕ 1.
    // Конструкция `?.let` безопасно проверяет, что `lastLocation` не пуста.
    // Внутри этого блока `lastLocation` для удобства называется `loc`.
    lastLocation?.let { loc ->
        // Добавляем в `data` основные GPS-параметры из объекта `location`.
        data["latitude"] = loc.latitude
        data["longitude"] = loc.longitude
        data["accuracy"] = loc.accuracy
        data["speed"] = loc.speed
        data["altitude"] = loc.altitude // Высота над эллипсоидом WGS84

        // Проверяем, есть ли данные о курсе (bearing).
        // Если есть, добавляем их. Если нет, добавляем null.
        data["gpsBearing"] = if (loc.hasBearing()) {
            loc.bearing.toDouble()
        } else {
            null
        }

        // Вычисляем задержку GPS.
        // Здесь мы используем `loc.time` — это и есть то самое время от GPS,
        // которое система передала нам на ШАГЕ 1.
        gpsLatency = now - loc.time
        // Также форматируем время GPS для лога.
        formattedGpsTime = sdf.format(Date(loc.time))

        // Вычисляем магнитное склонение.
        // Это разница между истинным севером и магнитным севером в данной точке.
        val geoField = GeomagneticField(
            loc.latitude.toFloat(),
            loc.longitude.toFloat(),
            loc.altitude.toFloat(),
            now
        )
        magneticDeclination = geoField.declination
        data["magneticDeclination"] = magneticDeclination
    }

    // Проверяем, есть ли у нас данные о высоте над уровнем моря (mslAltitude).
    // Эти данные получаются из NMEA-сообщений. Если они есть, добавляем их в `data`.
    mslAltitude?.let {
        data["msl_altitude"] = it
    }

    // Выводим отладочное сообщение в лог с форматированным временем и координатами.
    println("GpsInfoPlugin: Update -> AppTime: $formattedAppTime | GPSTime: $formattedGpsTime | Latency: ${gpsLatency ?: "N/A"}ms | Coords: ${data["latitude"] ?: "N/A"}, ${data["longitude"] ?: "N/A"}")

    // Отправляем данные во Flutter.
    // `activity?.runOnUiThread` гарантирует, что отправка будет выполнена
    // в основном (UI) потоке приложения, что является требованием для
    // взаимодействия с Flutter EventChannel.
    activity?.runOnUiThread {
        eventSink?.success(data)
    }
}

    private val locationListener = object : LocationListener {
        // ШАГ 1: Получение данных от системы.
        // Этот метод вызывается системой Android каждый раз, когда GPS-чип получает новые координаты.
        // `location` — это готовый объект от системы. Он содержит широту, долготу и, что важно,
        // `location.time` — точное время, когда спутник зафиксировал эту координату.
        override fun onLocationChanged(location: Location) {
            // Мы сохраняем полученный от системы объект `location` в нашу переменную `lastLocation`,
            // чтобы использовать его позже.
            lastLocation = location
            sendDataUpdate()
        }
        override fun onStatusChanged(
            provider: String?, status: Int, extras: Bundle?
        ) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    private val nmeaListener =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            OnNmeaMessageListener { message, _ ->
                if (message.startsWith("\$GPGGA") ||
                    message.startsWith("\$GNGGA")
                ) {
                    val parts = message.split(",")
                    if (parts.size > 9 && parts[9].isNotEmpty()) {
                        try {
                            mslAltitude = parts[9].toDouble()
                        } catch (e: NumberFormatException) {
                            // ignore
                        }
                    }
                }
            }
        } else null

    private val gnssStatusCallback =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            object : GnssStatus.Callback() {
                override fun onSatelliteStatusChanged(status: GnssStatus) {
                    satellitesUsed = (0 until status.satelliteCount)
                        .count { status.usedInFix(it) }
                    satellitesInView = status.satelliteCount
                    sendDataUpdate()
                }
            }
        } else null

    @Suppress("deprecation")
    private fun startGpsListener() {
        println("GpsInfoPlugin: startGpsListener isListening=$isListening")
        if (isListening) {
            println("GpsInfoPlugin: Already listening, skipping")
            return
        }

        if (activity == null) {
            println("GpsInfoPlugin ERROR: Activity is null")
            eventSink?.error(
                "NO_ACTIVITY",
                "Plugin is not attached to an activity.",
                null
            )
            return
        }

        if (!hasLocationPermission()) {
            println("GpsInfoPlugin: No permission, requesting...")
            requestLocationPermission()
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                gnssStatusCallback?.let {
                    locationManager.registerGnssStatusCallback(it, null)
                }
                nmeaListener?.let {
                    locationManager.addNmeaListener(it, null)
                }
            }
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                updateInterval,
                0f,
                locationListener
            )
            isListening = true
            println("GpsInfoPlugin: GPS listener started successfully")
        } catch (e: SecurityException) {
            println("GpsInfoPlugin ERROR: SecurityException ${e.message}")
            eventSink?.error(
                "SECURITY_EXCEPTION",
                "Failed to register GPS listener.",
                e.message
            )
        }
    }

    @Suppress("deprecation")
    private fun stopGpsListener() {
        println("GpsInfoPlugin: stopGpsListener isListening=$isListening")
        if (!isListening) {
            println("GpsInfoPlugin: Not listening, skipping")
            return
        }

        try {
            locationManager.removeUpdates(locationListener)
            println("GpsInfoPlugin: removeUpdates called")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                gnssStatusCallback?.let {
                    locationManager.unregisterGnssStatusCallback(it)
                }
                nmeaListener?.let {
                    locationManager.removeNmeaListener(it)
                }
            }
            isListening = false
            println("GpsInfoPlugin: GPS listener stopped successfully")
        } catch (e: Exception) {
            println("GpsInfoPlugin ERROR: Error stopping GPS listener ${e.message}")
        }
    }

    override fun onDetachedFromEngine(
        binding: FlutterPlugin.FlutterPluginBinding
    ) {
        println("GpsInfoPlugin: onDetachedFromEngine")
        stopGpsListener()
        eventSink = null
    }
}
