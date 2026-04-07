package com.example.my_compass

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.Surface
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import kotlin.math.roundToInt

class MyCompassPlugin : FlutterPlugin, EventChannel.StreamHandler, SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var windowManager: WindowManager? = null
    private var eventSink: EventChannel.EventSink? = null

    // Sensors
    private var rotationVectorSensor: Sensor? = null
    private var accelerometerSensor: Sensor? = null
    private var magneticFieldSensor: Sensor? = null

    // Fallback sensor data
    private val accelerometerReading = FloatArray(3)
    private val magnetometerReading = FloatArray(3)

    // Matrices / orientation
    private val rotationMatrix = FloatArray(9)
    private val remappedRotationMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)

    private var accuracy: Int = SensorManager.SENSOR_STATUS_UNRELIABLE
    private var useRotationVector = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        rotationVectorSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        accelerometerSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        magneticFieldSensor = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

        val eventChannel = EventChannel(binding.binaryMessenger, "my_compass/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopListening()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        startListening()
    }

    override fun onCancel(arguments: Any?) {
        stopListening()
        eventSink = null
    }

    private fun startListening() {
        stopListening()

        useRotationVector = rotationVectorSensor != null

        if (useRotationVector) {
            rotationVectorSensor?.also { sensor ->
                sensorManager.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME
                )
            }
        } else {
            accelerometerSensor?.also { sensor ->
                sensorManager.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME
                )
            }
            magneticFieldSensor?.also { sensor ->
                sensorManager.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME
                )
            }
        }
    }

    private fun stopListening() {
        sensorManager.unregisterListener(this)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        when (sensor?.type) {
            Sensor.TYPE_MAGNETIC_FIELD,
            Sensor.TYPE_ROTATION_VECTOR -> {
                this.accuracy = accuracy
            }
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                if (useRotationVector) {
                    SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
                    updateOrientationAnglesFromMatrix(rotationMatrix)
                }
            }

            Sensor.TYPE_ACCELEROMETER -> {
                if (!useRotationVector) {
                    System.arraycopy(
                        event.values,
                        0,
                        accelerometerReading,
                        0,
                        accelerometerReading.size
                    )
                    updateOrientationAnglesFallback()
                }
            }

            Sensor.TYPE_MAGNETIC_FIELD -> {
                if (!useRotationVector) {
                    System.arraycopy(
                        event.values,
                        0,
                        magnetometerReading,
                        0,
                        magnetometerReading.size
                    )
                    updateOrientationAnglesFallback()
                }
            }
        }
    }

    private fun updateOrientationAnglesFallback() {
        val success = SensorManager.getRotationMatrix(
            rotationMatrix,
            null,
            accelerometerReading,
            magnetometerReading
        )

        if (success) {
            updateOrientationAnglesFromMatrix(rotationMatrix)
        }
    }

    private fun updateOrientationAnglesFromMatrix(sourceMatrix: FloatArray) {
        val rotation = getDisplayRotation()

        val (axisX, axisY) = when (rotation) {
            Surface.ROTATION_90 -> Pair(SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X)
            Surface.ROTATION_180 -> Pair(SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y)
            Surface.ROTATION_270 -> Pair(SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X)
            else -> Pair(SensorManager.AXIS_X, SensorManager.AXIS_Y)
        }

        SensorManager.remapCoordinateSystem(
            sourceMatrix,
            axisX,
            axisY,
            remappedRotationMatrix
        )

        SensorManager.getOrientation(remappedRotationMatrix, orientationAngles)

        val azimuthRad = orientationAngles[0].toDouble()
        val azimuthDeg = Math.toDegrees(azimuthRad)

        val heading = ((azimuthDeg + 360.0) % 360.0)

        eventSink?.success(listOf(heading, accuracy.toDouble()))
    }

    @Suppress("DEPRECATION")
    private fun getDisplayRotation(): Int {
        return windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
    }
}
