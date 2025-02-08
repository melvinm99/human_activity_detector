import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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

  static Activity? lastActivityEvent;

  static final List<SensorsMeasurementEntity> data = [];

  static final StreamController<Activity> activityStream = StreamController.broadcast();

  static final StreamController<PredictionEntity> predictionStream = StreamController.broadcast();

  static void init() {
    processingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _processData();
    });
    /*requestPredictionTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      predict();
    });*/
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
    lastActivityEvent = null;
    AudioManager.stopAudioRecording();
    _activityStreamSubscription?.cancel();
    requestPredictionTimer?.cancel();
  }

  static _processData() async {
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
    await _computeDiscreteStats(processedData);
    //compute low-frequency measurements
    _computeLowFrequencyMeasurements(processedData);
    //compute time of day features
    _computeTimeOfDayFeatures(processedData);
    
    //compute activity features
    _computeActivityFeatures(processedData);

    data.add(processedData);

    clear();

    predict();
  }

  static void _computeRawAccMagnitudeStats(SensorsMeasurementEntity processedData) {
    var app = [...accelerometerEvents];
    List<num> magnitudes = [];
    List<num> valuesX = [];
    List<num> valuesY = [];
    List<num> valuesZ = [];

    for (var event in app) {
      var sum = event.x + event.y + event.z;
      magnitudes.add(math.pow(sum, 2));
      valuesX.add(event.x);
      valuesY.add(event.y);
      valuesZ.add(event.z);
    }
    var magnitude = math.sqrt(magnitudes.reduce((a, b) => a + b)); //L2 norm
    var magnitudeX = valuesX.reduce((a, b) => a + b);
    var magnitudeY = valuesY.reduce((a, b) => a + b);
    var magnitudeZ = valuesZ.reduce((a, b) => a + b);

    var mean = magnitude / accelerometerEvents.length;
    var meanX = magnitudeX / accelerometerEvents.length;
    var meanY = magnitudeY / accelerometerEvents.length;
    var meanZ = magnitudeZ / accelerometerEvents.length;

    var std = standardDeviation(magnitudes);
    var stdX = standardDeviation(valuesX);
    var stdY = standardDeviation(valuesY);
    var stdZ = standardDeviation(valuesZ);
    var mom3 = moment3(magnitudes);
    var mom4 = moment4(magnitudes);
    var percentile25 = scoreAtPercentile(magnitudes, 0.25);
    var percentile50 = scoreAtPercentile(magnitudes, 0.5);
    var percentile75 = scoreAtPercentile(magnitudes, 0.75);
    processedData.rawAccMagnitudeStatsMean = mean;
    processedData.rawAccMagnitudeStatsStd = std;
    processedData.rawAccMagnitudeStatsMoment3 = mom3;
    processedData.rawAccMagnitudeStatsMoment4 = mom4;
    processedData.rawAccMagnitudeStatsPercentile25 = percentile25;
    processedData.rawAccMagnitudeStatsPercentile50 = percentile50;
    processedData.rawAccMagnitudeStatsPercentile75 = percentile75;
    processedData.rawAcc3dMeanX = meanX;
    processedData.rawAcc3dMeanY = meanY;
    processedData.rawAcc3dMeanZ = meanZ;
    processedData.rawAcc3dStdX = stdX;
    processedData.rawAcc3dStdY = stdY;
    processedData.rawAcc3dStdZ = stdZ;
    /*processedData.rawAcc3dRoXy = roXy;
    processedData.rawAcc3dRoYz = roYz;
    processedData.rawAcc3dRoXz = roXz;*/
  }

  static double moment3(List<num> magnitudes) {
    if (magnitudes.isEmpty) throw ArgumentError('Data cannot be empty');

    final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    final sumCubedDeviations = magnitudes
        .map((x) => math.pow(x - mean, 3))
        .reduce((a, b) => a + b);

    var mom3 = sumCubedDeviations / magnitudes.length;
    if (mom3 == 0) return 0;
    return mom3.sign * math.pow(mom3.abs(), 1/3);
  }

  static double moment4(List<num> magnitudes) {
    if (magnitudes.isEmpty) throw ArgumentError('Data cannot be empty');

    final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    final sumFourthDeviations = magnitudes
        .map((x) => math.pow(x - mean, 4))
        .reduce((a, b) => a + b);

    final fourthMoment = sumFourthDeviations / magnitudes.length;
    return math.pow(fourthMoment, 0.25) as double;
  }

  static double standardDeviation(List<num> magnitudes) {
    if (magnitudes.isEmpty) throw ArgumentError('Data cannot be empty');


    final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    final sumSquaredDiffs = magnitudes
        .map((x) => math.pow(x - mean, 2))
        .reduce((a, b) => a + b);

    final variance = sumSquaredDiffs / (data.length);
    return math.sqrt(variance);
  }

  static double scoreAtPercentile(List<num> data, num percentile) {
    if (data.isEmpty) throw ArgumentError('Data cannot be empty');

    final sorted = List<double>.from(data)..sort();
    final index = (sorted.length - 1) * percentile;
    final lower = index.floor();
    final fraction = index - lower;

    return (lower >= sorted.length - 1)
        ? sorted[lower]
        : sorted[lower] * (1 - fraction) + sorted[lower + 1] * fraction;
  }

  static void _computeRawGyroMagnitudeStats(SensorsMeasurementEntity processedData) {
    var app = [...gyroscopeEvents];
    List<num> magnitudes = [];
    List<num> valuesX = [];
    List<num> valuesY = [];
    List<num> valuesZ = [];

    for (var event in app) {
      var sum = event.x + event.y + event.z;
      magnitudes.add(math.pow(sum, 2));
      valuesX.add(event.x);
      valuesY.add(event.y);
      valuesZ.add(event.z);
    }
    var magnitude = math.sqrt(magnitudes.reduce((a, b) => a + b)); //L2 norm
    var magnitudeX = valuesX.reduce((a, b) => a + b);
    var magnitudeY = valuesY.reduce((a, b) => a + b);
    var magnitudeZ = valuesZ.reduce((a, b) => a + b);

    var mean = magnitude / accelerometerEvents.length;
    var meanX = magnitudeX / accelerometerEvents.length;
    var meanY = magnitudeY / accelerometerEvents.length;
    var meanZ = magnitudeZ / accelerometerEvents.length;

    var std = standardDeviation(magnitudes);
    var stdX = standardDeviation(valuesX);
    var stdY = standardDeviation(valuesY);
    var stdZ = standardDeviation(valuesZ);
    var mom3 = moment3(magnitudes);
    var mom4 = moment4(magnitudes);
    var percentile25 = scoreAtPercentile(magnitudes, 0.25);
    var percentile50 = scoreAtPercentile(magnitudes, 0.5);
    var percentile75 = scoreAtPercentile(magnitudes, 0.75);

    processedData.procGyroMagnitudeStatsMean = mean;
    processedData.procGyroMagnitudeStatsStd = std;
    processedData.procGyroMagnitudeStatsMoment3 = mom3;
    processedData.procGyroMagnitudeStatsMoment4 = mom4;
    processedData.procGyroMagnitudeStatsPercentile25 = percentile25;
    processedData.procGyroMagnitudeStatsPercentile50 = percentile50;
    processedData.procGyroMagnitudeStatsPercentile75 = percentile75;
    processedData.procGyro3dMeanX = meanX;
    processedData.procGyro3dMeanY = meanY;
    processedData.procGyro3dMeanZ = meanZ;
    processedData.procGyro3dStdX = stdX;
    processedData.procGyro3dStdY = stdY;
    processedData.procGyro3dStdZ = stdZ;
    /*processedData.procGyro3dRoXy = roXy;
    processedData.procGyro3dRoYz = roYz;
    processedData.procGyro3dRoXz = roXz;*/
  }

  static void _computeRawMagnetMagnitudeStats(SensorsMeasurementEntity processedData) {
    var app = [...magnetometerEvents];
    List<num> magnitudes = [];
    List<num> valuesX = [];
    List<num> valuesY = [];
    List<num> valuesZ = [];

    for (var event in app) {
      var sum = event.x + event.y + event.z;
      magnitudes.add(math.pow(sum, 2));
      valuesX.add(event.x);
      valuesY.add(event.y);
      valuesZ.add(event.z);
    }
    var magnitude = math.sqrt(magnitudes.reduce((a, b) => a + b)); //L2 norm
    var magnitudeX = valuesX.reduce((a, b) => a + b);
    var magnitudeY = valuesY.reduce((a, b) => a + b);
    var magnitudeZ = valuesZ.reduce((a, b) => a + b);

    var mean = magnitude / accelerometerEvents.length;
    var meanX = magnitudeX / accelerometerEvents.length;
    var meanY = magnitudeY / accelerometerEvents.length;
    var meanZ = magnitudeZ / accelerometerEvents.length;

    var std = standardDeviation(magnitudes);
    var stdX = standardDeviation(valuesX);
    var stdY = standardDeviation(valuesY);
    var stdZ = standardDeviation(valuesZ);
    var mom3 = moment3(magnitudes);
    var mom4 = moment4(magnitudes);
    var percentile25 = scoreAtPercentile(magnitudes, 0.25);
    var percentile50 = scoreAtPercentile(magnitudes, 0.5);
    var percentile75 = scoreAtPercentile(magnitudes, 0.75);

    processedData.procGyroMagnitudeStatsMean = mean;
    processedData.procGyroMagnitudeStatsStd = std;
    processedData.procGyroMagnitudeStatsMoment3 = mom3;
    processedData.procGyroMagnitudeStatsMoment4 = mom4;
    processedData.procGyroMagnitudeStatsPercentile25 = percentile25;
    processedData.procGyroMagnitudeStatsPercentile50 = percentile50;
    processedData.procGyroMagnitudeStatsPercentile75 = percentile75;
    processedData.procGyro3dMeanX = meanX;
    processedData.procGyro3dMeanY = meanY;
    processedData.procGyro3dMeanZ = meanZ;
    processedData.procGyro3dStdX = stdX;
    processedData.procGyro3dStdY = stdY;
    processedData.procGyro3dStdZ = stdZ;
    /*processedData.procGyro3dRoXy = roXy;
    processedData.procGyro3dRoYz = roYz;
    processedData.procGyro3dRoXz = roXz;*/
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
    stdLat = math.sqrt(stdLat);
    stdLong /= locationEvents.length;
    stdLong = math.sqrt(stdLong);
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
    double logDiameter = math.log(math.max(diameter, epsilon));
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
    double deg2rad = math.pi / 180;
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
    var a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(deg2rad(lat1)) * math.cos(deg2rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    var c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    var d = R * c; // Distance in km
    return d;
  }

  static double deg2rad(double deg) {
    return deg * (math.pi / 180);
  }

  static double logCompression(double val) {
    double epsilon = 0.001;
    double logVal = math.log(epsilon + val.abs()) - math.log(epsilon);
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
    AudioManager.stopAudioRecording();
    bool computed = await AudioManager.computeMfccFeatures();
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

    // convert the mfcc file content to a list of doubles
    List<MfccMeasureEntity> mfccMeasures = await _computeMfccProperties(f);
    processedData.audioNaiveMfcc0Mean = mfccMeasures[0].mean;
    processedData.audioNaiveMfcc0Std = mfccMeasures[0].std;
    processedData.audioNaiveMfcc1Mean = mfccMeasures[1].mean;
    processedData.audioNaiveMfcc1Std = mfccMeasures[1].std;
    processedData.audioNaiveMfcc2Mean = mfccMeasures[2].mean;
    processedData.audioNaiveMfcc2Std = mfccMeasures[2].std;
    processedData.audioNaiveMfcc3Mean = mfccMeasures[3].mean;
    processedData.audioNaiveMfcc3Std = mfccMeasures[3].std;
    processedData.audioNaiveMfcc4Mean = mfccMeasures[4].mean;
    processedData.audioNaiveMfcc4Std = mfccMeasures[4].std;
    processedData.audioNaiveMfcc5Mean = mfccMeasures[5].mean;
    processedData.audioNaiveMfcc5Std = mfccMeasures[5].std;
    processedData.audioNaiveMfcc6Mean = mfccMeasures[6].mean;
    processedData.audioNaiveMfcc6Std = mfccMeasures[6].std;
    processedData.audioNaiveMfcc7Mean = mfccMeasures[7].mean;
    processedData.audioNaiveMfcc7Std = mfccMeasures[7].std;
    processedData.audioNaiveMfcc8Mean = mfccMeasures[8].mean;
    processedData.audioNaiveMfcc8Std = mfccMeasures[8].std;
    processedData.audioNaiveMfcc9Mean = mfccMeasures[9].mean;
    processedData.audioNaiveMfcc9Std = mfccMeasures[9].std;
    processedData.audioNaiveMfcc10Mean = mfccMeasures[10].mean;
    processedData.audioNaiveMfcc10Std = mfccMeasures[10].std;
    processedData.audioNaiveMfcc11Mean = mfccMeasures[11].mean;
    processedData.audioNaiveMfcc11Std = mfccMeasures[11].std;
    processedData.audioNaiveMfcc12Mean = mfccMeasures[12].mean;
    processedData.audioNaiveMfcc12Std = mfccMeasures[12].std;


    //await AudioManager.clearAudioRecordingData();
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

  static _computeDiscreteStats(SensorsMeasurementEntity processedData) async {
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

static Future<void> predict() async {
    if (data.isEmpty) {
      print("No data to predict, skipping request to backend");
      return;
    }
    String? prediction = await requestPredictionToBackend(data);
    data.clear();
    if(prediction == null) {
      print("No prediction received");
      return;
    }
    PredictionEntity predictionEntity = PredictionEntity(prediction, DateTime.now());
    predictionStream.add(predictionEntity);
  }

  static Future<String?> requestPredictionToBackend(List<SensorsMeasurementEntity> sensorMeasurements) async {
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
      return null;
    }
    return res.data["prediction"];
  }

   static void onActivityData(Activity activityEvent) {
    print(activityEvent);
    lastActivityEvent = activityEvent;
    activityStream.add(activityEvent);
  }
  
  static void _computeActivityFeatures(SensorsMeasurementEntity processedData) {
    var activity = lastActivityEvent;
    if(activity != null) {
      processedData.activityType = activity.type;
      processedData.activityConfidence = activity.confidence;
    }

  }

  static Future<List<MfccMeasureEntity>> _computeMfccProperties(File file) async {
    final lines = await file.readAsLines();

    // Parse the header
    final header = lines[0].split(',');
    final numColumns = header.length;

    // Initialize lists to store column values
    final columns = List.generate(numColumns, (_) => <double>[]);

    // Parse the data
    for (var i = 1; i < lines.length; i++) {
      final values = lines[i].split(',');
      for (var j = 0; j < numColumns; j++) {
        var v = double.tryParse(values[j]);
        if(v == null) {
          print("Error parsing value: ${values[j]}");
          v = 0;
        }
        columns[j].add(v);
      }
    }

    // Calculate mean and standard deviation for each column
    List<MfccMeasureEntity> mfccMeasures = [];
    for (var i = 0; i < numColumns; i++) {
      final mean = calculateMean(columns[i]);
      final stdDev = calculateStandardDeviation(columns[i], mean);

      print('${header[i]}:');
      print('  Mean: ${mean.toStringAsFixed(2)}');
      print('  Standard Deviation: ${stdDev.toStringAsFixed(2)}');
      print('');
      MfccMeasureEntity mfccMeasureEntity = MfccMeasureEntity(mean, stdDev);
      mfccMeasures.add(mfccMeasureEntity);
    }
    return mfccMeasures;
  }

  static double calculateMean(List<double> values) {
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double calculateStandardDeviation(List<double> values, double mean) {
    final variance = values.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) / values.length;
    return math.sqrt(variance);
  }
  
}

class PredictionEntity {
  final String prediction;
  final DateTime timestamp;

  PredictionEntity(this.prediction, this.timestamp);
}

class MfccMeasureEntity {
  final double mean;
  final double std;

  MfccMeasureEntity(this.mean, this.std);
}