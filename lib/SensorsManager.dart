import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:environment_sensors/environment_sensors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:geolocator/geolocator.dart' as geoLoc;
import 'package:human_activity_detector/AudioManager.dart';
import 'package:human_activity_detector/HomePage.dart';
import 'package:human_activity_detector/Logger.dart';
import 'package:human_activity_detector/RingerManager.dart';
import 'package:human_activity_detector/SleepApiNotifier.dart';
import 'package:human_activity_detector/entity/SensorsMeasurementEntity.dart';
import 'package:phone_state/phone_state.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:record/record.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:synchronized/synchronized.dart';

class SensorsManager {
  static Timer? processingTimer;
  static Timer? requestPredictionTimer;

  static var accelerometerEventsLock = Lock();
  static List<AccelerometerEvent> accelerometerEvents = [];

  static var gyroscopeEventsLock = Lock();
  static List<GyroscopeEvent> gyroscopeEvents = [];

  static var magnetometerEventsLock = Lock();
  static List<MagnetometerEvent> magnetometerEvents = [];

  static var locationEventsLock = Lock();
  static List<geoLoc.Position> locationEvents = [];

  static var audioEventsLock = Lock();
  static List<Uint8List> audioEvents = [];

  static geoLoc.LocationSettings? locationSettings;

  static StreamSubscription<geoLoc.Position>? positionStream;
  static StreamSubscription<AccelerometerEvent>? accelerometerStreamSubscription;
  static StreamSubscription<GyroscopeEvent>? gyroscopeStreamSubscription;
  static StreamSubscription<MagnetometerEvent>? magnetometerStreamSubscription;

  static const int bufferSize = 4096;
  static const int sampleRate = 22050;
  static const hopLength = 1024;
  static const nMels = 34;
  static const fftSize = 512;
  static const mfcc = 13;

  static var battery = Battery();

  static PhoneState? phoneState;

  static List<double> ambientTempEvents = [];
  static List<double> humidityEvents = [];
  static List<double> lightEvents = [];
  static List<double> pressureEvents = [];
  static List<int> proximityEvents = [];

  static StreamSubscription<Activity>? _activityStreamSubscription;

  static final activityRecognition = FlutterActivityRecognition.instance;

  static final activityEvents = <Activity>[];

  static final List<SensorsMeasurementEntity> data = [];

  static final StreamController<Activity> activityStream = StreamController.broadcast();

