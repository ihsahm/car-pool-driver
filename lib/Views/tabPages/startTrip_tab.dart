import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;

import '../../Models/trip.dart';
import '../../widgets/progress_dialog.dart';


class MyWidget extends StatefulWidget {
  final Trip trip;
  @override
  _MyWidgetState createState() => _MyWidgetState();

  const MyWidget({
    Key? key,
    required this.trip
  });
}

class _MyWidgetState extends State<MyWidget> {
  late final TextEditingController _tripNameController;
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _lastPosition;
  bool _trackingActive = false;
  double _totalDistance = 0.0;
  Position? _destination;
  Timer? _simulationTimer;
  double _costPerMeter = 0.1; // 0.1 birr per meter
  double _costPerMinute = 0.5; // 0.5 birr minute
  double _totalCost = 0.0;
  DateTime? _startTime;
  late final GoogleMapController _mapController;
  Set<Marker> _markers = {};
  Position? _currentPosition;
  Set<Polyline> _polylines = {};


  Future<void> _createPolylines() async {
    PolylinePoints polylinePoints = PolylinePoints();
    List<LatLng> polylineCoordinates = [];

    PointLatLng startLatLng = PointLatLng(
        _lastPosition!.latitude, _lastPosition!.longitude);
    PointLatLng destinationLatLng = PointLatLng(
        _destination!.latitude, _destination!.longitude);
    Future.delayed(Duration.zero, () {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext c){
            return ProgressDialog(message: "Processing, Please wait...",);
          }
      );
    });
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      'AIzaSyDvCw3bdrvlUbjoSsW8BHYqyWNxxhTuIiY',
      startLatLng,
      destinationLatLng,
      travelMode: TravelMode.driving,
    );

    if (result.points.isNotEmpty) {
      result.points.forEach((PointLatLng point) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      });
    }

    setState(() {
      _polylines.add(Polyline(
        polylineId: PolylineId('polyline'),
        color: Colors.blue,
        points: polylineCoordinates,
      ));
    });
    Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation().then((Position? position) {
      if (position != null) {
        _currentPosition = position;
        _mapController.animateCamera(CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude), 16));

        _lastPosition = position;
        _destination = Position(
            latitude: double.parse(widget.trip.dropOffLatPos),
            longitude: double.parse(widget.trip.dropOffLongPos),
            altitude: 0,
            accuracy: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            timestamp: DateTime.now());

        _createPolylines();
      }
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _tripNameController.dispose();
    super.dispose();
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }

  void _startTracking() {
    setState(() {
      _trackingActive = true;
    });
    _positionStreamSubscription =
        Geolocator.getPositionStream().listen((Position position) {
          setState(() {
            if (_lastPosition != null) {
              double distance = Geolocator.distanceBetween(
                _lastPosition!.latitude,
                _lastPosition!.longitude,
                position.latitude,
                position.longitude,
              );
              _totalDistance += distance;
            }
            _lastPosition = position;
          });
        });
  }


  Future<void> _endTracking() async {
    setState(() {
      _trackingActive = false;
    });
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    // Cancel the Timer used for simulating movement
    _simulationTimer?.cancel();
    _simulationTimer = null;

    final CollectionReference statusCollection =
    FirebaseFirestore.instance.collection('tripStatus');


    final DocumentReference newStatusRef = await statusCollection.add({
    'title': 'Trip ended',
    'description':
    'The trip has ended rate or pay the driver online',
    });
    //final CollectionReference statusCollection = FirebaseFirestore.instance.collection('trip')
  }

  void _startTrackingSimulation() {
    print("_destination: $_destination");

    int numberOfIds = int.parse(widget.trip.passengers[0]) - int.parse(widget.trip.availableSeats);
    List<String> passengerIDs = List.filled(numberOfIds, ''); // initialize the list with a fixed size
    List<Future> futures = []; // create a list to store the futures returned by the onValue listeners
    for(int i = 0; i < numberOfIds ; i++){
      DatabaseReference starCountRef =
      FirebaseDatabase.instance.ref('trips/${widget.trip.tripID}/passengerIDs/${i.toString()}');
      futures.add(starCountRef.onValue.first.then((event) {
        final data = event.snapshot.value;
        passengerIDs[i] = data.toString(); // update the element in the list at the correct index
      }));
    }
    Future.wait(futures).then((_) {
      FirebaseFirestore firestore = FirebaseFirestore.instance;
      firestore
          .collection('trips') // specify the collection name
          .doc(widget.trip.tripID) // specify the document ID
          .set({
        'passengerIDs': passengerIDs // specify the name of the array field and the list of passenger IDs
      }).then((value) => print("Data written to Firestore"))
          .catchError((error) => print("Failed to write data to Firestore: $error"));
    });
    _simulationTimer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      if (_lastPosition != null && _destination != null) {
        LatLng lastPositionLatLng = LatLng(
            _lastPosition!.latitude, _lastPosition!.longitude);
        double distance = Geolocator.distanceBetween(
          lastPositionLatLng.latitude,
          lastPositionLatLng.longitude,
          _destination!.latitude,
          _destination!.longitude,
        );
        print("distance: $distance");

        if (distance < 100) {
          timer.cancel();
          return;
        }
        double bearing = Geolocator.bearingBetween(
          lastPositionLatLng.latitude,
          lastPositionLatLng.longitude,
          _destination!.latitude,
          _destination!.longitude,
        );
        double speed = 5; // 5 meters per second

        double distanceToTravel = speed;
        if (distanceToTravel > distance) {
          distanceToTravel = distance;
        }
        double lat = lastPositionLatLng.latitude +
            (distanceToTravel / 111320) * cos(bearing * pi / 180.0);
        double lng = lastPositionLatLng.longitude +
            (distanceToTravel / (111320 * cos(lastPositionLatLng.latitude * pi / 180.0))) *
                sin(bearing * pi / 180.0);
        setState(() {
          LatLng newPositionLatLng = LatLng(lat, lng);
          _trackingActive = true;
          _lastPosition = Position(
              latitude: lat,
              longitude: lng,
              altitude: 0,
              accuracy: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              timestamp: DateTime.now());
          _mapController.animateCamera(
              CameraUpdate.newLatLng(newPositionLatLng));
          _addMarker(newPositionLatLng);

          if (_startTime == null) {
            _startTime = DateTime.now();
          }
          if (_lastPosition != null && _trackingActive) {
            double newDistance = Geolocator.distanceBetween(
              lastPositionLatLng.latitude,
              lastPositionLatLng.longitude,
              newPositionLatLng.latitude,
              newPositionLatLng.longitude,
            );
            print("New distance: $newDistance");
            _totalDistance += newDistance;
            print("Total distance: $_totalDistance");
            print("Last Position: $_lastPosition");
            int totalTimeInMinutes = DateTime
                .now()
                .difference(_startTime!)
                .inMinutes;
            _totalCost = (_totalDistance * _costPerMeter) +
                (totalTimeInMinutes * _costPerMinute);
          }
        });
      }
    });
  }


  Marker _marker = Marker(
    markerId: MarkerId('user'),
    position: LatLng(0, 0),
  );

  void _addMarker(LatLng position) async {
    final Uint8List markerIcon = await getBytesFromAsset('images/car.png', 50);
    final BitmapDescriptor customIcon = BitmapDescriptor.fromBytes(markerIcon);

    double rotation = 0.0;
    if (_marker.position != LatLng(0, 0)) {
      rotation = getMarkerRotation(_marker.position.latitude, _marker.position.longitude, position.latitude, position.longitude);
    }

    _marker = Marker(
      markerId: MarkerId('user'),
      position: position,
      icon: customIcon,
      rotation: rotation,
    );

    setState(() {
      _markers.clear();
      _markers.add(_marker);
    });
  }

  double getMarkerRotation(double startLat, double startLng, double endLat, double endLng) {
    final double bearing = atan2(sin(endLng - startLng) * cos(endLat), cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(endLng - startLng));
    return bearing * 180 / pi;
  }
  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    final ByteData data = await rootBundle.load(path);
    final ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    final ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Trip'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SizedBox(
              height: MediaQuery
                  .of(context)
                  .size
                  .height * 0.8,
              child: GoogleMap(
                onMapCreated: (controller) => _mapController = controller,
                initialCameraPosition: _currentPosition != null
                    ? CameraPosition(
                  target: LatLng(_currentPosition!.latitude,
                      _currentPosition!.longitude),
                  zoom: 16,
                )
                    : const CameraPosition(
                  target: LatLng(0, 0),
                  zoom: 16,
                ),
                markers: _markers,
                polylines: _polylines,

              ),
            ),
          ),
          Container(
            width:MediaQuery
                .of(context)
                .size
                .width ,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18.0),
                  topRight: Radius.circular(18.0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent,
                  blurRadius: 10.0,
                ),
              ],
            ),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_trackingActive)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      fixedSize: const Size(100, 100),
                      shape: const CircleBorder(),
                    ),
                    onPressed: _startTrackingSimulation,
                    child: const Text(
                      'Start',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (_trackingActive)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      fixedSize: const Size(100, 100),
                      shape: const CircleBorder(),
                      primary: Colors.red,
                    ),
                    onPressed: _endTracking,
                    child: const Text('End'),
                  ),
                const SizedBox(height: 16),
                /*if (_lastPosition != null)
                  Text(
                    'Last Position: ${_lastPosition!.latitude}, ${_lastPosition!
                        .longitude}',
                  ),*/
                Text(
                  'Total Distance: ${_totalDistance.toStringAsFixed(2)} meters',
                ),
                Text(
                  'Total Cost: ${_totalCost.toStringAsFixed(
                      2)} br. (${_startTime != null ? DateTime
                      .now()
                      .difference(_startTime!)
                      .inMinutes : 0} min)',
                ),
                if (_destination != null)
                  Text(
                    'Destination: ${_destination!.latitude}, ${_destination!
                        .longitude}',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
