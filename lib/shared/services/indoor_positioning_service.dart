import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:easylocate_flutter_sdk/cmds/commands.dart';
import 'package:easylocate_flutter_sdk/easylocate_sdk.dart';
import 'package:easylocate_flutter_sdk/tracelet_api.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:flutter_mvvm_architecture/base.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobx/mobx.dart';

import '../utils/position_fuser.dart';

/// Combines positions received when using a UWB Tracelet and also real time positions from the geolocator package, and fuses them using the kalman filter
/// To start positioning use the function [startPositioning].
/// To stop positioning use the function [stopTraceletPositioning].

class IndoorPositioningService extends Service implements Disposable {
  IndoorPositioningService({
    required this.referenceLatitude,
    required this.referenceLongitude,
    required this.referenceAzimuth,
  });

  factory IndoorPositioningService.fromJson(Map<String, dynamic> json) =>
      IndoorPositioningService(
        referenceLatitude: json['originLatitude'],
        referenceLongitude: json['originLongitude'],
        referenceAzimuth: json['originAzimuth'],
      );

  /// Latitude of the origin
  final double referenceLatitude;

  /// Longitude of the origin
  final double referenceLongitude;

  /// Azimuth of the origin
  final double referenceAzimuth;

  // ------------------  Connection Status -------------------//

  final Observable<bool> _isConnected = Observable(false);

  /// Return true if a tracelet is connected, and false otherwise
  bool get isConnected => _isConnected.value;

  // ------------------  Current LatLng Positions -------------------//

  final Observable<LatLng?> _traceletPosition = Observable(null);

  /// Returns the current wgs84 position from a tracelet. If no position found returns null
  LatLng? get traceletPosition => _traceletPosition.value;

  final Observable<LatLng?> _gnssPosition = Observable(null);

  /// Returns the current GNSS position from the geolocation package. If no position returns null
  LatLng? get gnssPosition => _gnssPosition.value;

  final Observable<LatLng?> _fusedPosition = Observable(null);

  /// Returns the current fused Position . If no position returns null
  LatLng? get fusedPosition => _fusedPosition.value;

  // ------------------  Start and Stop Positioning -------------------//

  /// Starts receiving tracelet positions, geolocations , and fused positions
  void startPositioning() {
    startTraceletPositioning();
    starGeolocation();
    _startFusion();
  }

  /// Stops tracelet positioning, fusedPositioning, and geolocations
  void stopPositioning() {
    stopTraceletPositioning();
    starGeolocation();
    _stopFusion();
  }

  // ------------------  System Fusion -------------------//

  final _fusionLog = Logger('Fusion Positioning');

  Timer _fusionTime = Timer(Duration.zero, () {});

  late final positionFuser = PositionFuser(
      referenceLatitude: referenceLatitude,
      referenceLongitude: referenceLongitude,
      referenceAzimuth: referenceAzimuth);

  /// Fuses tracelet positions and gnss positions.
  void _startFusion() {
    _fusionLog.info('Starting Position Fusion');
    _fusionTime = Timer(const Duration(seconds: 1), () {
      final fusedPosition = positionFuser.fusedPosition;
      runInAction(() {
        _fusedPosition.value = fusedPosition;
        _fusionLog.fine('Position received $fusedPosition');
      });
    });
  }

  /// Stops position fusion
  void _stopFusion() {
    _fusionTime.cancel();
  }

  // ------------------  GeoLocation -------------------//

  final _geolocatorLog = Logger('Geolocator Positioning');

  StreamSubscription<Position>? _positionStream;