  static void init() {
    processingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _processData();
    });
    requestPredictionTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      predict();
    });
    accelerometerStreamSubscription = accelerometerEventStream().listen(
          (AccelerometerEvent event) {
        accelerometerEventsLock.synchronized(() {
          accelerometerEvents.add(event);
        });
      },
      onError: (error) {
        // Logic to handle error
        // Needed for Android in case sensor is not available
      },
      cancelOnError: true,
    );
    gyroscopeStreamSubscription = gyroscopeEventStream().listen(
          (GyroscopeEvent event) {
        gyroscopeEventsLock.synchronized(() {
          gyroscopeEvents.add(event);
        });
      },
      onError: (error) {
        // Logic to handle error
        // Needed for Android in case sensor is not available
      },
      cancelOnError: true,
    );
    magnetometerStreamSubscription = magnetometerEventStream().listen(
          (MagnetometerEvent event) {
        magnetometerEventsLock.synchronized(() {
          magnetometerEvents.add(event);
        });
      },
      onError: (error) {
        // Logic to handle error
        // Needed for Android in case sensor is not available
      },
      cancelOnError: true,
    );

    PhoneState.stream.listen((event) {
      phoneState = event;
    });

    _initGeoLocator();
    _initAudio();
    AudioManager.startAudioRecording();
    _initEnvironmentalSensors();

    // Subscribe to activity recognition stream.
    _activityStreamSubscription = activityRecognition.activityStream.handleError(_handleError).listen(onActivityData, onError: onActivityError);

    //subscribe to the sleep api stream
    if(Platform.isAndroid) {
      SleepApiNotifier().init();
    }

  }


  static void _handleError(dynamic error) {
    Logger.logError(text: 'Catch Error >> $error');
  }

  static void onActivityError(Object error) {
    print('ERROR - $error');
  }

  static void stop() {
    processingTimer?.cancel();
    accelerometerStreamSubscription?.cancel();
    gyroscopeStreamSubscription?.cancel();
    magnetometerStreamSubscription?.cancel();
    positionStream?.cancel();
    clear();
    AudioManager.stopAudioRecording();
    _activityStreamSubscription?.cancel();
  }

  static void _processData() {
    var processedData = SensorsMeasurementEntity();
    // compute raw accelerometer magnitude stats
    _computeRawAccMagnitudeStats(processedData);
    // compute raw gyroscope magnitude stats
    _computeRawGyroMagnitudeStats(processedData);
    // compute raw magnetometer magnitude stats
    _computeRawMagnetMagnitudeStats(processedData);
    //compute location stats
    _computeLocationStats(processedData);
    //compute audio stats
    _computeAudioStats(processedData);
    //compute discrete stats
    _computeDiscreteStats(processedData);
    //compute low-frequency measurements
    _computeLowFrequencyMeasurements(processedData);
    //compute time of day features
    _computeTimeOfDayFeatures(processedData);
    
    //compute activity features
    _computeActivityFeatures(processedData);

    data.add(processedData);

    clear();
  }

  static void _computeRawAccMagnitudeStats(SensorsMeasurementEntity processedData) {
    var mean = 0.0;
    var std = 0.0;
    var moment3 = 0.0;
    var moment4 = 0.0;
    var percentile25 = 0.0;
    var percentile50 = 0.0;
    var percentile75 = 0.0;
    var meanX = 0.0;
    var meanY = 0.0;
    var meanZ = 0.0;
    var stdX = 0.0;
    var stdY = 0.0;
    var stdZ = 0.0;
    var roXy = 0.0;
    var roYz = 0.0;
    var roXz = 0.0;
    var app = [...accelerometerEvents];
    for (var event in app) {
      mean += event.x + event.y + event.z;
      std += (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean);
      moment3 += (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean);
      moment4 += (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean) *
          (event.x + event.y + event.z - mean);
      percentile25 += event.x + event.y + event.z;
      percentile50 += event.x + event.y + event.z;
      percentile75 += event.x + event.y + event.z;
      meanX += event.x;
      meanY += event.y;
      meanZ += event.z;
      stdX += (event.x - meanX) * (event.x - meanX);
      stdY += (event.y - meanY) * (event.y - meanY);
      stdZ += (event.z - meanZ) * (event.z - meanZ);
      roXy += (event.x - meanX) * (event.y - meanY);
      roYz += (event.y - meanY) * (event.z - meanZ);
      roXz += (event.x - meanX) * (event.z - meanZ);
    }
    mean /= accelerometerEvents.length;
    std /= accelerometerEvents.length;
    std = sqrt(std);
    moment3 /= accelerometerEvents.length;
    moment4 /= accelerometerEvents.length;
    percentile25 /= accelerometerEvents.length;
    percentile50 /= accelerometerEvents.length;
    percentile75 /= accelerometerEvents.length;


    processedData.rawAccMagnitudeStatsMean = mean;
    processedData.rawAccMagnitudeStatsStd = std;
    processedData.rawAccMagnitudeStatsMoment3 = moment3;
    processedData.rawAccMagnitudeStatsMoment4 = moment4;
    processedData.rawAccMagnitudeStatsPercentile25 = percentile25;
    processedData.rawAccMagnitudeStatsPercentile50 = percentile50;
    processedData.rawAccMagnitudeStatsPercentile75 = percentile75;
    processedData.rawAcc3dMeanX = meanX;
    processedData.rawAcc3dMeanY = meanY;
    processedData.rawAcc3dMeanZ = meanZ;
    processedData.rawAcc3dStdX = stdX;
    processedData.rawAcc3dStdY = stdY;
    processedData.rawAcc3dStdZ = stdZ;
    processedData.rawAcc3dRoXy = roXy;
    processedData.rawAcc3dRoYz = roYz;
    processedData.rawAcc3dRoXz = roXz;
  }

  static void _computeRawGyroMagnitudeStats(SensorsMeasurementEntity processedData) {
    var mean = 0.0;
    var std = 0.0;
    var moment3 = 0.0;
    var moment4 = 0.0;
    var percentile25 = 0.0;
    var percentile50 = 0.0;
    var percentile75 = 0.0;
    var meanX = 0.0;
    var meanY = 0.0;
    var meanZ = 0.0;
    var stdX = 0.0;
    var stdY = 0.0;
    var stdZ = 0.0;
    var roXy = 0.0;
    var roYz = 0.0;
    var roXz = 0.0;
    var app = [...gyroscopeEvents];
    for (var event in app) {
      mean += event.x + event.y + event.z;
      std += (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean);
      moment3 += (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean);
      moment4 += (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean) *
          (event.x + event.y + event.z - mean);
      percentile25 += event.x + event.y + event.z;
      percentile50 += event.x + event.y + event.z;
      percentile75 += event.x + event.y + event.z;
      meanX += event.x;
      meanY += event.y;
      meanZ += event.z;
      stdX += (event.x - meanX) * (event.x - meanX);
      stdY += (event.y - meanY) * (event.y - meanY);
      stdZ += (event.z - meanZ) * (event.z - meanZ);
      roXy += (event.x - meanX) * (event.y - meanY);
      roYz += (event.y - meanY) * (event.z - meanZ);
      roXz += (event.x - meanX) * (event.z - meanZ);
    }
    mean /= gyroscopeEvents.length;
    std /= gyroscopeEvents.length;
    std = sqrt(std);
    moment3 /= gyroscopeEvents.length;
    moment4 /= gyroscopeEvents.length;
    percentile25 /= gyroscopeEvents.length;
    percentile50 /= gyroscopeEvents.length;
    percentile75 /= gyroscopeEvents.length;

    processedData.procGyroMagnitudeStatsMean = mean;
    processedData.procGyroMagnitudeStatsStd = std;
    processedData.procGyroMagnitudeStatsMoment3 = moment3;
    processedData.procGyroMagnitudeStatsMoment4 = moment4;
    processedData.procGyroMagnitudeStatsPercentile25 = percentile25;
    processedData.procGyroMagnitudeStatsPercentile50 = percentile50;
    processedData.procGyroMagnitudeStatsPercentile75 = percentile75;
    processedData.procGyro3dMeanX = meanX;
    processedData.procGyro3dMeanY = meanY;
    processedData.procGyro3dMeanZ = meanZ;
    processedData.procGyro3dStdX = stdX;
    processedData.procGyro3dStdY = stdY;
    processedData.procGyro3dStdZ = stdZ;
    processedData.procGyro3dRoXy = roXy;
    processedData.procGyro3dRoYz = roYz;
    processedData.procGyro3dRoXz = roXz;
  }

  static void _computeRawMagnetMagnitudeStats(SensorsMeasurementEntity processedData) {
    var mean = 0.0;
    var std = 0.0;
    var moment3 = 0.0;
    var moment4 = 0.0;
    var percentile25 = 0.0;
    var percentile50 = 0.0;
    var percentile75 = 0.0;
    var meanX = 0.0;
    var meanY = 0.0;
    var meanZ = 0.0;
    var stdX = 0.0;
    var stdY = 0.0;
    var stdZ = 0.0;
    var roXy = 0.0;
    var roYz = 0.0;
    var roXz = 0.0;
    var app = [...magnetometerEvents];
    for (var event in app) {
      mean += event.x + event.y + event.z;
      std += (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean);
      moment3 += (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean);
      moment4 += (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean) * (event.x + event.y + event.z - mean) *
          (event.x + event.y + event.z - mean);
      percentile25 += event.x + event.y + event.z;
      percentile50 += event.x + event.y + event.z;
      percentile75 += event.x + event.y + event.z;
      meanX += event.x;
      meanY += event.y;
      meanZ += event.z;
      stdX += (event.x - meanX) * (event.x - meanX);
      stdY += (event.y - meanY) * (event.y - meanY);
      stdZ += (event.z - meanZ) * (event.z - meanZ);
      roXy += (event.x - meanX) * (event.y - meanY);
      roYz += (event.y - meanY) * (event.z - meanZ);
      roXz += (event.x - meanX) * (event.z - meanZ);
    }
    mean /= magnetometerEvents.length;
    std /= magnetometerEvents.length;
    std = sqrt(std);
    moment3 /= magnetometerEvents.length;
    moment4 /= magnetometerEvents.length;
    percentile25 /= magnetometerEvents.length;
    percentile50 /= magnetometerEvents.length;
    percentile75 /= magnetometerEvents.length;

    processedData.procGyroMagnitudeStatsMean = mean;
    processedData.procGyroMagnitudeStatsStd = std;
    processedData.procGyroMagnitudeStatsMoment3 = moment3;
    processedData.procGyroMagnitudeStatsMoment4 = moment4;
    processedData.procGyroMagnitudeStatsPercentile25 = percentile25;
    processedData.procGyroMagnitudeStatsPercentile50 = percentile50;
    processedData.procGyroMagnitudeStatsPercentile75 = percentile75;
    processedData.procGyro3dMeanX = meanX;
    processedData.procGyro3dMeanY = meanY;
    processedData.procGyro3dMeanZ = meanZ;
    processedData.procGyro3dStdX = stdX;
    processedData.procGyro3dStdY = stdY;
    processedData.procGyro3dStdZ = stdZ;
    processedData.procGyro3dRoXy = roXy;
    processedData.procGyro3dRoYz = roYz;
    processedData.procGyro3dRoXz = roXz;
  }

  static void _initGeoLocator() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = geoLoc.AndroidSettings(
          accuracy: geoLoc.LocationAccuracy.high,
          distanceFilter: 100,
          forceLocationManager: true,
          intervalDuration: const Duration(seconds: 10),
          //(Optional) Set foreground notification config to keep the app alive
          //when going to the background
          foregroundNotificationConfig: const geoLoc.ForegroundNotificationConfig(
            notificationText:
            "Example app will continue to receive your location even when you aren't using it",
            notificationTitle: "Running in Background",
            enableWakeLock: true,
          )
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = geoLoc.AppleSettings(
        accuracy: geoLoc.LocationAccuracy.high,
        activityType: geoLoc.ActivityType.fitness,
        distanceFilter: 100,
        pauseLocationUpdatesAutomatically: true,
        // Only set to true if our app will be started up in the background.
        showBackgroundLocationIndicator: false,
      );
    } else {
      locationSettings = const geoLoc.LocationSettings(
        accuracy: geoLoc.LocationAccuracy.high,
        distanceFilter: 100,
      );
    }
    positionStream = geoLoc.Geolocator.getPositionStream(locationSettings: locationSettings).listen(
            (geoLoc.Position? position) {
          print(position == null ? 'Unknown' : '${position.latitude.toString()}, ${position.longitude.toString()}');
          if (position != null) {
            locationEventsLock.synchronized(() {
              locationEvents.add(position);
            });
          }
        });
  }

  static void clear() {
    accelerometerEvents.clear();
    gyroscopeEvents.clear();
    magnetometerEvents.clear();
    locationEvents.clear();
    audioEvents.clear();
    ambientTempEvents.clear();
    humidityEvents.clear();
    lightEvents.clear();
    pressureEvents.clear();
    proximityEvents.clear();
    activityEvents.clear();
  }

  static void _computeLocationStats(SensorsMeasurementEntity processedData) {
    /* 138) Loc        location:num_valid_updates
    139) Loc        location:log_latitude_range
    140) Loc        location:log_longitude_range
    141) Loc        location:min_altitude
    142) Loc        location:max_altitude
    143) Loc        location:min_speed
    144) Loc        location:max_speed
    145) Loc        location:best_horizontal_accuracy
    146) Loc        location:best_vertical_accuracy
    147) Loc        location:diameter
    148) Loc        location:log_diameter
    149) Loc        location_quick_features:std_lat
    150) Loc        location_quick_features:std_long
    151) Loc        location_quick_features:lat_change
    152) Loc        location_quick_features:long_change
    153) Loc        location_quick_features:mean_abs_lat_deriv
    154) Loc        location_quick_features:mean_abs_long_deriv*/
    var numValidUpdates = 0;
    var minAltitude = 0.0;
    var maxAltitude = 0.0;
    var minSpeed = 0.0;
    var maxSpeed = 0.0;
    var bestHorizontalAccuracy = 0.0;
    var bestVerticalAccuracy = 0.0;
    var stdLat = 0.0;
    var stdLong = 0.0;
    var latChange = 0.0;
    var longChange = 0.0;
    var maxLat = 0.0;
    var minLat = double.maxFinite;
    var maxLon = 0.0;
    var minLon = double.maxFinite;
    var app = [...locationEvents];
    for (var event in app) {
      numValidUpdates++;
      minAltitude += event.altitude;
      maxAltitude += event.altitude;
      minSpeed += event.speed;
      maxSpeed += event.speed;
      bestHorizontalAccuracy += event.accuracy;
      bestVerticalAccuracy += event.altitudeAccuracy;

      stdLat += event.latitude;
      stdLong += event.longitude;
      if (event.latitude > maxLat) {
        maxLat = event.latitude;
      }
      if (event.latitude < minLat) {
        minLat = event.latitude;
      }
      if (event.longitude > maxLon) {
        maxLon = event.longitude;
      }
      if (event.longitude < minLon) {
        minLon = event.longitude;
      }
    }
    stdLat /= locationEvents.length;
    stdLat = sqrt(stdLat);
    stdLong /= locationEvents.length;
    stdLong = sqrt(stdLong);
    latChange = maxLat - minLat;
    longChange = maxLon - minLon;

    var logLatitudeRange = logCompression(maxLat - minLat);
    var logLongitudeRange = logCompression(maxLon - minLon);

    List<double> validLatitudes = [];
    List<double> validLongitudes = [];

    for (int i = 0; i < locationEvents.length; i++) {
      validLatitudes.add(locationEvents[i].latitude);
      validLongitudes.add(locationEvents[i].longitude);
    }

    double diameter = findLargestGeographicDistance(validLatitudes, validLongitudes);
    var epsilon = 0.001;
    double logDiameter = log(max(diameter, epsilon));
    processedData.locationNumValidUpdates = numValidUpdates;
    processedData.locationLogLatitudeRange = logLatitudeRange;
    processedData.locationLogLongitudeRange = logLongitudeRange;
    processedData.locationMinAltitude = minAltitude;
    processedData.locationMaxAltitude = maxAltitude;
    processedData.locationMinSpeed = minSpeed;
    processedData.locationMaxSpeed = maxSpeed;
    processedData.locationBestHorizontalAccuracy = bestHorizontalAccuracy;
    processedData.locationBestVerticalAccuracy = bestVerticalAccuracy;
    processedData.locationQuickFeaturesStdLat = stdLat;
    processedData.locationQuickFeaturesStdLong = stdLong;
    processedData.locationQuickFeaturesLatChange = latChange > 0.001 ? latChange : 0;
    processedData.locationQuickFeaturesLongChange = longChange > 0.001 ? longChange : 0;


    processedData.locationDiameter = diameter;
    processedData.locationLogDiameter = logDiameter;
  }


  static double findLargestGeographicDistance(List<double> latitudes, List<double> longitudes) {
    double deg2rad = pi / 180;
    List<double> rLatitudes = latitudes.map((lat) => deg2rad * lat).toList();
    List<double> rLongitudes = longitudes.map((lon) => deg2rad * lon).toList();

    double maxDist = 0.0;
    for (int ii = 0; ii < latitudes.length; ii++) {
      for (int jj = ii + 1; jj < latitudes.length; jj++) {
        double d = distanceBetweenGeographicPoints(
            rLatitudes[ii], rLongitudes[ii], rLatitudes[jj], rLongitudes[jj]);
        if (d > maxDist) {
          maxDist = d;
        }
      }
    }
    return maxDist;
  }

  static double distanceBetweenGeographicPoints(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Radius of the earth in km
    var dLat = deg2rad(lat2 - lat1); // deg2rad below
    var dLon = deg2rad(lon2 - lon1);
    var a = sin(dLat / 2) * sin(dLat / 2) +
        cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));
    var d = R * c; // Distance in km
    return d;
  }

  static double deg2rad(double deg) {
    return deg * (pi / 180);
  }

  static double logCompression(double val) {
    double epsilon = 0.001;
    double logVal = log(epsilon + val.abs()) - log(epsilon);
    double compVal = val.sign * logVal;
    return compVal;
  }

  static void _initAudio() async {
    Logger.logInfo(text:"Starting audio recording...");
    final record = AudioRecorder();
    if (await record.hasPermission()) {
      if (await record.isPaused()) {
        await record.resume();
      }
      final stream = await record.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          sampleRate: 16000,
        ),
      );
      stream.listen((event) {
        audioEventsLock.synchronized(() {
          audioEvents.add(event);
        });
      });
    }
  }

  static void _computeAudioStats(SensorsMeasurementEntity processedData) async {
    bool computed = await AudioManager.clearAudioRecordingData();
    if (!computed) {
      Logger.logError(text:"Failed to compute Mfcc features");
      return;
    }
    var f = await AudioManager.getMfccFile();
    if(f == null) {
      Logger.logError(text:"Failed to get Mfcc file");
      return;
    }
    if(!(await f.exists())) {
      Logger.logError(text:"Mfcc file does not exist");
      return;
    }
    //print f size in mb
    Logger.logInfo(text: "MFCC file size in MB: ${f.lengthSync() / (1024 * 1024)}");
    AudioManager.startAudioRecording();


    /*for (var event in audioEvents) {
      final byteData = event.buffer.asByteData();

      for (var offset = 0; offset < event.length; offset += 2) {
        signals[indexSignal] = byteData.getInt16(offset, Endian.little).toDouble();
        indexSignal++;

        if (indexSignal == bufferSize) {
          indexSignal = 0;

          final featureMatrix = await _flutterSoundProcessingPlugin.getFeatureMatrix(
            signals: signals,
            fftSize: fftSize,
            hopLength: hopLength,
            nMels: nMels,
            mfcc: mfcc,
            sampleRate: sampleRate,
          );

          print(featureMatrix?.toList());
          Map<int, double> means = {};
          Map<int, double> stds = {};
          for (int i = 0; i < mfcc; i++) {
            double mean = 0.0;
            double std = 0.0;
            for (int j = 0; j < nMels; j++) {
              mean += featureMatrix![j]
            }
            mean /= nMels;
            for (int j = 0; j < nMels; j++) {
              std += (featureMatrix[j][i] - mean) * (featureMatrix[j][i] - mean);
            }
            std /= nMels;
            std = sqrt(std);
            means[i] = mean;
            stds[i] = std;
          }
        }
      }
    }*/
  }

  static void _computeDiscreteStats(SensorsMeasurementEntity processedData) async {
    //app state
    processedData.discreteAppStateIsActive = HomePage.appState == AppLifecycleState.resumed;
    processedData.discreteAppStateIsBackground = HomePage.appState == AppLifecycleState.detached || HomePage.appState == AppLifecycleState.paused ||
        HomePage.appState == AppLifecycleState.hidden;
    processedData.discreteAppStateIsInactive = HomePage.appState == AppLifecycleState.inactive;
    processedData.discreteAppStateMissing = false; //todo understand why this exists

    //battery
    var batteryState = await battery.batteryState;
    processedData.discreteBatteryPluggedIsAc = batteryState == BatteryState.charging;
    processedData.discreteBatteryPluggedIsUsb = false; //todo how to do it in flutter
    processedData.discreteBatteryPluggedIsWireless = false; //todo how to do it in flutter
    processedData.discreteBatteryPluggedMissing = false; //todo understand why this exists
    processedData.discreteBatteryStateIsUnknown = batteryState == BatteryState.unknown;
    processedData.discreteBatteryStateIsUnplugged = batteryState == BatteryState.discharging; //todo check if this is correct
    processedData.discreteBatteryStateIsNotCharging = batteryState == BatteryState.connectedNotCharging;
    processedData.discreteBatteryStateIsDischarging = batteryState == BatteryState.discharging;
    processedData.discreteBatteryStateIsCharging = batteryState == BatteryState.charging;
    processedData.discreteBatteryStateIsFull = batteryState == BatteryState.full;
    processedData.discreteBatteryStateMissing = false; //todo understand why this exists

    //phone state
    processedData.discreteOnThePhoneIsTrue = phoneState != null && phoneState!.status != PhoneStateStatus.NOTHING;
    processedData.discreteOnThePhoneIsFalse = phoneState == null || phoneState!.status == PhoneStateStatus.NOTHING;
    processedData.discreteOnThePhoneMissing = false; //todo understand why this exists

    //ringer mode stats
    var ringerMode = await RingerManager.getRingerMode();
    processedData.discreteRingerModeIsNormal = ringerMode == RingerMode.NORMAL;
    processedData.discreteRingerModeIsSilentWithVibrate = ringerMode == RingerMode.VIBRATE;
    processedData.discreteRingerModeIsSilentNoVibrate = ringerMode == RingerMode.SILENT;
    processedData.discreteRingerModeMissing = ringerMode == null;

    //wifi status stats
    List<ConnectivityResult> connectivityStatus = await Connectivity().checkConnectivity();
    processedData.discreteWifiStatusIsNotReachable = connectivityStatus.contains(ConnectivityResult.none);
    processedData.discreteWifiStatusIsReachableViaWifi = connectivityStatus.contains(ConnectivityResult.wifi);
    processedData.discreteWifiStatusIsReachableViaWwan = connectivityStatus.contains(ConnectivityResult.mobile); //todo check if this mapping is correct
    processedData.discreteWifiStatusMissing = false;
  }

  static void _initEnvironmentalSensors() async {
    final environmentSensors = EnvironmentSensors();
    var tempAvailable = await environmentSensors.getSensorAvailable(SensorType.AmbientTemperature);
    if(tempAvailable) {
      environmentSensors.pressure.listen((ambTemp) {
        ambientTempEvents.add(ambTemp);
      });
    }
    var humidityAvailable = await environmentSensors.getSensorAvailable(SensorType.Humidity);
    if(humidityAvailable) {
      environmentSensors.humidity.listen((humidity) {
        humidityEvents.add(humidity);
      });
    }
    var lightAvailable = await environmentSensors.getSensorAvailable(SensorType.Light);
    if(lightAvailable) {
      environmentSensors.humidity.listen((light) {
        lightEvents.add(light);
      });
    }
    var pressureAvailable = await environmentSensors.getSensorAvailable(SensorType.Pressure);
    if(pressureAvailable) {
      environmentSensors.humidity.listen((pressure) {
        pressureEvents.add(pressure);
      });
    }
    ProximitySensor.events.listen((proximity) {
      proximityEvents.add(proximity);
    });
  }

  static void _computeLowFrequencyMeasurements(SensorsMeasurementEntity processedData) async {

    //battery level
    var level = await battery.batteryLevel;
    processedData.lfMeasurementsBatteryLevel = level.toDouble();

    //screen brightness
    var br = await ScreenBrightness().current;
    processedData.lfMeasurementsScreenBrightness = br;

    //environmental sensors
    processedData.lfMeasurementsTemperatureAmbient = ambientTempEvents.lastOrNull ?? 0.0;
    processedData.lfMeasurementsRelativeHumidity = humidityEvents.lastOrNull ?? 0.0;
    processedData.lfMeasurementsLight = lightEvents.lastOrNull ?? 0.0;
    processedData.lfMeasurementsPressure = pressureEvents.lastOrNull ?? 0.0;
    processedData.lfMeasurementsProximity = proximityEvents.lastOrNull?.toDouble() ?? 0.0;
    processedData.lfMeasurementsProximityCm = proximityEvents.lastOrNull?.toDouble() ?? 0.0; //todo check if this is correct and needed
  }

  static void _computeTimeOfDayFeatures(SensorsMeasurementEntity processedData) {
    var now = DateTime.now();
    var hour = now.hour;
    processedData.discreteTimeOfDayBetween0and6 = hour >= 0 && hour < 6;
    processedData.discreteTimeOfDayBetween3and9 = hour >= 3 && hour < 9;
    processedData.discreteTimeOfDayBetween6and12 = hour >= 6 && hour < 12;
    processedData.discreteTimeOfDayBetween9and15 = hour >= 9 && hour < 15;
    processedData.discreteTimeOfDayBetween12and18 = hour >= 12 && hour < 18;
    processedData.discreteTimeOfDayBetween15and21 = hour >= 15 && hour < 21;
    processedData.discreteTimeOfDayBetween18and24 = hour >= 18 && hour < 24;
    processedData.discreteTimeOfDayBetween21and3 = hour >= 21 || hour < 3;
  }

