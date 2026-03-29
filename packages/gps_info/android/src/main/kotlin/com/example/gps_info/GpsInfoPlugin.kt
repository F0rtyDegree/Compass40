
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

class GpsInfoPlugin : FlutterPlugin, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private var activity: Activity? = null
    private lateinit var locationManager: LocationManager
    private var eventSink: EventChannel.EventSink? = null
    private val GPS_DATA_CHANNEL_NAME = "com.example.gps_info/gps_data_stream"
    private val LOCATION_PERMISSION_REQUEST_CODE = 34

    // State holders
    private var satellitesUsed = 0
    private var satellitesInView = 0
    private var lastLocation: Location? = null
    private var mslAltitude: Double? = null
    private var magneticDeclination: Float? = null
    private var updateInterval: Long = 1000L

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, GPS_DATA_CHANNEL_NAME)
        locationManager = flutterPluginBinding.applicationContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                if (arguments is Int) {
                    updateInterval = arguments.toLong()
                }
                startGpsListener()
            }

            override fun onCancel(arguments: Any?) {
                stopGpsListener()
                eventSink = null
            }
        })
    }

    // region ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }
    // endregion

    private fun hasLocationPermission(): Boolean {
        return activity?.let {
            ContextCompat.checkSelfPermission(it, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        } ?: false
    }

    private fun requestLocationPermission() {
        activity?.let {
            ActivityCompat.requestPermissions(it, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), LOCATION_PERMISSION_REQUEST_CODE)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startGpsListener()
                return true
            } else {
                eventSink?.error("PERMISSION_DENIED", "Location permission not granted.", null)
            }
        }
        return false
    }

    // Combines all data and sends it to Flutter
    private fun sendDataUpdate() {
        if (eventSink == null) return

        val data = HashMap<String, Any?>()
        data["satellitesUsed"] = satellitesUsed
        data["satellitesInView"] = satellitesInView
        lastLocation?.let {
            data["latitude"] = it.latitude
            data["longitude"] = it.longitude
            data["accuracy"] = it.accuracy
            data["speed"] = it.speed
            data["altitude"] = it.altitude
            
            val geoField = GeomagneticField(
                it.latitude.toFloat(),
                it.longitude.toFloat(),
                it.altitude.toFloat(),
                System.currentTimeMillis()
            )
            magneticDeclination = geoField.declination
            data["magneticDeclination"] = magneticDeclination
        }
        mslAltitude?.let {
            data["msl_altitude"] = it
        }

        activity?.runOnUiThread {
            eventSink?.success(data)
        }
    }

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            lastLocation = location
            sendDataUpdate()
        }
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }
    
    private val nmeaListener = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        OnNmeaMessageListener { message, timestamp ->
            if (message.startsWith("\$GPGGA") || message.startsWith("\$GNGGA")) {
                val parts = message.split(",")
                if (parts.size > 9 && parts[9].isNotEmpty()) {
                    try {
                        mslAltitude = parts[9].toDouble()
                    } catch (e: NumberFormatException) {
                        // Log error or handle it
                    }
                }
            }
        }
    } else {
        null
    }


    private val gnssStatusCallback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(status: GnssStatus) {
                satellitesUsed = (0 until status.satelliteCount).count { status.usedInFix(it) }
                satellitesInView = status.satelliteCount
                sendDataUpdate()
            }
        }
    } else {
        null
    }

    @Suppress("deprecation")
    private fun startGpsListener() {
        if (activity == null) {
            eventSink?.error("NO_ACTIVITY", "Plugin is not attached to an activity.", null)
            return
        }

        if (!hasLocationPermission()) {
            requestLocationPermission()
            return
        }

        try {
             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                locationManager.registerGnssStatusCallback(gnssStatusCallback!!, null)
                if (nmeaListener != null) {
                    locationManager.addNmeaListener(nmeaListener, null)
                }
            }
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, updateInterval, 0f, locationListener)

        } catch (e: SecurityException) {
            eventSink?.error("SECURITY_EXCEPTION", "Failed to register GPS listener.", e.message)
        }
    }

    @Suppress("deprecation")
    private fun stopGpsListener() {
        if (hasLocationPermission()) {
            locationManager.removeUpdates(locationListener)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                locationManager.unregisterGnssStatusCallback(gnssStatusCallback!!)
                 if (nmeaListener != null) {
                    locationManager.removeNmeaListener(nmeaListener)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopGpsListener()
    }
}