  final LocationSettings locationSettings = const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 100,
  );

  /// Starts listening to real time positions from platform specific location services
  void starGeolocation() {
    _geolocatorLog.info('Starting Geolocation');
    try {
      _positionStream =
          Geolocator.getPositionStream(locationSettings: locationSettings)
              .listen((Position? position) {
        if (position != null) {
          runInAction(() => _gnssPosition.value =
              LatLng(position.latitude, position.longitude));
          _geolocatorLog.finest('Position Received : $gnssPosition');
          positionFuser.updateGnssPosition(gnssPosition, position.accuracy);
        }
      });
    } on Exception catch (error) {
      _geolocatorLog.shout(error);
    }
  }

  /// Stops listening to platform specific location services
  void stopGeolocation() {
    _geolocatorLog.info('Stopping Geolocation');
    _positionStream?.cancel();
  }

  // ------------------  Tracelet Positioning -------------------//

  final _traceletLog = Logger('Tracelet Positioning API');

  final _easyLocateSdk = EasyLocateSdk();

  TraceletApi? _positioningApi;

  final Observable<BleDevice?> _bluetoothTracelet = Observable(null);

  /// Retrieves the currently connected bluetooth tracelet. Null when no device is found
  BleDevice? get bluetoothTracelet => _bluetoothTracelet.value;

  /// Connects to the Tracelet on Channel 5 with the closest RSSI value, and starts monitoring the positions.
  ///
  /// Steps:
  /// 1.Scan for the closest tracelet
  /// 2. Connects to the closest tracelet if available
  /// 3. Displays a blue flashing light on the connected tracelet
  /// 3. Sets the channel to 5, the positioning interval to 250ms and motion check interval to 0ms. (Default values used)
  /// 4. Sets the reference wgs84 position. This is the wgs84 position of the origin
  /// 5. Starts positioning
  void startTraceletPositioning() async {
    try {
      // Registers the scanListener to look for bluetooth tracelets
      final scanListener = BluetoothScanListener();
      // Starts scanning and looks for tracelets for 5 seconds
      _traceletLog.info('Start Scanning for Tracelets');
      await _easyLocateSdk.startTraceletScan(
        scanListener,
        scanTimeout: 5,
      );
      // Gets the closest bluetooth tracelet available
      final bluetoothTracelet = scanListener.bleDevice;
      _traceletLog.info('Tracelets Found ${bluetoothTracelet?.name}');
      // Stops bluetooth tracelet scanning
      await _easyLocateSdk.stopBleScan();
      _traceletLog.info('Stop Scanning');

      // Continue only if a ble Tracelet is found
      if (bluetoothTracelet != null) {
        // Connect to the bluetooth tracelet
        _traceletLog.info('Connecting to Tracelet');
        _positioningApi = await _easyLocateSdk.connectBleTracelet(
          bluetoothTracelet,
          listener: ConnectionListener(
            onConnected: () async {
              runInAction(() => _isConnected.value = true);
              _traceletLog.info(
                  'Tracelet Connected. To verify look for a blue flashing light on the device');
              // A blue LED blinks on the connected device. This can be used to verify if you're connected to the right device
              await _positioningApi!.showMe();

              _traceletLog.info('Setting channel to Channel 5');
              // Set the channel to 5 (6.5 GHz). For dw1k tracelets, channel setting is not required as the tracelets operate only on 6.5Ghz
              final channelStatus = await _positioningApi!
                  .setRadioSettings(Channel.FIVE)
                  .timeout(const Duration(seconds: 3));
              channelStatus
                  ? _traceletLog.info('Channel Set Successfully')
                  : _traceletLog.shout('Channel Not Set');
              // Sets the reference wgs84 position. This should be the wgs84 position of the origin
              // By default the tracelet does not know its position in LatLng coordinates,
              // but instead it know the distance in meters from the origin, and it uses the
              // wgs84 coordinates of the origin to find its own position in the real world
              _traceletLog.info('Setting reference wgs84 position');
              await _positioningApi!.setWgs84Reference(
                  referenceLatitude, referenceLongitude, referenceAzimuth);
              // Sets the positioning interval to 250ms. This means that we can get 4 position values every second
              _traceletLog.info('Setting up positioning interval');
              await _positioningApi!.setPositioningInterval(1);

              // Sets the motion check interval to 0. This disables checking if there is motion on the tracelet
              _traceletLog.info('Setting up motion check interval');
              await _positioningApi!.setMotionCheckInterval(0);

              // Start positioning. Uses the position listener to get wgs84 values
              _traceletLog.info('Start Positioning');
              await _positioningApi!.startPositioning(
                PositionListener(
                  onWgs84PositionUpdated: (position) {
                    runInAction(
                      () => _traceletPosition.value =
                          LatLng(position.lat, position.lon),
                    );
                    _traceletLog
                        .finest('Position Received : $traceletPosition');
                    positionFuser.updateUwbPosition(
                        traceletPosition, position.acc);
                  },
                ),
              );
            },
            onDisconnected: () {
              runInAction(() {
                _isConnected.value = false;
                _bluetoothTracelet.value = null;
                _traceletPosition.value = null;
              });
              // Takes 1 second after disconnectTracelet() runs to execute
              _traceletLog.info('Tracelet Disconnected');
            },
          ),
        );
      }
    } on Exception catch (error) {
      runInAction(() {
        _bluetoothTracelet.value = null;
        _isConnected.value = false;
        _traceletPosition.value = null;
      });
      _traceletLog.info(error.toString());
    }
  }

  /// Disconnects from a Tracelet
  void stopTraceletPositioning() async {
    if (_positioningApi != null) {
      _traceletLog.info('Disconnecting Tracelet');
      await _positioningApi!.stopPositioning();
      // The tracelet takes 1s to disconnect
      _positioningApi!.disconnect();
      _positioningApi = null;
    }
  }

  @override
  FutureOr onDispose() {
    if (_positioningApi != null) {
      _traceletLog.info(' Disconnecting Tracelet');
      _positioningApi!.disconnect();
    }
    _traceletLog.info('Service disposed successfully');
  }
}

/// Listener that receives information when a tracelet is connected/ disconnected
class ConnectionListener extends ConnectionStateListener {
  final VoidCallback? onDisconnected;
  final VoidCallback? onConnected;

  ConnectionListener({this.onDisconnected, this.onConnected});

  @override
  void onConnectionStateChanged(bool connected) {
    if (connected == false) {
      onDisconnected?.call();
    } else {
      onConnected?.call();
    }
  }
}

/// Listener that receives positioning data as local positions (meters) / wgs84 positions
class PositionListener extends TagPositionListener {
  final void Function(Wgs84Position wgs84position)? onWgs84PositionUpdated;

  PositionListener({this.onWgs84PositionUpdated});

  @override
  void onLocalPosition(LocalPosition localPosition) {}

  @override
  void onWgs84Position(Wgs84Position wgs84position) {
    onWgs84PositionUpdated?.call(wgs84position);
  }
}

/// Listener for bluetooth tracelet devices
class BluetoothScanListener extends BleScanListener {
  BleDevice? _bleDevice;

  /// Available list of satlets sorted according to their proximity to the device
  BleDevice? get bleDevice => _bleDevice;

  @override
  void onDeviceApproached(BleDevice bleDevice) {
    _bleDevice = bleDevice;
  }

  @override
  void onScanResults(List<BleDevice> bleDevices) {}
}
