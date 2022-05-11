import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Etekcity Scale',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Etekcity Scale'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FlutterBlue flutterBlue = FlutterBlue.instance;

  List<BluetoothDevice> _foundScales = List.empty(growable: true);

  @override
  void initState() {
    super.initState();
    // Listen to scan results
    var subscription = flutterBlue.scanResults.listen((results) {
      // do something with scan results
      for (ScanResult r in results) {
        if (r.device.name.isEmpty) {
          continue;
        }
        print('${r.device.name} found! rssi: ${r.rssi}');

        // Check if it is one of the scales we support.
        exploreDevice(device: r.device);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: ListView.builder(
            itemCount: _foundScales.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(_foundScales[index].name),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) =>
                          ScalePage(scaleDevice: _foundScales[index])));
                },
              );
            }),
      ),
      floatingActionButton: StreamBuilder<bool>(
        initialData: false,
        stream: flutterBlue.isScanning,
        builder: (BuildContext context, AsyncSnapshot<bool> snapShot) {
          if (!snapShot.hasData || snapShot.data == false) {
            return FloatingActionButton(
              onPressed: () {
                startScanForScales();
              },
              tooltip: "Find Scales",
              child: const Icon(Icons.add),
            );
          } else {
            return FloatingActionButton(
              onPressed: () {
                flutterBlue.stopScan();
              },
              tooltip: "Stop Search",
              child: const Icon(Icons.stop),
            );
          }
        },
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  Future<void> startScanForScales() async {
    if (!await Permission.locationWhenInUse.request().isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Padding(
          padding: EdgeInsets.all(8.0),
          child: Text("Access to location is needed in order to find Scales."),
        ),
      ));
      return;
    }

    flutterBlue.startScan(withServices: <Guid>[
    ]);
  }

  Future<void> exploreDevice({required BluetoothDevice device}) async {
    await device.connect();

    List<BluetoothService> services = await device.discoverServices();

    for (BluetoothService service in services) {
      List<BluetoothCharacteristic> characteristics = service.characteristics;
      for (BluetoothCharacteristic c in characteristics) {
        if (c.uuid == Guid("0000FFF1-0000-1000-8000-00805F9B34FB") &&
            device.name.startsWith("Etekcity")) {
          // This is the scale weight characteristic. The weight measurements will come through here
          // This is likely an Etekcity Scale let's display it to connect to it.
          if (!_foundScales.contains(device)) {
            setState(() {
              _foundScales.add(device);
            });
          }
        }
      }
    }
    // Disconnect from device
    device.disconnect();
  }
}

class ScalePage extends StatefulWidget {
  final BluetoothDevice scaleDevice;

  const ScalePage({Key? key, required this.scaleDevice}) : super(key: key);

  @override
  State<ScalePage> createState() => _ScalePageState();
}

class _ScalePageState extends State<ScalePage> {
  double _scaleWeight = 0;
  StreamSubscription<List<int>>? notificationSubscription;

  @override
  void initState() {
    super.initState();
    connectDevice(device: widget.scaleDevice);
  }

  @override
  void dispose() {
    super.dispose();
    disconnectDevice(device: widget.scaleDevice);
    notificationSubscription?.cancel();
  }

  Future<void> connectDevice({required BluetoothDevice device}) async {
    await device.connect();

    List<BluetoothService> services = await device.discoverServices();

    for (BluetoothService service in services) {
      List<BluetoothCharacteristic> characteristics = service.characteristics;
      for (BluetoothCharacteristic c in characteristics) {
        print("Characteristic: ${c.uuid}");
        ///
        /// In this scale the weight is available through the characteristic 0xFFF1
        ///
        if (c.uuid == Guid("0000FFF1-0000-1000-8000-00805F9B34FB") &&
            device.name.startsWith("Etekcity")) {
          // This is the scale weight characteristic. The weight measurements will come through here
          // Register for notifications.
          ///
          /// Weight chance from the scale will be notified to the app.
          ///
          await c.setNotifyValue(true);
          notificationSubscription = c.value.listen((value) {
            // do something with new value
            print(
                "Data: ${value.map((e) => e.toRadixString(16).padLeft(2, '0')).join("-")}");

            if (value.length < 22) {
              return;
            }
            /// Bytes 10 and 11 contain the weight values in little endian
            Uint8List weightValues = Uint8List.fromList([0x00, 0x00, value[11], value[10]]);

            if (!mounted) {
              notificationSubscription?.cancel();
              return;
            }


            /*
            print ("${weightValues.map((e) => e.toRadixString(16).padLeft(2, '0')).join("-")} ---- ${roundDouble(
                weightValues.buffer.asByteData().getInt32(0) /
                    453.9, 2)}");

             */
            /// Divide decimal value of weight by 453.9 to obtain pounds.

            setState(() {
              _scaleWeight = roundDouble(
                  weightValues.buffer.asByteData().getInt32(0) /
                      453.9, 2);
            });

            /// Byte 19 will be set to 1 when the measurement is fully capture (number blinks on scale)
          });
        }
      }
    }
  }

  double roundDouble(double value, int places){
    double mod = pow(10.0, places).toDouble();
    return ((value * mod).round().toDouble() / mod);
  }

  Future<void> disconnectDevice({required BluetoothDevice device}) async {
    // Disconnect from device
    device.disconnect();
  }


  // 52.3 lbs
  // Data: a5-02-8d-10-00-66-01-61-a1-00-d0-5c-00-00-00-c3-61-00-00-00-01-01
  // Data: a5-02-8e-10-00-6f-01-61-a1-00-c6-5c-00-00-00-c3-61-00-00-00-01-01
  // Data: a5-02-8e-10-00-6f-01-61-a1-00-c6-5c-00-00-00-c3-61-00-00-00-01-01
  // Data: a5-02-8f-10-00-78-01-61-a1-00-bc-5c-00-00-00-c3-61-00-00-00-01-01
  // Data: a5-02-8f-10-00-78-01-61-a1-00-bc-5c-00-00-00-c3-61-00-00-00-01-01
  // Data: a5-02-90-10-00-75-01-61-a1-00-bc-5c-00-00-00-c4-61-00-00-01-01-01
  // Data: a5-02-90-10-00-75-01-61-a1-00-bc-5c-00-00-00-c4-61-00-00-01-01-01

  // 0.00 lbs
  // Data: a5-02-38-10-00-7a-01-61-a1-00-ba-04-00-00-00-4a-88-01-00-00-01-01
  // Data: a5-02-39-10-00-28-01-61-a1-00-0c-03-00-00-00-4a-88-01-00-00-01-01
  // Data: a5-02-3a-10-00-d7-01-61-a1-00-5e-01-00-00-00-4a-88-01-00-00-01-01
  // Data: a5-02-3b-10-00-da-01-61-a1-00-5a-00-00-00-00-4b-88-01-00-00-01-01
  // Data: a5-02-3c-10-00-33-01-61-a1-00-00-00-00-00-00-4b-88-01-00-00-01-01
  // Data: a5-02-3d-10-00-32-01-61-a1-00-00-00-00-00-00-4b-88-01-00-00-01-01
  // Data: a5-02-3e-10-00-31-01-61-a1-00-00-00-00-00-00-4b-88-01-00-00-01-01

  //26.0 lbs
  // Data: a5-02-f5-10-00-0b-01-61-a1-00-18-2e-00-00-00-69-92-01-00-01-01-01
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scaleDevice.name),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text("$_scaleWeight lbs", style: GoogleFonts.pressStart2p(fontSize: 30),)],
        ),
      ),
    );
  }
}