static Future<bool> predict() async {
    if (data.isEmpty) {
      print("No data to predict, skipping request to backend");
      return false;
    }
    bool result = await requestPredictionToBackend(data);
    data.clear();
    return result;
  }

  static Future<bool> requestPredictionToBackend(List<SensorsMeasurementEntity> sensorMeasurements) async {
    Dio dio = Dio();

    BaseOptions options = BaseOptions(
        connectTimeout: const Duration(milliseconds: 30000),
        receiveTimeout: const Duration(milliseconds: 30000),
        headers: {
          "Content-Type": "application/json",
        },
        contentType: ContentType.json.value,
        responseType: ResponseType.json);
    dio.options = options;
    Response res;

    try {
      res = await dio.post("https://loved-finally-trout.ngrok-free.app/predict", data:
        {
          "data": sensorMeasurements.map((e) => e.toJson()).toList()
        }
      );
    } catch (e) {
      print("Error while sending data to backend: $e");
      return false;
    }
    return true;
  }

   static void onActivityData(Activity activityEvent) {
    print(activityEvent);
    activityEvents.add(activityEvent);
    activityStream.add(activityEvent);
  }
  
  static void _computeActivityFeatures(SensorsMeasurementEntity processedData) {
    var activity = activityEvents.lastOrNull;
    if(activity != null) {
      processedData.activityType = activity.type;
      processedData.activityConfidence = activity.confidence;
    }

  }
  
}

