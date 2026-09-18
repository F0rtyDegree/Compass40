import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math_64.dart';

class SensorFusionService {
  static final SensorFusionService _instance = SensorFusionService._internal();
  factory SensorFusionService() => _instance;
  SensorFusionService._internal();

  final _headingController = StreamController<double>.broadcast();
  Stream<double> get headingStream => _headingController.stream;

  StreamSubscription? _accelSubscription;
  StreamSubscription? _magnetSubscription;

  Vector3? _accelerometerValues;
  Vector3? _magnetometerValues;

  void start() {
    // Prevent multiple subscriptions
    if (_accelSubscription != null || _magnetSubscription != null) {
      stop();
    }

    _accelSubscription = userAccelerometerEventStream().listen((event) {
      _accelerometerValues = Vector3(event.x, event.y, event.z);
      _updateHeading();
    });

    _magnetSubscription = magnetometerEventStream().listen((event) {
      _magnetometerValues = Vector3(event.x, event.y, event.z);
      _updateHeading();
    });
  }

  void stop() {
    _accelSubscription?.cancel();
    _magnetSubscription?.cancel();
    _accelSubscription = null;
    _magnetSubscription = null;
  }

  void _updateHeading() {
    if (_accelerometerValues == null || _magnetometerValues == null) {
      return;
    }

    // This logic is a Dart implementation of Android's SensorManager.getRotationMatrix
    // and SensorManager.getOrientation to calculate the device's orientation.
    final rotationMatrix = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0];
    
    // We don't use the inclination matrix, but it's part of the original API.
    final inclinationMatrix = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0];

    bool success = SensorManager.getRotationMatrix(
      rotationMatrix,
      inclinationMatrix,
      _accelerometerValues!,
      _magnetometerValues!,
    );

    if (success) {
      final orientation = <double>[0, 0, 0];
      SensorManager.getOrientation(rotationMatrix, orientation);

      // orientation[0] contains the azimuth in radians.
      double azimuthRadians = orientation[0];
      double azimuthDegrees = degrees(azimuthRadians);

      // Normalize to 0-360
      if (azimuthDegrees < 0) {
        azimuthDegrees += 360;
      }

      _headingController.add(azimuthDegrees);
    }
  }

  void dispose() {
    stop();
    _headingController.close();
  }
}

// A helper class that mimics parts of Android's SensorManager to perform calculations.
class SensorManager {
  static bool getRotationMatrix(
    List<double> R,
    List<double> I, // Not used, but kept for compatibility with the concept.
    Vector3 gravity,
    Vector3 geomagnetic,
  ) {
    Vector3 a = gravity.normalized();
    Vector3 e = geomagnetic.normalized();
    Vector3 h = e.cross(a);
    
    // Check for the singularity case: when the device is close to parallel to the
    // magnetic field vector.
    if (h.length2 < 0.1) {
      return false; // Cannot compute rotation matrix.
    }

    h.normalize();
    a = h.cross(e);

    R[0] = h.x; R[1] = h.y; R[2] = h.z;
    R[3] = a.x; R[4] = a.y; R[5] = a.z;
    R[6] = e.x; R[7] = e.y; R[8] = e.z;

    return true;
  }

  static List<double> getOrientation(List<double> R, List<double> values) {
    // Azimuth (yaw)
    values[0] = atan2(R[1], R[4]);
    // Pitch
    values[1] = asin(-R[7]);
    // Roll
    values[2] = atan2(-R[6], R[8]);
    return values;
  }
}
