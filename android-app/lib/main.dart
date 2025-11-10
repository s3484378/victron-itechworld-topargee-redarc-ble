import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/stream/ctr.dart';
import 'secrets.dart';

void main() {
  runApp(const ESP32CounterApp());
}

class ESP32CounterApp extends StatelessWidget {
  const ESP32CounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tallulah',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainNavigationPage(),
    );
  }
}

// Main navigation page with bottom navigation bar
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;
  
  final List<Widget> _pages = [
    const BLEScannerPage(),
    const DirectAccessPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: 'ESP32 Controller',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sensors),
            label: 'Direct Access',
          ),
        ],
      ),
    );
  }
}

// ESP32 BLE Service UUIDs
const String ESP32_SERVICE_UUID = "12345678-1234-1234-1234-123456789abc";
const String TELEMETRY_CHAR_UUID = "87654321-4321-4321-4321-210987654321";
const String UPDATE_RATE_CHAR_UUID = "11111111-2222-3333-4444-555555555555";

// Individual solar panel data (12 bytes each)
class SolarPanelData {
  final double voltage;
  final double current;
  final double power;

  SolarPanelData({
    required this.voltage,
    required this.current,
    required this.power,
  });

  static SolarPanelData fromByteData(ByteData data, int offset) {
    return SolarPanelData(
      voltage: data.getFloat32(offset, Endian.little),
      current: data.getFloat32(offset + 4, Endian.little),
      power: data.getFloat32(offset + 8, Endian.little),
    );
  }
}

// Individual battery monitor data (20 bytes each)
class BatteryMonitorData {
  final double voltage;
  final double current;
  final double power;
  final double stateOfCharge;
  final double timeToEmptyFull;

  BatteryMonitorData({
    required this.voltage,
    required this.current,
    required this.power,
    required this.stateOfCharge,
    required this.timeToEmptyFull,
  });

  static BatteryMonitorData fromByteData(ByteData data, int offset) {
    return BatteryMonitorData(
      voltage: data.getFloat32(offset, Endian.little),
      current: data.getFloat32(offset + 4, Endian.little),
      power: data.getFloat32(offset + 8, Endian.little),
      stateOfCharge: data.getFloat32(offset + 12, Endian.little),
      timeToEmptyFull: data.getFloat32(offset + 16, Endian.little),
    );
  }
}

// Water tank data (24 bytes)
class WaterTankData {
  final double percentage;
  final double litresRemaining;
  final double flowRate;
  final int lastRefillDate;
  final double averageLPerDay;
  final double estimatedDaysLeft;

  WaterTankData({
    required this.percentage,
    required this.litresRemaining,
    required this.flowRate,
    required this.lastRefillDate,
    required this.averageLPerDay,
    required this.estimatedDaysLeft,
  });

  static WaterTankData fromByteData(ByteData data, int offset) {
    return WaterTankData(
      percentage: data.getFloat32(offset, Endian.little),
      litresRemaining: data.getFloat32(offset + 4, Endian.little),
      flowRate: data.getFloat32(offset + 8, Endian.little),
      lastRefillDate: data.getUint32(offset + 12, Endian.little),
      averageLPerDay: data.getFloat32(offset + 16, Endian.little),
      estimatedDaysLeft: data.getFloat32(offset + 20, Endian.little),
    );
  }
}

// Complete telemetry data structure (96 bytes total)
class TelemetryData {
  final SolarPanelData solarPanel1;
  final SolarPanelData solarPanel2;
  final BatteryMonitorData batteryMonitor1;
  final BatteryMonitorData batteryMonitor2;
  final WaterTankData waterTank;
  final int counter;
  final int timestamp;

  TelemetryData({
    required this.solarPanel1,
    required this.solarPanel2,
    required this.batteryMonitor1,
    required this.batteryMonitor2,
    required this.waterTank,
    required this.counter,
    required this.timestamp,
  });

  static TelemetryData fromBytes(List<int> bytes) {
    if (bytes.length < 96) throw Exception('Invalid data length: ${bytes.length} bytes, expected at least 96');
    
    ByteData byteData = Uint8List.fromList(bytes).buffer.asByteData();
    
    return TelemetryData(
      // Solar panels (24 bytes total: 12 each)
      solarPanel1: SolarPanelData.fromByteData(byteData, 0),
      solarPanel2: SolarPanelData.fromByteData(byteData, 12),
      
      // Battery monitors (40 bytes total: 20 each)
      batteryMonitor1: BatteryMonitorData.fromByteData(byteData, 24),
      batteryMonitor2: BatteryMonitorData.fromByteData(byteData, 44),
      
      // Water tank (24 bytes)
      waterTank: WaterTankData.fromByteData(byteData, 64),
      
      // System info (8 bytes)
      counter: byteData.getUint32(88, Endian.little),
      timestamp: byteData.getUint32(92, Endian.little),
    );
  }

  // Helper getters for backward compatibility and convenience
  double get totalSolarPower => solarPanel1.power + solarPanel2.power;
  double get totalBatteryPower => batteryMonitor1.power + batteryMonitor2.power;
  double get averageBatteryVoltage => (batteryMonitor1.voltage + batteryMonitor2.voltage) / 2;
  double get averageStateOfCharge => (batteryMonitor1.stateOfCharge + batteryMonitor2.stateOfCharge) / 2;
}

// Custom painter for 5-bar signal strength indicator
class SignalStrengthPainter extends CustomPainter {
  final int bars;
  final Color color;

  SignalStrengthPainter({required this.bars, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;

    const int maxBars = 5;
    final double barWidth = size.width / (maxBars * 1.5); // Space between bars
    final double barSpacing = barWidth * 0.5;

    for (int i = 0; i < maxBars; i++) {
      final double barHeight = size.height * ((i + 1) / maxBars);
      final double x = i * (barWidth + barSpacing);
      final double y = size.height - barHeight;

      // Set color based on whether this bar should be filled
      paint.color = (i < bars) ? color : color.withOpacity(0.3);

      canvas.drawRect(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is SignalStrengthPainter &&
        (oldDelegate.bars != bars || oldDelegate.color != color);
  }
}

// Victron device data classes
class VictronShuntData {
  final double timeToGo;
  final double batteryVoltage;
  final double batteryCurrent;
  final double consumedAh;
  final double stateOfCharge;
  final double auxVoltage;
  final int alarmReason;
  final int auxInputType;
  final DateTime lastUpdate;

  VictronShuntData({
    required this.timeToGo,
    required this.batteryVoltage,
    required this.batteryCurrent,
    required this.consumedAh,
    required this.stateOfCharge,
    required this.auxVoltage,
    required this.alarmReason,
    required this.auxInputType,
    required this.lastUpdate,
  });
}

class VictronSolarData {
  final int state;
  final int error;
  final double batteryVoltage;
  final double batteryCurrent;
  final double pvPower;
  final double yieldToday;
  final double loadCurrent;
  final DateTime lastUpdate;

  VictronSolarData({
    required this.state,
    required this.error,
    required this.batteryVoltage,
    required this.batteryCurrent,
    required this.pvPower,
    required this.yieldToday,
    required this.loadCurrent,
    required this.lastUpdate,
  });
}

class ItechworldBatteryData {
  final double voltage;
  final double current;
  final double power;
  final double ampHours;
  final double cell1Voltage;
  final double cell2Voltage;
  final double cell3Voltage;
  final double cell4Voltage;
  final bool chargeIsolatorEnabled;
  final bool dischargeIsolatorEnabled;
  final DateTime lastUpdate;

  ItechworldBatteryData({
    required this.voltage,
    required this.current,
    required this.power,
    required this.ampHours,
    required this.cell1Voltage,
    required this.cell2Voltage,
    required this.cell3Voltage,
    required this.cell4Voltage,
    required this.chargeIsolatorEnabled,
    required this.dischargeIsolatorEnabled,
    required this.lastUpdate,
  });
}

class TopargeeWaterTankData {
  final int tankCapacity;
  final int litresUsed;
  final int currentLitres;
  final double percentage;
  final String deviceName;
  final DateTime lastUpdate;

  TopargeeWaterTankData({
    required this.tankCapacity,
    required this.litresUsed,
    required this.currentLitres,
    required this.percentage,
    required this.deviceName,
    required this.lastUpdate,
  });
}

// Direct Access page for Victron device scanning
class DirectAccessPage extends StatefulWidget {
  const DirectAccessPage({super.key});

  @override
  State<DirectAccessPage> createState() => _DirectAccessPageState();
}

class _DirectAccessPageState extends State<DirectAccessPage> {
  // Device constants (imported from secrets.dart)
  // See lib/secrets.dart for actual values
  
  // Topargee UUIDs and commands
  static const String TOPARGEE_WRITE_UUID = "0000fff1-0000-1000-8000-00805f9b34fb";
  static const String TOPARGEE_NOTIFY_UUID = "0000fff4-0000-1000-8000-00805f9b34fb";
  static const String TANK_CAP_CMD = "5ac300ffffffffffffffffffffffffffffffff";
  static const String LITRES_USED_CMD = "5ac700ffffffffffffffffffffffffffffffff";
  
  // Itechworld UUIDs and commands
  static const String ITECHWORLD_NOTIFY_UUID = "0000ff01-0000-1000-8000-00805f9b34fb";
  static const String ITECHWORLD_WRITE_UUID = "0000ff02-0000-1000-8000-00805f9b34fb";
  static const String POLL_CMD = "dda50300fffd77";
  static const String FINAL_BLOCK_CMD = "dda50400fffc77";
  static const String ISOLATOR_ENABLE_CHARGE = "dd5ae1020001ff1c77";
  static const String ISOLATOR_ENABLE_DISCHARGE = "dd5ae1020002ff1b77";
  static const String ISOLATOR_DISABLE_BOTH = "dd5ae1020000ff1d77";
  static const String ISOLATOR_ENABLE_BOTH = "dd5ae1020003ff1a77";
  // static const String ISOLATOR_SECOND_WRITE = "dd5a01020000fffd77"; // Not required per user testing

  bool isScanning = false;
  VictronShuntData? shuntData;
  VictronSolarData? solarData;
  ItechworldBatteryData? itechworldData;
  TopargeeWaterTankData? topargeeData;
  StreamSubscription<List<ScanResult>>? scanSubscription;
  Map<String, int> lastDataCounters = {};
  Timer? refreshTimer;
  Timer? scanWatchdog; // Watchdog timer to ensure scanning stays active
  
  // Topargee BLE connection state
  BluetoothDevice? topargeeDevice;
  BluetoothCharacteristic? topargeeNotifyChar;
  BluetoothCharacteristic? topargeeWriteChar;
  bool topargeeConnected = false;
  bool topargeeConnecting = false;
  Timer? topargeePollTimer;
  bool topargeeWaitingForResponse = false;
  
  // Itechworld BLE connection state
  BluetoothDevice? itechworldDevice;
  BluetoothCharacteristic? itechworldNotifyChar;
  BluetoothCharacteristic? itechworldWriteChar;
  bool itechworldConnected = false;
  bool itechworldConnecting = false;
  List<String> itechworldCycleData = ["", "", "", ""];
  String itechworldLatestBlock4 = "";
  int itechworldPollCount = 0;
  Timer? itechworldPollTimer;
  
  // Status-driven polling state
  bool isWaitingForResponse = false;
  Timer? pollWatchdog;
  bool isRequestingCellVoltages = false;
  
  // Isolator command state
  bool isExecutingIsolatorCommand = false;
  bool isPendingIsolatorCommand = false;  // Flag to queue isolator commands
  
  // Isolator pending states for immediate UI feedback
  bool? chargeIsolatorPending;
  bool? dischargeIsolatorPending;
  DateTime? lastIsolatorCommand;

  bool get isShuntDataFresh {
    if (shuntData == null) return false;
    return DateTime.now().difference(shuntData!.lastUpdate).inSeconds < 30;
  }

  bool get isSolarDataFresh {
    if (solarData == null) return false;
    return DateTime.now().difference(solarData!.lastUpdate).inSeconds < 30;
  }

  bool get isItechworldDataFresh {
    if (itechworldData == null) return false;
    return DateTime.now().difference(itechworldData!.lastUpdate).inSeconds < 30;
  }

  bool get isTopargeeDataFresh {
    if (topargeeData == null) return false;
    return DateTime.now().difference(topargeeData!.lastUpdate).inSeconds < 30;
  }

  Color get itechworldStatusColor {
    if (itechworldConnecting) return Colors.orange;
    if (!itechworldConnected) return Colors.red;
    if (isItechworldDataFresh) return Colors.green;
    return Colors.orange; // Connected but no recent data
  }

  Color get topargeeStatusColor {
    if (topargeeConnecting) return Colors.orange;
    if (!topargeeConnected) return Colors.red;
    if (isTopargeeDataFresh) return Colors.green;
    return Colors.orange; // Connected but no recent data
  }

  String get itechworldStatusText {
    if (itechworldConnecting) return 'Connecting...';
    if (!itechworldConnected) return 'Disconnected';
    if (isItechworldDataFresh) return 'Connected';
    return 'Connected (No Data)';
  }

  String get topargeeStatusText {
    if (topargeeConnecting) return 'Connecting...';
    if (!topargeeConnected) return 'Disconnected';
    if (isTopargeeDataFresh) return 'Connected';
    return 'Connected (No Data)';
  }

  @override
  void initState() {
    super.initState();
    
    // Reduce Flutter Blue Plus debug logging
    FlutterBluePlus.setLogLevel(LogLevel.none);
    
    _requestPermissions().then((_) {
      // Auto-start scanning when permissions are granted
      _startScanning();
    });
    
    // Start a periodic timer to refresh the UI and monitor scanning health
    refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        // Clear pending states if they've been pending for more than 5 seconds
        if (lastIsolatorCommand != null) {
          final timeSinceCommand = DateTime.now().difference(lastIsolatorCommand!).inSeconds;
          if (timeSinceCommand > 5) {
            setState(() {
              chargeIsolatorPending = null;
              dischargeIsolatorPending = null;
              lastIsolatorCommand = null;
            });
          }
        }
        
        // Health check: ensure scanning is still active if it should be
        _checkScanningHealth();
        
        setState(() {
          // This will trigger a rebuild to update timestamps and connection status
        });
      }
    });
    
    // Start scanning watchdog to ensure reliability
    _startScanningWatchdog();
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    refreshTimer?.cancel();
    scanWatchdog?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    if (!allGranted) {
      //print('Some permissions not granted');
    }
  }

  // AES-CTR decryption
  Uint8List _decryptPayload(Uint8List payload, int counterLsb, int counterMsb, List<int> bindkey) {
    // Create nonce: 2 bytes counter + 14 zero bytes
    final nonce = Uint8List(16);
    nonce[0] = counterLsb;
    nonce[1] = counterMsb;

    // Initialize AES-CTR cipher
    final cipher = CTRStreamCipher(AESEngine());
    final params = pc.ParametersWithIV(pc.KeyParameter(Uint8List.fromList(bindkey)), nonce);
    cipher.init(false, params);

    // Decrypt
    final decrypted = Uint8List(payload.length);
    cipher.processBytes(payload, 0, payload.length, decrypted, 0);
    return decrypted;
  }

  VictronShuntData? _parseShuntData(Uint8List data) {
    if (data.length < 15) return null;
    
    // Pad to 16 bytes if needed
    if (data.length == 15) {
      final padded = Uint8List(16);
      padded.setRange(0, 15, data);
      data = padded;
    }

    final byteData = ByteData.sublistView(data);
    
    final timeToGo = byteData.getUint16(0, Endian.little).toDouble();
    final batteryVoltage = byteData.getInt16(2, Endian.little) * 0.01;
    final alarmReason = byteData.getUint16(4, Endian.little);
    final auxInputRaw = byteData.getUint16(6, Endian.little);
    
    // Bit-packed fields
    var remainingBits = byteData.getUint64(8, Endian.little);
    final auxInputType = remainingBits & 0x3;
    remainingBits >>= 2;
    
    var batteryCurrentRaw = remainingBits & 0x3FFFFF;
    if (batteryCurrentRaw & 0x200000 != 0) {
      batteryCurrentRaw |= 0xFFC00000;
    }
    final batteryCurrent = batteryCurrentRaw.toSigned(32) * 0.001;
    remainingBits >>= 22;
    
    final consumedAhRaw = remainingBits & 0xFFFFF;
    final consumedAh = -(consumedAhRaw * 0.1);
    remainingBits >>= 20;
    
    final stateOfChargeRaw = remainingBits & 0x3FF;
    final stateOfCharge = stateOfChargeRaw * 0.1;
    
    final auxVoltage = auxInputRaw == 0xFFFF ? 0.0 : auxInputRaw * 0.01;

    return VictronShuntData(
      timeToGo: timeToGo,
      batteryVoltage: batteryVoltage,
      batteryCurrent: batteryCurrent,
      consumedAh: consumedAh,
      stateOfCharge: stateOfCharge,
      auxVoltage: auxVoltage,
      alarmReason: alarmReason,
      auxInputType: auxInputType,
      lastUpdate: DateTime.now(),
    );
  }

  VictronSolarData? _parseSolarData(Uint8List data) {
    if (data.length < 12) return null;
    
    // Pad to 16 bytes if needed
    if (data.length < 16) {
      final padded = Uint8List(16);
      padded.setRange(0, data.length, data);
      data = padded;
    }

    final byteData = ByteData.sublistView(data);
    
    final state = data[0];
    final error = data[1];
    final batteryVoltage = byteData.getUint16(2, Endian.little) * 0.01;
    final batteryCurrent = byteData.getInt16(4, Endian.little) * 0.1;
    final yieldToday = byteData.getUint16(6, Endian.little) * 0.01;
    final pvPower = byteData.getUint16(8, Endian.little).toDouble();
    
    // Load current: 9-bit signed value from bytes 12-13
    final loadBits = data[12] | (data[13] << 8);
    var loadIRaw = loadBits & 0x1FF;
    if (loadIRaw & 0x100 != 0) {
      loadIRaw -= 0x200;
    }
    final loadCurrent = loadIRaw * 0.1;

    return VictronSolarData(
      state: state,
      error: error,
      batteryVoltage: batteryVoltage,
      batteryCurrent: batteryCurrent,
      pvPower: pvPower,
      yieldToday: yieldToday,
      loadCurrent: loadCurrent,
      lastUpdate: DateTime.now(),
    );
  }

  // Health check to ensure scanning stays active and self-heals
  void _checkScanningHealth() {
    // If we should be scanning but aren't, restart it
    if (isScanning && !FlutterBluePlus.isScanningNow) {
      //print('SCAN HEALTH - Scanning stopped unexpectedly, restarting...');
      _restartScanning();
    }
    
    // Check if Victron data is getting stale (no updates for 60+ seconds)
    final now = DateTime.now();
    bool shuntStale = shuntData != null && now.difference(shuntData!.lastUpdate).inSeconds > 60;
    bool solarStale = solarData != null && now.difference(solarData!.lastUpdate).inSeconds > 60;
    
    if (isScanning && (shuntStale || solarStale)) {
      //print('SCAN HEALTH - Victron data stale, refreshing scan...');
      _restartScanning();
    }
  }

  // Start scanning watchdog to monitor and restart scanning if needed
  void _startScanningWatchdog() {
    scanWatchdog?.cancel();
    scanWatchdog = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && isScanning) {
        // Restart scanning every 30 seconds to prevent BLE stack issues
        //print('SCAN WATCHDOG - Refreshing scan for reliability');
        _restartScanning();
      }
    });
  }

  // Restart scanning for reliability
  Future<void> _restartScanning() async {
    try {
      // Don't change UI state, just restart the underlying scan
      await FlutterBluePlus.stopScan();
      scanSubscription?.cancel();
      
      // Small delay before restart
      await Future.delayed(Duration(milliseconds: 500));
      
      if (isScanning && mounted) {
        // Restart scan subscription
        scanSubscription = FlutterBluePlus.scanResults.listen((results) {
          for (final result in results) {
            _processAdvertisement(result);
          }
        });
        
        // Start scanning again
        await FlutterBluePlus.startScan();
        //print('SCAN HEALTH - Scanning restarted successfully');
      }
    } catch (e) {
      //print('SCAN HEALTH - Error restarting scan: $e');
      // Try again in a few seconds
      if (mounted && isScanning) {
        Timer(Duration(seconds: 3), () => _restartScanning());
      }
    }
  }

  void _processAdvertisement(ScanResult result) {
    final manufacturerData = result.advertisementData.manufacturerData;
    if (manufacturerData.isEmpty) return;

    final payload = manufacturerData[0x02E1];
    if (payload == null || payload.length < 8) return;

    final counterLsb = payload[5];
    final counterMsb = payload[6];
    final encryptionKey0 = payload[7];
    final encrypted = Uint8List.fromList(payload.sublist(8));

    final dataCounter = counterLsb | (counterMsb << 8);
    final deviceKey = '${result.device.remoteId}';
    
    // Only process if data counter changed
    if (lastDataCounters[deviceKey] == dataCounter) return;
    lastDataCounters[deviceKey] = dataCounter;

    try {
      if (result.device.remoteId.toString().toUpperCase() == SHUNT_MAC) {
        if (encryptionKey0 != SHUNT_BINDKEY[0]) return;
        final decrypted = _decryptPayload(encrypted, counterLsb, counterMsb, SHUNT_BINDKEY);
        final parsed = _parseShuntData(decrypted);
        if (parsed != null) {
          setState(() {
            shuntData = parsed;
          });
        }
      } else if (result.device.remoteId.toString().toUpperCase() == SOLAR_MAC) {
        if (encryptionKey0 != SOLAR_BINDKEY[0]) return;
        final decrypted = _decryptPayload(encrypted, counterLsb, counterMsb, SOLAR_BINDKEY);
        final parsed = _parseSolarData(decrypted);
        if (parsed != null) {
          setState(() {
            solarData = parsed;
          });
        }
      } else if (result.device.remoteId.toString().toUpperCase() == ITECHWORLD_MAC) {
        // Itechworld device detected but don't auto-connect (use toggle button instead)
      } else if (result.device.remoteId.toString().toUpperCase() == TOPARGEE_MAC) {
        // Topargee device detected but don't auto-connect (use toggle button instead)
      }
    } catch (e) {
      // Silently handle advertisement processing errors
    }
  }

  // Itechworld isolator control methods
  Future<void> _toggleChargeIsolator(bool enabled) async {
    //print('here');
    if (!itechworldConnected || itechworldWriteChar == null) {
      return;
    }

    // Prevent multiple simultaneous isolator commands
    if (isExecutingIsolatorCommand) {
      //print('ISOLATOR DEBUG - Already executing isolator command, ignoring');
      return;
    }

    // Set pending state for immediate UI feedback
    setState(() {
      chargeIsolatorPending = enabled;
      lastIsolatorCommand = DateTime.now();
    });

    try {
      // If currently polling, queue the isolator command to execute after current cycle completes
      if (isWaitingForResponse) {
        //print('ISOLATOR DEBUG - Polling in progress, queueing isolator command');
        isPendingIsolatorCommand = true;
        
        // Wait for current polling cycle to completely finish
        while (isWaitingForResponse) {
          await Future.delayed(Duration(milliseconds: 100));
        }
        // Additional wait for the pending flag to be cleared by notification handler
        while (isPendingIsolatorCommand) {
          await Future.delayed(Duration(milliseconds: 100));
        }
      }
      
      // Set isolator command execution flag to pause polling
      isExecutingIsolatorCommand = true;
      
      // Determine the appropriate command based on current state and requested state
      String command;
      final currentDischargeState = itechworldData?.dischargeIsolatorEnabled ?? false;
      
      if (enabled && currentDischargeState) {
        // Enable both charge and discharge
        command = ISOLATOR_ENABLE_BOTH;
      } else if (enabled && !currentDischargeState) {
        // Enable only charge
        command = ISOLATOR_ENABLE_CHARGE;
      } else if (!enabled && currentDischargeState) {
        // Disable charge, keep discharge
        command = ISOLATOR_ENABLE_DISCHARGE;
      } else {
        // Disable both
        command = ISOLATOR_DISABLE_BOTH;
      }

      await _sendIsolatorCommand(command, enabled ? "enable charge" : "disable charge");
    } catch (e) {
      // Clear pending state on error
      setState(() {
        chargeIsolatorPending = null;
      });
    } finally {
      // Always clear the isolator command flag to resume polling
      isExecutingIsolatorCommand = false;
      
      // Resume polling immediately after isolator command completes
      if (itechworldConnected) {
        // Small delay to ensure isolator command is fully processed
        await Future.delayed(Duration(milliseconds: 200));
        _pollItechworldData();
      }
      //print('ISOLATOR DEBUG - Charge isolator command complete (polling disabled for UX testing)');
    }
  }

  Future<void> _toggleDischargeIsolator(bool enabled) async {
    if (!itechworldConnected || itechworldWriteChar == null) {
      return;
    }

    // Prevent multiple simultaneous isolator commands
    if (isExecutingIsolatorCommand) {
      //print('ISOLATOR DEBUG - Already executing isolator command, ignoring');
      return;
    }

    // Set pending state for immediate UI feedback
    setState(() {
      dischargeIsolatorPending = enabled;
      lastIsolatorCommand = DateTime.now();
    });

    try {
      // If currently polling, queue the isolator command to execute after current cycle completes
      if (isWaitingForResponse) {
        //print('ISOLATOR DEBUG - Polling in progress, queueing isolator command');
        isPendingIsolatorCommand = true;
        
        // Wait for current polling cycle to completely finish
        while (isWaitingForResponse) {
          await Future.delayed(Duration(milliseconds: 100));
        }
        // Additional wait for the pending flag to be cleared by notification handler
        while (isPendingIsolatorCommand) {
          await Future.delayed(Duration(milliseconds: 100));
        }
      }
      
      // Set isolator command execution flag to pause polling
      isExecutingIsolatorCommand = true;
      
      // Determine the appropriate command based on current state and requested state
      String command;
      final currentChargeState = itechworldData?.chargeIsolatorEnabled ?? false;
      
      if (enabled && currentChargeState) {
        // Enable both charge and discharge
        command = ISOLATOR_ENABLE_BOTH;
      } else if (enabled && !currentChargeState) {
        // Enable only discharge
        command = ISOLATOR_ENABLE_DISCHARGE;
      } else if (!enabled && currentChargeState) {
        // Disable discharge, keep charge
        command = ISOLATOR_ENABLE_CHARGE;
      } else {
        // Disable both
        command = ISOLATOR_DISABLE_BOTH;
      }

      await _sendIsolatorCommand(command, enabled ? "enable discharge" : "disable discharge");
    } catch (e) {
      // Clear pending state on error
      setState(() {
        dischargeIsolatorPending = null;
      });
    } finally {
      // Always clear the isolator command flag to resume polling
      isExecutingIsolatorCommand = false;
      
      // Resume polling immediately after isolator command completes
      if (itechworldConnected) {
        // Small delay to ensure isolator command is fully processed
        await Future.delayed(Duration(milliseconds: 200));
        _pollItechworldData();
      }
      //print('ISOLATOR DEBUG - Discharge isolator command complete (polling disabled for UX testing)');
    }
  }

  // Send isolator command and wait for confirmation before resuming polling
  Future<void> _sendIsolatorCommand(String commandHex, String description) async {
    if (itechworldWriteChar == null) {
      return;
    }

    try {
      //print('ISOLATOR DEBUG - Sending $description command: $commandHex');
      
      // Track notifications for confirmation
      List<String> notifications = [];
      StreamSubscription? notifSubscription;
      
      // Listen for confirmation notifications
      notifSubscription = itechworldNotifyChar?.lastValueStream.listen((data) {
        final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        notifications.add(hexData);
        //print('ISOLATOR DEBUG - Received notification during isolator command: $hexData');
      });

      // Send the isolator command
      final commandBytes = _hexStringToBytes(commandHex);
      await itechworldWriteChar!.write(commandBytes, withoutResponse: true);
      //print('ISOLATOR DEBUG - Isolator command sent, waiting for dde1 confirmation...');

      // Wait for dde1 confirmation notification (indicating isolator command was processed)
      bool confirmReceived = false;
      for (int i = 0; i < 50; i++) { // Wait up to 5 seconds
        await Future.delayed(Duration(milliseconds: 100));
        if (notifications.any((notif) => notif.contains("dde10000000077"))) {
          confirmReceived = true;
          //print('ISOLATOR DEBUG - dde1 confirmation received');
          break;
        }
      }

      if (!confirmReceived) {
        //print('ISOLATOR DEBUG - Warning: dde1 confirmation not received within timeout');
      }

      // if (confirmReceived) {
      //   // Send second write command
      //   final secondWriteBytes = _hexStringToBytes(ISOLATOR_SECOND_WRITE);
      //   await itechworldWriteChar!.write(secondWriteBytes, withoutResponse: true);

      //   // Wait for final confirmation
      //   for (int i = 0; i < 20; i++) {
      //     await Future.delayed(Duration(milliseconds: 100));
      //     if (notifications.any((notif) => notif.contains("dd010000000077"))) {
      //       break;
      //     }
      //   }
      // }

      notifSubscription?.cancel();
      
      // Additional wait to ensure isolator command processing is complete
      await Future.delayed(Duration(milliseconds: 500));
      //print('ISOLATOR DEBUG - Isolator command sequence complete');
      
    } catch (e) {
      //print('ISOLATOR DEBUG - Error in isolator command: $e');
    }
  }

  // Toggle Itechworld connection on/off
  Future<void> _toggleItechworldConnection(bool connect) async {
    if (connect) {
      // Start connection process
      setState(() {
        itechworldConnecting = true;
        itechworldConnected = false;
      });
      await _connectToItechworldByMAC();
    } else {
      // Disconnect from device
      await _disconnectItechworldDevice();
    }
  }

  // Connect to Itechworld device by MAC address (manual connection)
  Future<void> _connectToItechworldByMAC() async {
    try {
      // Start scanning to find the device
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));
      
      // Listen for scan results
      bool deviceFound = false;
      final scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (final result in results) {
          if (result.device.remoteId.toString().toUpperCase() == ITECHWORLD_MAC && !deviceFound) {
            deviceFound = true;
            await FlutterBluePlus.stopScan();
            await _connectToItechworldDevice(result.device);
            break;
          }
        }
      });

      // Wait for scan timeout
      await Future.delayed(Duration(seconds: 10));
      scanSubscription.cancel();
      await FlutterBluePlus.stopScan();

      if (!deviceFound) {
        setState(() {
          itechworldConnecting = false;
          itechworldConnected = false;
        });
      }
    } catch (e) {
      setState(() {
        itechworldConnecting = false;
        itechworldConnected = false;
      });
    }
  }

  // Disconnect from Itechworld device
  Future<void> _disconnectItechworldDevice() async {
    try {
      // Stop polling
      itechworldPollTimer?.cancel();
      pollWatchdog?.cancel();
      
      // Disconnect device
      if (itechworldDevice != null) {
        await itechworldDevice!.disconnect();
      }
      
      // Clear connection state
      setState(() {
        itechworldDevice = null;
        itechworldNotifyChar = null;
        itechworldWriteChar = null;
        itechworldConnecting = false;
        itechworldConnected = false;
        itechworldData = null;
        isWaitingForResponse = false;
        isRequestingCellVoltages = false;
        // Clear pending states on disconnect
        chargeIsolatorPending = null;
        dischargeIsolatorPending = null;
      });
    } catch (e) {
      // Silently handle disconnection errors
    }
  }

  // Topargee water tank connection methods
  Future<void> _toggleTopargeeConnection(bool connect) async {
    if (connect) {
      // Start connection process
      setState(() {
        topargeeConnecting = true;
        topargeeConnected = false;
      });
      await _connectToTopargeeByMAC();
    } else {
      // Disconnect from device
      await _disconnectTopargeeDevice();
    }
  }

  // Connect to Topargee device by MAC address
  Future<void> _connectToTopargeeByMAC() async {
    try {
      //print('TOPARGEE DEBUG - Starting scan for MAC: $TOPARGEE_MAC');
      
      // Start scanning to find the device
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 40));
      
      // Listen for scan results
      bool deviceFound = false;
      final scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (final result in results) {
          final deviceMac = result.device.remoteId.toString().toUpperCase();
          // //print('TOPARGEE DEBUG - Found device: $deviceMac');
          
          if (deviceMac == TOPARGEE_MAC.toUpperCase() && !deviceFound) {
            //print('TOPARGEE DEBUG - Target device found! Attempting connection...');
            deviceFound = true;
            await FlutterBluePlus.stopScan();
            await _connectToTopargeeDevice(result.device);
            break;
          }
        }
      });

      // Wait for scan timeout
      await Future.delayed(Duration(seconds: 40));
      scanSubscription.cancel();
      await FlutterBluePlus.stopScan();

      if (!deviceFound) {
        //print('TOPARGEE DEBUG - Device not found during scan timeout');
        setState(() {
          topargeeConnecting = false;
          topargeeConnected = false;
        });
      }
    } catch (e) {
      //print('TOPARGEE DEBUG - Error during scan: $e');
      setState(() {
        topargeeConnecting = false;
        topargeeConnected = false;
      });
    }
  }

  // Connect to Topargee device
  Future<void> _connectToTopargeeDevice(BluetoothDevice device) async {
    if (topargeeConnected || topargeeDevice?.remoteId == device.remoteId) {
      //print('TOPARGEE DEBUG - Already connected to this device');
      return; // Already connected to this device
    }

    try {
      //print('TOPARGEE DEBUG - Attempting to connect to device: ${device.remoteId}');
      
      // Connect to device
      await device.connect();
      topargeeDevice = device;
      //print('TOPARGEE DEBUG - Device connected, discovering services...');
      
      // Discover services
      final services = await device.discoverServices();
      //print('TOPARGEE DEBUG - Found ${services.length} services');
      
      // Find the characteristics we need
      for (final service in services) {
        //print('TOPARGEE DEBUG - Service UUID: ${service.uuid}');
        for (final characteristic in service.characteristics) {
          final charUuid = characteristic.uuid.toString().toLowerCase();
          //print('TOPARGEE DEBUG - Characteristic UUID: $charUuid');
          
          if (charUuid == 'fff4' || charUuid == TOPARGEE_NOTIFY_UUID.toLowerCase()) {
            topargeeNotifyChar = characteristic;
            //print('TOPARGEE DEBUG - Found notify characteristic');
          } else if (charUuid == 'fff1' || charUuid == TOPARGEE_WRITE_UUID.toLowerCase()) {
            topargeeWriteChar = characteristic;
            //print('TOPARGEE DEBUG - Found write characteristic');
          }
        }
      }
      
      if (topargeeNotifyChar != null && topargeeWriteChar != null) {
        //print('TOPARGEE DEBUG - Both characteristics found, enabling notifications...');
        
        // Enable notifications
        await topargeeNotifyChar!.setNotifyValue(true);
        
        // Listen for notifications
        topargeeNotifyChar!.lastValueStream.listen((data) {
          _handleTopargeeNotification(data);
        });
        
        setState(() {
          topargeeConnecting = false;
          topargeeConnected = true;
        });
        
        //print('TOPARGEE DEBUG - Connection successful! Starting polling...');
        
        // Start polling for data
        _startTopargeePolling();
      } else {
        //print('TOPARGEE DEBUG - Required characteristics not found - notify: ${topargeeNotifyChar != null}, write: ${topargeeWriteChar != null}');
        await device.disconnect();
        setState(() {
          topargeeConnecting = false;
          topargeeConnected = false;
        });
      }
    } catch (e) {
      //print('TOPARGEE DEBUG - Connection error: $e');
      topargeeDevice = null;
      topargeeNotifyChar = null;
      topargeeWriteChar = null;
      setState(() {
        topargeeConnecting = false;
        topargeeConnected = false;
      });
    }
  }

  // Disconnect from Topargee device
  Future<void> _disconnectTopargeeDevice() async {
    try {
      // Stop polling
      topargeePollTimer?.cancel();
      
      // Disconnect device
      if (topargeeDevice != null) {
        await topargeeDevice!.disconnect();
      }
      
      // Clear connection state
      setState(() {
        topargeeDevice = null;
        topargeeNotifyChar = null;
        topargeeWriteChar = null;
        topargeeConnecting = false;
        topargeeConnected = false;
        topargeeData = null;
        topargeeWaitingForResponse = false;
      });
    } catch (e) {
      // Silently handle disconnection errors
    }
  }

  // Start polling the Topargee device for data
  void _startTopargeePolling() {
    _pollTopargeeData();
  }

  // Poll Topargee for tank capacity and litres used
  Future<void> _pollTopargeeData() async {
    if (topargeeWriteChar == null || !topargeeConnected || topargeeWaitingForResponse) return;
    
    try {
      //print('TOPARGEE DEBUG - Starting poll cycle');
      topargeeWaitingForResponse = true;
      
      // Query tank capacity first
      final tankCapBytes = _hexStringToBytes(TANK_CAP_CMD);
      final tankCapChecksum = _xorChecksum(tankCapBytes);
      final tankCapFullCmd = tankCapBytes + [tankCapChecksum];
      
      //print('TOPARGEE DEBUG - Sending tank capacity command: ${tankCapFullCmd.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      await topargeeWriteChar!.write(tankCapFullCmd, withoutResponse: false);
      
      // Wait for response before sending next command
      await Future.delayed(Duration(milliseconds: 1000));
      
      // Query litres used
      final litresUsedBytes = _hexStringToBytes(LITRES_USED_CMD);
      final litresUsedChecksum = _xorChecksum(litresUsedBytes);
      final litresUsedFullCmd = litresUsedBytes + [litresUsedChecksum];
      
      //print('TOPARGEE DEBUG - Sending litres used command: ${litresUsedFullCmd.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      await topargeeWriteChar!.write(litresUsedFullCmd, withoutResponse: false);
      
      // Wait for response processing
      await Future.delayed(Duration(milliseconds: 1000));
      
      // Schedule next poll in 5 seconds
      topargeePollTimer?.cancel();
      topargeePollTimer = Timer(Duration(seconds: 5), () {
        topargeeWaitingForResponse = false;
        //print('TOPARGEE DEBUG - Poll timer expired, starting next cycle');
        _pollTopargeeData();
      });
      
    } catch (e) {
      //print('TOPARGEE DEBUG - Error during polling: $e');
      topargeeWaitingForResponse = false;
      // Retry in 5 seconds
      topargeePollTimer?.cancel();
      topargeePollTimer = Timer(Duration(seconds: 5), () => _pollTopargeeData());
    }
  }

  // Calculate XOR checksum for Topargee commands
  int _xorChecksum(List<int> dataBytes) {
    int result = 0;
    for (int b in dataBytes) {
      result ^= b;
    }
    return result;
  }

  // Reset tank meter to specified litres used (0 = full tank)
  Future<void> _resetTopargeTank([int litresUsed = 0]) async {
    if (topargeeWriteChar == null || !topargeeConnected) return;
    
    try {
      // //print('TOPARGEE DEBUG - Resetting tank to $litresUsed litres used');
      
      // Pause polling during reset
      bool wasWaiting = topargeeWaitingForResponse;
      topargeeWaitingForResponse = true;
      
      // Build reset command like Python script: 5ac701040000 + litres_used_bytes + padding + checksum
      final usedBytes = [(litresUsed >> 8) & 0xFF, litresUsed & 0xFF]; // Big-endian 16-bit
      final cmdPrefix = _hexStringToBytes("5ac701040000");
      final padding = List.filled(20 - cmdPrefix.length - usedBytes.length - 1, 0xff);
      final cmd = cmdPrefix + usedBytes + padding;
      final checksum = _xorChecksum(cmd);
      final fullCmd = cmd + [checksum];
      
      // //print('TOPARGEE DEBUG - Sending reset command: ${fullCmd.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      await topargeeWriteChar!.write(fullCmd, withoutResponse: false);
      
      // Wait for command to process
      await Future.delayed(Duration(milliseconds: 1000));
      
      // Resume polling
      topargeeWaitingForResponse = wasWaiting;
      
      // //print('TOPARGEE DEBUG - Tank reset command sent successfully');
      
    } catch (e) {
      // //print('TOPARGEE DEBUG - Error during tank reset: $e');
      topargeeWaitingForResponse = false;
    }
  }

  // Show confirmation dialog for tank reset
  Future<void> _showResetTankDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Reset Water Tank'),
          content: const Text('Are you sure you want to reset the tank meter to full?\n\nThis will set the "Litres Used" to 0, indicating a full tank.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reset Tank'),
            ),
          ],
        );
      },
    );
    
    if (confirmed == true) {
      await _resetTopargeTank(0); // Reset to 0 litres used (full tank)
    }
  }

  // Handle notifications from Topargee device
  void _handleTopargeeNotification(List<int> data) {
    //print('TOPARGEE DEBUG - Received notification: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    
    if (data.length < 8) {
      //print('TOPARGEE DEBUG - Notification too short: ${data.length} bytes');
      return;
    }
    
    // Check response type based on second byte (like Python script)
    final responseType = data[1];
    //print('TOPARGEE DEBUG - Response type: 0x${responseType.toRadixString(16).padLeft(2, '0')}');
    
    // Extract payload (remove header and checksum like Python: data[4:-1])
    final payload = data.sublist(4, data.length - 1);
    //print('TOPARGEE DEBUG - Payload: ${payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    
    if (payload.length >= 4) {
      // Extract 16-bit value from bytes 2-3 of payload (big-endian like Python)
      final value = (payload[2] << 8) | payload[3];
      //print('TOPARGEE DEBUG - Extracted value: $value');
      
      // Update tank data based on response type
      if (topargeeData == null) {
        // Initialize with received data
        if (responseType == 0xc3) { // Tank capacity response
          //print('TOPARGEE DEBUG - Initializing with tank capacity: $value');
          final newData = TopargeeWaterTankData(
            tankCapacity: value,
            litresUsed: 0,
            currentLitres: value,
            percentage: 100.0,
            deviceName: "Water Tank",
            lastUpdate: DateTime.now(),
          );
          setState(() {
            topargeeData = newData;
          });
        } else if (responseType == 0xc7) { // Litres used response
          //print('TOPARGEE DEBUG - Initializing with litres used: $value');
          final newData = TopargeeWaterTankData(
            tankCapacity: 0,
            litresUsed: value,
            currentLitres: 0,
            percentage: 0.0,
            deviceName: "Water Tank", 
            lastUpdate: DateTime.now(),
          );
          setState(() {
            topargeeData = newData;
          });
        }
      } else {
        // Update existing data
        if (responseType == 0xc3) { // Tank capacity response
          //print('TOPARGEE DEBUG - Updating tank capacity: $value (previous: ${topargeeData!.tankCapacity})');
          final currentLitres = value - topargeeData!.litresUsed;
          final percentage = value > 0 ? (currentLitres / value * 100) : 0.0;
          
          final newData = TopargeeWaterTankData(
            tankCapacity: value,
            litresUsed: topargeeData!.litresUsed,
            currentLitres: currentLitres,
            percentage: percentage,
            deviceName: topargeeData!.deviceName,
            lastUpdate: DateTime.now(),
          );
          setState(() {
            topargeeData = newData;
          });
        } else if (responseType == 0xc7) { // Litres used response
          //print('TOPARGEE DEBUG - Updating litres used: $value (previous: ${topargeeData!.litresUsed})');
          final currentLitres = topargeeData!.tankCapacity - value;
          final percentage = topargeeData!.tankCapacity > 0 ? (currentLitres / topargeeData!.tankCapacity * 100) : 0.0;
          
          final newData = TopargeeWaterTankData(
            tankCapacity: topargeeData!.tankCapacity,
            litresUsed: value,
            currentLitres: currentLitres,
            percentage: percentage,
            deviceName: topargeeData!.deviceName,
            lastUpdate: DateTime.now(),
          );
          setState(() {
            topargeeData = newData;
          });
        }
      }
    } else {
      //print('TOPARGEE DEBUG - Payload too short: ${payload.length} bytes');
    }
  }

  Future<void> _startScanning() async {
    if (isScanning) return;

    setState(() {
      isScanning = true;
    });

    try {
      // Listen to scan results
      scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          _processAdvertisement(result);
        }
      });

      // Start scanning with no timeout (continuous)
      await FlutterBluePlus.startScan();
      
      // Start watchdog timer to ensure scanning reliability
      _startScanningWatchdog();
      
      //print('VICTRON SCAN - Started continuous scanning with watchdog');
    } catch (e) {
      //print('VICTRON SCAN - Error starting scan: $e');
      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> _stopScanning() async {
    await FlutterBluePlus.stopScan();
    scanSubscription?.cancel();
    scanWatchdog?.cancel();
    setState(() {
      isScanning = false;
    });
    //print('VICTRON SCAN - Stopped scanning and watchdog');
  }

  // Itechworld device connection and polling
  Future<void> _connectToItechworldDevice(BluetoothDevice device) async {
    if (itechworldConnected || itechworldDevice?.remoteId == device.remoteId) {
      return; // Already connected to this device
    }

    try {
      // Connect to device
      await device.connect();
      itechworldDevice = device;
      
      // Discover services
      final services = await device.discoverServices();
      
      // Find the characteristics we need
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          final charUuid = characteristic.uuid.toString().toLowerCase();
          
          // Check for both short form (ff01) and full form UUIDs
          if (charUuid == 'ff01' || charUuid == ITECHWORLD_NOTIFY_UUID.toLowerCase()) {
            itechworldNotifyChar = characteristic;
          } else if (charUuid == 'ff02' || charUuid == ITECHWORLD_WRITE_UUID.toLowerCase()) {
            itechworldWriteChar = characteristic;
          }
        }
      }
      
      if (itechworldNotifyChar != null && itechworldWriteChar != null) {
        // Enable notifications
        await itechworldNotifyChar!.setNotifyValue(true);
        
        // Listen for notifications
        itechworldNotifyChar!.lastValueStream.listen((data) {
          _handleItechworldNotification(data);
        });
        
        setState(() {
          itechworldConnecting = false;
          itechworldConnected = true;
        });
        
        // Start polling for data
        _startItechworldPolling();
      } else {
        await device.disconnect();
        setState(() {
          itechworldConnecting = false;
          itechworldConnected = false;
        });
      }
    } catch (e) {
      itechworldDevice = null;
      itechworldNotifyChar = null;
      itechworldWriteChar = null;
      setState(() {
        itechworldConnecting = false;
        itechworldConnected = false;
      });
    }
  }

  // Start polling the Itechworld device for data (status-driven)
  void _startItechworldPolling() {
    // Start with immediate poll, then use responsive polling
    _pollItechworldData();
  }

  // Responsive poll for Itechworld data blocks
  Future<void> _pollItechworldData() async {
    if (itechworldWriteChar == null || !itechworldConnected) return;
    
    // Don't send new poll if already waiting for response, executing isolator command, or isolator command is pending
    if (isWaitingForResponse || isExecutingIsolatorCommand || isPendingIsolatorCommand) return;
    
    try {
      itechworldPollCount++;
      
      // Determine what to request: every 3rd poll gets cell voltages
      final shouldRequestCellVoltages = (itechworldPollCount % 3 == 0);
      
      if (shouldRequestCellVoltages) {
        // Reset all blocks for cell voltage request
        itechworldCycleData = ["", "", "", ""];
        isRequestingCellVoltages = true;
        
        // Send cell voltage request - expects single dd04 block response (no "77" end marker)
        final finalBlockCmd = _hexStringToBytes(FINAL_BLOCK_CMD);
        await itechworldWriteChar!.write(finalBlockCmd, withoutResponse: true);
        
        // Set waiting state with shorter timeout since it's just one block
        isWaitingForResponse = true;
        _startPollWatchdog(Duration(milliseconds: 1000)); // 1 second for single block
        
      } else {
        // Reset blocks 1-3, preserve block 4 (cell voltages)
        final preservedBlock4 = itechworldCycleData[3];
        itechworldCycleData = ["", "", "", preservedBlock4];
        isRequestingCellVoltages = false;
        
        // Send regular data poll - expects 3 notifications: Block1(dd03) + Block2(other) + end marker(0x77)
        final pollCmd = _hexStringToBytes(POLL_CMD);
        await itechworldWriteChar!.write(pollCmd, withoutResponse: true);
        
        // Set waiting state with longer timeout for multiple blocks
        isWaitingForResponse = true;
        _startPollWatchdog(Duration(milliseconds: 2000)); // 2 seconds for multiple blocks
      }
      
    } catch (e) {
      // Reset state on error and try again in 1 second
      isWaitingForResponse = false;
      itechworldPollTimer?.cancel();
      itechworldPollTimer = Timer(Duration(seconds: 1), () => _pollItechworldData());
    }
  }

  // Start watchdog timer with configurable duration
  void _startPollWatchdog([Duration? timeout]) {
    pollWatchdog?.cancel();
    final watchdogTimeout = timeout ?? Duration(seconds: 2);
    pollWatchdog = Timer(watchdogTimeout, () {
      // Watchdog timeout - continue with next poll
      isWaitingForResponse = false;
      pollWatchdog?.cancel();
      
      // Parse any data we have received so far
      _parseItechworldData();
      
      // Schedule next poll immediately
      if (itechworldConnected) {
        _pollItechworldData();
      }
    });
  }

  // Check if we have received all expected blocks for current request
  bool _hasReceivedExpectedBlocks() {
    if (isRequestingCellVoltages) {
      // For FINAL_BLOCK_CMD (cell voltage request), success is when we receive dd04 block
      return itechworldCycleData[3].isNotEmpty;
    } else {
      // For POLL_CMD (regular data request), success is when we receive:
      // 1. Block 1 (dd03 - main data)
      // 2. Block 2 (other - isolator status) 
      // 3. End marker (0x77) - handled separately in notification handler
      return itechworldCycleData[0].isNotEmpty && itechworldCycleData[1].isNotEmpty;
    }
  }

  // Handle notifications from Itechworld device
  void _handleItechworldNotification(List<int> data) {
    final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    // Handle single-byte end marker (only for POLL_CMD responses)
    if (hexData.length == 2 && hexData == '77') {
      // End marker received - check if we have all expected blocks for POLL_CMD
      if (isWaitingForResponse && !isRequestingCellVoltages && _hasReceivedExpectedBlocks()) {
        // POLL_CMD success: received Block 1 + Block 2 + end marker (0x77)
        isWaitingForResponse = false;
        pollWatchdog?.cancel();
        
        // Use latest block 4 if current cycle doesn't have it
        if (itechworldCycleData[3].isEmpty) {
          itechworldCycleData[3] = itechworldLatestBlock4;
        }
        
        // Parse the data and update UI
        _parseItechworldData();
        
        // Check if there's a pending isolator command to execute
        if (isPendingIsolatorCommand) {
          isPendingIsolatorCommand = false;
        } else {
          // Send next poll immediately only if no isolator command is pending/executing
          if (itechworldConnected && !isExecutingIsolatorCommand) {
            _pollItechworldData();
          }
        }
      }
      return;
    }
    
    // Identify blocks by their headers and content
    if (hexData.length >= 4) {
      final header = hexData.substring(0, 4);
      
      if (header == 'dd03') {
        // Block 1: Main data (voltage, current, amp-hours) - always dd03
        if (itechworldCycleData[0].isEmpty) {
          itechworldCycleData[0] = hexData;
        }
      } else if (header == 'dd04') {
        // Block 4: Cell voltage data - always dd04
        itechworldCycleData[3] = hexData;
        itechworldLatestBlock4 = hexData;
        
        // FINAL_BLOCK_CMD success: received dd04 block
        if (isWaitingForResponse && isRequestingCellVoltages) {
          isWaitingForResponse = false;
          pollWatchdog?.cancel();
          
          // Parse the data and update UI
          _parseItechworldData();
          
          // Check if there's a pending isolator command to execute
          if (isPendingIsolatorCommand) {
            //print('ISOLATOR DEBUG - Cell voltage cycle complete, clearing pending isolator flag');
            isPendingIsolatorCommand = false;
          } else {
            // Send next poll immediately only if no isolator command is pending/executing
            if (itechworldConnected && !isExecutingIsolatorCommand) {
              _pollItechworldData();
            }
          }
        }
      } else {
        // Block 2: Isolator status data (any header that's not dd03 or dd04)
        // Only capture if Block 2 slot is empty and this is during a POLL_CMD
        // Exclude confirmation notifications (dde1 and dd01 patterns)
        if (itechworldCycleData[1].isEmpty && !isRequestingCellVoltages && 
            !header.startsWith('dde1') && !header.startsWith('dd01')) {
          itechworldCycleData[1] = hexData;
        }
      }
    }
  }

  // Convert hex string to bytes
  List<int> _hexStringToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  // Parse Itechworld data blocks similar to Python script
  void _parseItechworldData() {
    try {
      // Start with previous values to avoid resetting to 0 if we don't have complete data
      double voltage = itechworldData?.voltage ?? 0.0;
      double current = itechworldData?.current ?? 0.0;
      double ampHours = itechworldData?.ampHours ?? 0.0;
      // Start with previous cell voltages and isolator states to avoid resetting
      double cell1V = itechworldData?.cell1Voltage ?? 0.0;
      double cell2V = itechworldData?.cell2Voltage ?? 0.0;
      double cell3V = itechworldData?.cell3Voltage ?? 0.0;
      double cell4V = itechworldData?.cell4Voltage ?? 0.0;
      bool chargeIsolatorEnabled = itechworldData?.chargeIsolatorEnabled ?? false;
      bool dischargeIsolatorEnabled = itechworldData?.dischargeIsolatorEnabled ?? false;

      // Parse Block 1 (03 Block 1): Current, Voltage, Amp-hours
      final block1 = itechworldCycleData[0];
      if (block1.length >= 20) {
        // Current from bytes 6-7 (hex positions 12-16)
        final currentHex = block1.substring(12, 16);
        final currentBytes = _hexStringToBytes(currentHex);
        var currentValue = (currentBytes[0] << 8) | currentBytes[1];
        // Convert to signed 16-bit value (two's complement)
        if (currentValue & 0x8000 != 0) {
          currentValue = currentValue - 0x10000;
        }
        current = currentValue / 100.0; // Convert to amps
        
        // Voltage from bytes 4-5 (hex positions 8-12)
        final voltageHex = block1.substring(8, 12);
        final voltageBytes = _hexStringToBytes(voltageHex);
        final voltageValue = (voltageBytes[0] << 8) | voltageBytes[1];
        voltage = voltageValue / 100.0; // Convert to volts
        
        // Amp-hours from bytes 8-9 (hex positions 16-20)
        final ahHex = block1.substring(16, 20);
        final ahBytes = _hexStringToBytes(ahHex);
        final ahValue = (ahBytes[0] << 8) | ahBytes[1];
        ampHours = ahValue / 100.0; // Convert to amp-hours
      }

      // Parse Block 2 (03 Block 2): Isolator status
      final block2 = itechworldCycleData[1];
      if (block2.length >= 10) {
        // Only show debug output when isolator commands are pending (user pressed toggle)
        if (chargeIsolatorPending != null || dischargeIsolatorPending != null) {
          //print('ISOLATOR TOGGLE DEBUG - Block 2 data: "$block2"');
          //print('ISOLATOR TOGGLE DEBUG - Nibble at position 9: "${block2[9]}"');
          //print('ISOLATOR TOGGLE DEBUG - Pending: charge=$chargeIsolatorPending, discharge=$dischargeIsolatorPending');
        }
        
        // Isolator status from nibble 9 (position 9) - matching Python script
        final nibble9 = block2[9]; // Position 9
        
        // Parse isolator status based on nibble 9 (exactly like Python script)
        switch (nibble9) {
          case '3':
            chargeIsolatorEnabled = false;
            dischargeIsolatorEnabled = false;
            break;
          case '1':
            chargeIsolatorEnabled = false;
            dischargeIsolatorEnabled = true;
            break;
          case '2':
            chargeIsolatorEnabled = true;
            dischargeIsolatorEnabled = false;
            break;
          case '0':
            chargeIsolatorEnabled = true;
            dischargeIsolatorEnabled = true;
            break;
          default:
            // Keep previous state for unknown values
            chargeIsolatorEnabled = itechworldData?.chargeIsolatorEnabled ?? false;
            dischargeIsolatorEnabled = itechworldData?.dischargeIsolatorEnabled ?? false;
        }
        
        // Clear pending states if we got a valid response and sufficient time has passed
        if (nibble9 == '3' || nibble9 == '1' || nibble9 == '2' || nibble9 == '0') {
          // Ensure loading indicator is visible for at least 800ms from when command was initiated
          if (lastIsolatorCommand != null) {
            final timeSinceCommand = DateTime.now().difference(lastIsolatorCommand!).inMilliseconds;
            final minDisplayTime = 800; // Minimum time to show loading indicator
            
            if (timeSinceCommand >= minDisplayTime) {
              // Enough time has passed, clear immediately
              setState(() {
                chargeIsolatorPending = null;
                dischargeIsolatorPending = null;
              });
            } else {
              // Wait for remaining time before clearing
              final remainingTime = minDisplayTime - timeSinceCommand;
              Future.delayed(Duration(milliseconds: remainingTime), () {
                if (mounted) {
                  setState(() {
                    chargeIsolatorPending = null;
                    dischargeIsolatorPending = null;
                  });
                }
              });
            }
          } else {
            // No timestamp available, use default delay
            Future.delayed(Duration(milliseconds: 500), () {
              if (mounted) {
                setState(() {
                  chargeIsolatorPending = null;
                  dischargeIsolatorPending = null;
                });
              }
            });
          }
        }
      }

      // Parse Block 4 (04 Block 1): Cell voltages
      final block4 = itechworldCycleData[3];
      if (block4.isNotEmpty && block4.length >= 24) {
        // Cell 1 from bytes 4-5 (hex positions 8-12)
        final cell1Hex = block4.substring(8, 12);
        final cell1Bytes = _hexStringToBytes(cell1Hex);
        final cell1Value = (cell1Bytes[0] << 8) | cell1Bytes[1];
        cell1V = cell1Value / 1000.0; // Convert to volts
        
        // Cell 2 from bytes 6-7 (hex positions 12-16)
        final cell2Hex = block4.substring(12, 16);
        final cell2Bytes = _hexStringToBytes(cell2Hex);
        final cell2Value = (cell2Bytes[0] << 8) | cell2Bytes[1];
        cell2V = cell2Value / 1000.0;
        
        // Cell 3 from bytes 8-9 (hex positions 16-20)
        final cell3Hex = block4.substring(16, 20);
        final cell3Bytes = _hexStringToBytes(cell3Hex);
        final cell3Value = (cell3Bytes[0] << 8) | cell3Bytes[1];
        cell3V = cell3Value / 1000.0;
        
        // Cell 4 from bytes 10-11 (hex positions 20-24)
        final cell4Hex = block4.substring(20, 24);
        final cell4Bytes = _hexStringToBytes(cell4Hex);
        final cell4Value = (cell4Bytes[0] << 8) | cell4Bytes[1];
        cell4V = cell4Value / 1000.0;
      }

      // Update the UI with parsed data
      final power = voltage * current; // Calculate power in watts
      setState(() {
        itechworldData = ItechworldBatteryData(
          voltage: voltage,
          current: current,
          power: power,
          ampHours: ampHours,
          cell1Voltage: cell1V,
          cell2Voltage: cell2V,
          cell3Voltage: cell3V,
          cell4Voltage: cell4V,
          chargeIsolatorEnabled: chargeIsolatorEnabled,
          dischargeIsolatorEnabled: dischargeIsolatorEnabled,
          lastUpdate: DateTime.now(),
        );
      });
    } catch (e) {
      // Silently handle parsing errors
    }
  }

  Widget _buildShuntCard() {
    if (shuntData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.battery_charging_full, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text('SmartShunt', style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
              const SizedBox(height: 8),
              const Text('No data received', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.battery_charging_full, 
                     color: isShuntDataFresh ? Colors.green[600] : Colors.grey[600]),
                const SizedBox(width: 8),
                Text('SmartShunt', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isShuntDataFresh ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Battery Voltage', style: Theme.of(context).textTheme.bodySmall),
                      Text('${shuntData!.batteryVoltage.toStringAsFixed(2)} V', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Battery Current', style: Theme.of(context).textTheme.bodySmall),
                      Text('${shuntData!.batteryCurrent.toStringAsFixed(2)} A', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Power', style: Theme.of(context).textTheme.bodySmall),
                      Text('${(shuntData!.batteryVoltage * shuntData!.batteryCurrent).toStringAsFixed(2)} W',
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('State of Charge', style: Theme.of(context).textTheme.bodySmall),
                      Text('${shuntData!.stateOfCharge.toStringAsFixed(1)} %', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Consumed Ah', style: Theme.of(context).textTheme.bodySmall),
                      Text('${shuntData!.consumedAh.toStringAsFixed(1)} Ah', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Last updated: ${shuntData!.lastUpdate.toString().substring(11, 19)}', 
                 style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildSolarCard() {
    if (solarData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.solar_power, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text('SmartSolar', style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
              const SizedBox(height: 8),
              const Text('No data received', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.solar_power, 
                     color: isSolarDataFresh ? Colors.orange[600] : Colors.grey[600]),
                const SizedBox(width: 8),
                Text('SmartSolar', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSolarDataFresh ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PV Power', style: Theme.of(context).textTheme.bodySmall),
                      Text('${solarData!.pvPower.toStringAsFixed(0)} W', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Battery Voltage', style: Theme.of(context).textTheme.bodySmall),
                      Text('${solarData!.batteryVoltage.toStringAsFixed(2)} V', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Battery Current', style: Theme.of(context).textTheme.bodySmall),
                      Text('${solarData!.batteryCurrent.toStringAsFixed(1)} A', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yield Today', style: Theme.of(context).textTheme.bodySmall),
                      Text('${solarData!.yieldToday.toStringAsFixed(2)} kWh', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Last updated: ${solarData!.lastUpdate.toString().substring(11, 19)}', 
                 style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildItechworldCard() {
    if (itechworldData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.battery_full, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Itechworld Battery', 
                         style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  itechworldConnecting 
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                        ),
                      )
                    : Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: itechworldStatusColor,
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connection',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          itechworldConnecting 
                            ? 'Connecting to device...'
                            : itechworldConnected 
                              ? 'Connected' 
                              : 'Disconnected',
                          style: TextStyle(
                            color: itechworldConnecting 
                              ? Colors.orange 
                              : itechworldConnected 
                                ? Colors.green 
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: itechworldConnecting || itechworldConnected,
                    onChanged: itechworldConnecting ? null : (value) => _toggleItechworldConnection(value),
                    activeColor: itechworldConnecting ? Colors.orange : Colors.green,
                  ),
                ],
              ),
              if (itechworldConnected) ...[
                const SizedBox(height: 8),
                Text(
                  'Device: ${ITECHWORLD_MAC}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.battery_full, 
                     color: isItechworldDataFresh ? Colors.blue[600] : Colors.grey[600]),
                const SizedBox(width: 8),
                Text('Itechworld Battery', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: itechworldStatusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Connection toggle
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connection',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        itechworldConnecting 
                          ? 'Connecting to device...'
                          : itechworldConnected 
                            ? 'Connected' 
                            : 'Disconnected',
                        style: TextStyle(
                          color: itechworldConnecting 
                            ? Colors.orange 
                            : itechworldConnected 
                              ? Colors.green 
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: itechworldConnecting || itechworldConnected,
                  onChanged: itechworldConnecting ? null : (value) => _toggleItechworldConnection(value),
                  activeColor: itechworldConnecting ? Colors.orange : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Main battery stats - Row 1: Voltage and Power
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Voltage', style: Theme.of(context).textTheme.bodySmall),
                      Text('${itechworldData!.voltage.toStringAsFixed(2)} V', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Power', style: Theme.of(context).textTheme.bodySmall),
                      Text('${itechworldData!.power.toStringAsFixed(1)} W', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Main battery stats - Row 2: Current and Amp Hours
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current', style: Theme.of(context).textTheme.bodySmall),
                      Text('${itechworldData!.current.toStringAsFixed(2)} A', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Amp Hours', style: Theme.of(context).textTheme.bodySmall),
                      Text('${itechworldData!.ampHours.toStringAsFixed(2)} Ah', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Cell voltages
            Text('Cell Voltages', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cell 1', style: Theme.of(context).textTheme.bodySmall),
                      Text('${itechworldData!.cell1Voltage.toStringAsFixed(3)} V', 
                           style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cell 2', style: Theme.of(context).textTheme.bodySmall),
                      Text('${itechworldData!.cell2Voltage.toStringAsFixed(3)} V', 
                           style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cell 3', style: Theme.of(context).textTheme.bodySmall),
                      Text('${itechworldData!.cell3Voltage.toStringAsFixed(3)} V', 
                           style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cell 4', style: Theme.of(context).textTheme.bodySmall),
                      Text('${itechworldData!.cell4Voltage.toStringAsFixed(3)} V', 
                           style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Isolator controls
            Text('Isolator Controls', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Charge Isolator', style: Theme.of(context).textTheme.bodySmall),
                          if (chargeIsolatorPending != null) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Switch(
                        value: chargeIsolatorPending ?? itechworldData!.chargeIsolatorEnabled,
                        onChanged: (value) {
                          _toggleChargeIsolator(value);
                        },
                        // Show different colors for pending state
                        activeColor: chargeIsolatorPending != null ? Colors.orange : null,
                        inactiveThumbColor: chargeIsolatorPending != null ? Colors.grey[400] : null,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Discharge Isolator', style: Theme.of(context).textTheme.bodySmall),
                          if (dischargeIsolatorPending != null) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Switch(
                        value: dischargeIsolatorPending ?? itechworldData!.dischargeIsolatorEnabled,
                        onChanged: (value) {
                          _toggleDischargeIsolator(value);
                        },
                        // Show different colors for pending state
                        activeColor: dischargeIsolatorPending != null ? Colors.orange : null,
                        inactiveThumbColor: dischargeIsolatorPending != null ? Colors.grey[400] : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Last updated: ${itechworldData!.lastUpdate.toString().substring(11, 19)}', 
                 style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildTopargeeCard() {
    if (topargeeData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.water_drop, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Water Tank', 
                         style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  topargeeConnecting 
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                        ),
                      )
                    : Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: topargeeStatusColor,
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connection',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          topargeeConnecting 
                            ? 'Connecting to device...'
                            : topargeeConnected 
                              ? 'Connected' 
                              : 'Disconnected',
                          style: TextStyle(
                            color: topargeeConnecting 
                              ? Colors.orange 
                              : topargeeConnected 
                                ? Colors.green 
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: topargeeConnecting || topargeeConnected,
                    onChanged: topargeeConnecting ? null : (value) => _toggleTopargeeConnection(value),
                    activeColor: topargeeConnecting ? Colors.orange : Colors.green,
                  ),
                ],
              ),
              if (topargeeConnected) ...[
                const SizedBox(height: 8),
                Text(
                  'Device: ${TOPARGEE_MAC}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_drop, 
                     color: isTopargeeDataFresh ? Colors.blue[600] : Colors.grey[600]),
                const SizedBox(width: 8),
                Text('Water Tank', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: topargeeStatusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Connection toggle
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connection',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        topargeeConnecting 
                          ? 'Connecting to device...'
                          : topargeeConnected 
                            ? 'Connected' 
                            : 'Disconnected',
                        style: TextStyle(
                          color: topargeeConnecting 
                            ? Colors.orange 
                            : topargeeConnected 
                              ? Colors.green 
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: topargeeConnecting || topargeeConnected,
                  onChanged: topargeeConnecting ? null : (value) => _toggleTopargeeConnection(value),
                  activeColor: topargeeConnecting ? Colors.orange : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Tank statistics - Row 1: Current Litres and Percentage
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current Litres', style: Theme.of(context).textTheme.bodySmall),
                      Text('${topargeeData!.currentLitres} L', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Remaining', style: Theme.of(context).textTheme.bodySmall),
                      Text('${topargeeData!.percentage.toStringAsFixed(1)} %', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Tank statistics - Row 2: Tank Capacity and Litres Used
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tank Capacity', style: Theme.of(context).textTheme.bodySmall),
                      Text('${topargeeData!.tankCapacity} L', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Litres Used', style: Theme.of(context).textTheme.bodySmall),
                      Text('${topargeeData!.litresUsed} L', 
                           style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Reset tank button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: topargeeConnected ? _showResetTankDialog : null,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset Tank to Full'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: topargeeConnected ? Colors.blue : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Device info
            Text('Device: ${topargeeData!.deviceName}', 
                 style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Last updated: ${topargeeData!.lastUpdate.toString().substring(11, 19)}', 
                 style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Direct Access'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isScanning ? _stopScanning : _startScanning,
                    icon: Icon(isScanning ? Icons.stop : Icons.play_arrow),
                    label: Text(isScanning ? 'Stop Scanning' : 'Start Scanning'),
                  ),
                ),
              ],
            ),
          ),
          if (isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isScanning ? Colors.blue : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('Scanning', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isShuntDataFresh ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('SmartShunt', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSolarDataFresh ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('SmartSolar', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isItechworldDataFresh ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('Itechworld', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isTopargeeDataFresh ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('Water Tank', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildShuntCard(),
                const SizedBox(height: 16),
                _buildSolarCard(),
                const SizedBox(height: 16),
                _buildItechworldCard(),
                const SizedBox(height: 16),
                _buildTopargeeCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BLEScannerPage extends StatefulWidget {
  const BLEScannerPage({super.key});

  @override
  State<BLEScannerPage> createState() => _BLEScannerPageState();
}

class _BLEScannerPageState extends State<BLEScannerPage> {
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  StreamSubscription<List<ScanResult>>? scanSubscription;
  String statusMessage = 'Ready to look for Tallulah';

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkBluetoothState() async {
    if (await FlutterBluePlus.isSupported == false) {
      setState(() {
        statusMessage = 'Bluetooth not supported by this device';
      });
      return;
    }

    BluetoothAdapterState adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      setState(() {
        statusMessage = 'Please turn on Bluetooth';
      });
      return;
    }

    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    
    if (!allGranted) {
      setState(() {
        statusMessage = 'Please grant all permissions to scan for devices';
      });
    } else {
      setState(() {
        statusMessage = 'Ready to scan for ESP32-Telemetry';
      });
    }
  }

  Future<void> _startScan() async {
    if (isScanning) return;

    setState(() {
      scanResults.clear();
      isScanning = true;
      statusMessage = 'Looking for Tallulah...';
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          // Filter for ESP32-Telemetry devices or devices with our service UUID
          scanResults = results.where((result) {
            String deviceName = result.device.platformName.toLowerCase();
            List<Guid> serviceUuids = result.advertisementData.serviceUuids;
            
            return deviceName.contains('esp32') || 
                   deviceName.contains('telemetry') ||
                   deviceName.contains('tallulah') ||
                   serviceUuids.any((uuid) => uuid.toString().toLowerCase() == ESP32_SERVICE_UUID.toLowerCase());
          }).toList();
        });
      });

      await Future.delayed(const Duration(seconds: 5));
      await _stopScan();
    } catch (e) {
      setState(() {
        statusMessage = 'Error scanning: $e';
        isScanning = false;
      });
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    scanSubscription?.cancel();
    setState(() {
      isScanning = false;
      statusMessage = scanResults.isEmpty 
          ? 'Couldn\'t find Tallulah :('
          // : 'Found ${scanResults.length} ESP32 device(s)';
          : 'Found Tallulah!';
    });
  }

  void _connectToDevice(BluetoothDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ESP32ControllerPage(device: device),
      ),
    );
  }

  Widget _buildDeviceCard(ScanResult result) {
    String deviceName = result.device.platformName.isNotEmpty 
        ? result.device.platformName 
        : 'Unknown ESP32 Device';
    
    String deviceId = result.device.remoteId.toString();
    int rssi = result.rssi;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(
          Icons.memory,
          color: Colors.blue,
        ),
        title: Text(
          deviceName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: $deviceId'),
            Text('RSSI: $rssi dBm'),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _connectToDevice(result.device),
          child: const Text('Connect'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const FlutterLogo(size: 32),
            const SizedBox(width: 12),
            const Text('Tallulah'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  statusMessage,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isScanning ? null : _startScan,
                      icon: Icon(isScanning ? Icons.hourglass_empty : Icons.search),
                      label: Text(isScanning ? 'Scanning...' : 'Scan for Tallulah'),
                    ),
                    ElevatedButton.icon(
                      onPressed: isScanning ? _stopScan : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Scan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          
          Expanded(
            child: scanResults.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FlutterLogo(size: 120),
                        SizedBox(height: 24),
                        Text(
                          'Tallulah',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No ESP32-Telemetry devices found.\nMake sure your ESP32 is powered on and advertising.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: scanResults.length,
                    itemBuilder: (context, index) {
                      return _buildDeviceCard(scanResults[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ESP32 Telemetry Dashboard
class ESP32ControllerPage extends StatefulWidget {
  final BluetoothDevice device;

  const ESP32ControllerPage({super.key, required this.device});

  @override
  State<ESP32ControllerPage> createState() => _ESP32ControllerPageState();
}

class _ESP32ControllerPageState extends State<ESP32ControllerPage> with TickerProviderStateMixin {
  bool isConnected = false;
  bool isSubscribed = false;
  TelemetryData? telemetryData;
  int updateRateMs = 1000;
  DateTime? lastDataUpdate;
  int currentRssi = -100; // Initialize with weak signal
  
  BluetoothCharacteristic? telemetryCharacteristic;
  BluetoothCharacteristic? updateRateCharacteristic;
  StreamSubscription<List<int>>? telemetrySubscription;
  StreamSubscription<BluetoothConnectionState>? connectionSubscription;
  Timer? _rssiTimer;
  
  late AnimationController _solarAnimationController;
  late AnimationController _tankFlowController;
  late Animation<double> _solarPulse;
  late Animation<double> _tankFlow;
  
  final TextEditingController _updateRateController = TextEditingController();
  String statusMessage = 'Connecting...';

  @override
  void initState() {
    super.initState();
    _updateRateController.text = updateRateMs.toString();
    
    // Initialize animations
    _solarAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _tankFlowController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    
    _solarPulse = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _solarAnimationController, curve: Curves.easeInOut),
    );
    _tankFlow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _tankFlowController, curve: Curves.linear),
    );
    
    _setupConnectionListener();
    _connectToDevice();
  }

  @override
  void dispose() {
    telemetrySubscription?.cancel();
    connectionSubscription?.cancel();
    _solarAnimationController.dispose();
    _tankFlowController.dispose();
    _rssiTimer?.cancel();
    widget.device.disconnect();
    _updateRateController.dispose();
    super.dispose();
  }

  void _setupConnectionListener() {
    connectionSubscription = widget.device.connectionState.listen((state) {
      //print('Connection state changed: $state');
      
      bool wasConnected = isConnected;
      bool nowConnected = (state == BluetoothConnectionState.connected);
      
      setState(() {
        isConnected = nowConnected;
        
        if (!isConnected && wasConnected) {
          // Only clean up if we were previously connected
          isSubscribed = false;
          telemetryCharacteristic = null;
          updateRateCharacteristic = null;
          telemetrySubscription?.cancel();
          _rssiTimer?.cancel();
          _rssiTimer = null;
          statusMessage = 'Device disconnected';
          _solarAnimationController.stop();
          _tankFlowController.stop();
        } else if (isConnected && !wasConnected) {
          statusMessage = 'Device connected';
        }
      });
      
      // Only show disconnection dialog if we were actually connected before
      if (state == BluetoothConnectionState.disconnected && wasConnected) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted && !isConnected) {
            _showDisconnectionDialog();
          }
        });
      }
    });
  }

  void _showDisconnectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Device Disconnected'),
          content: const Text('The ESP32 device has been disconnected. Would you like to try reconnecting?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to scanner
              },
              child: const Text('Back to Scanner'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _connectToDevice();
              },
              child: const Text('Reconnect'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _connectToDevice() async {
    setState(() {
      statusMessage = 'Connecting to ESP32...';
      isConnected = false;
    });
    
    try {
      // Check if already connected
      BluetoothConnectionState currentState = await widget.device.connectionState.first;
      if (currentState == BluetoothConnectionState.connected) {
        //print('Device already connected, proceeding to service discovery');
        setState(() {
          isConnected = true;
          statusMessage = 'Already connected! Discovering services...';
        });
        await _discoverServices();
        return;
      }
      
      //print('Connecting to device...');
      await widget.device.connect(timeout: const Duration(seconds: 15));
      
      // Wait a bit for connection to stabilize
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify connection
      currentState = await widget.device.connectionState.first;
      if (currentState == BluetoothConnectionState.connected) {
        setState(() {
          isConnected = true;
          statusMessage = 'Connected! Discovering services...';
        });
        
        await _discoverServices();
      } else {
        throw Exception('Connection verification failed');
      }
    } catch (e) {
      //print('Connection error: $e');
      setState(() {
        isConnected = false;
        statusMessage = 'Connection failed: $e';
      });
      
      // Show retry dialog after a short delay
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _showRetryDialog();
      }
    }
  }

  void _showRetryDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Connection Failed'),
          content: Text('Failed to connect to ESP32 device.\n\nError: $statusMessage'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to scanner
              },
              child: const Text('Back to Scanner'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _connectToDevice();
              },
              child: const Text('Retry'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _discoverServices() async {
    try {
      // Check connection before proceeding
      BluetoothConnectionState currentState = await widget.device.connectionState.first;
      if (currentState != BluetoothConnectionState.connected) {
        throw Exception('Device not connected during service discovery');
      }
      
      //print('Starting service discovery...');
      List<BluetoothService> services = await widget.device.discoverServices();
      //print('Found ${services.length} services');
      
      for (BluetoothService service in services) {
        //print('Service: ${service.uuid}');
        if (service.uuid.toString().toLowerCase() == ESP32_SERVICE_UUID.toLowerCase()) {
          //print('Found ESP32 telemetry service!');
          
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            String charUuid = characteristic.uuid.toString().toLowerCase();
            //print('Characteristic: $charUuid');
            
            if (charUuid == TELEMETRY_CHAR_UUID.toLowerCase()) {
              telemetryCharacteristic = characteristic;
              //print('Found telemetry characteristic');
              
              // Read initial telemetry data
              try {
                List<int> value = await characteristic.read();
                //print('Read ${value.length} bytes of telemetry data');
                if (value.length >= 96) {
                  telemetryData = TelemetryData.fromBytes(value);
                  //print('Parsed telemetry data successfully');
                } else {
                  //print('Insufficient data: ${value.length} bytes');
                }
              } catch (e) {
                //print('Error reading initial telemetry data: $e');
                // Don't fail entirely if initial read fails
              }
            } else if (charUuid == UPDATE_RATE_CHAR_UUID.toLowerCase()) {
              updateRateCharacteristic = characteristic;
              //print('Found update rate characteristic');
              
              // Read initial update rate
              try {
                List<int> value = await characteristic.read();
                if (value.length >= 4) {
                  updateRateMs = _bytesToInt32(value);
                  _updateRateController.text = updateRateMs.toString();
                  //print('Read update rate: ${updateRateMs}ms');
                }
              } catch (e) {
                //print('Error reading initial update rate: $e');
                // Don't fail entirely if initial read fails
              }
            }
          }
          break;
        }
      }
      
      setState(() {
        if (telemetryCharacteristic != null && updateRateCharacteristic != null) {
          statusMessage = 'Ready! Starting telemetry updates...';
          //print('Service discovery complete - ready for telemetry');
        } else {
          statusMessage = 'ESP32 telemetry service not found. Check device compatibility.';
          //print('Service discovery failed - missing characteristics');
        }
      });
      
      // Automatically start updates if characteristics are available
      if (telemetryCharacteristic != null && updateRateCharacteristic != null) {
        _startRssiUpdates();
        await _toggleSubscription();
      }
    } catch (e) {
      //print('Service discovery error: $e');
      setState(() {
        statusMessage = 'Service discovery failed: $e';
        isConnected = false;
      });
    }
  }

  int _bytesToInt32(List<int> bytes) {
    if (bytes.length < 4) return 0;
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }

  List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  Future<void> _toggleSubscription() async {
    if (telemetryCharacteristic == null) return;

    try {
      if (!isSubscribed) {
        await telemetryCharacteristic!.setNotifyValue(true);
        telemetrySubscription = telemetryCharacteristic!.onValueReceived.listen((value) {
          //print('Received ${value.length} bytes of telemetry data');
          if (value.length >= 96) {
            try {
              TelemetryData newData = TelemetryData.fromBytes(value);
              //print('Parsed: Battery1=${newData.batteryMonitor1.voltage.toStringAsFixed(2)}V (${newData.batteryMonitor1.stateOfCharge.toStringAsFixed(1)}%), Solar=${newData.totalSolarPower.toStringAsFixed(1)}W, Tank=${newData.waterTank.percentage.toStringAsFixed(1)}%');
              setState(() {
                telemetryData = newData;
                lastDataUpdate = DateTime.now();
                _updateAnimations();
              });
            } catch (e) {
              //print('Error parsing telemetry data: $e');
            }
          } else {
            //print('Insufficient telemetry data: ${value.length} bytes, expected 32');
          }
        });
        setState(() {
          isSubscribed = true;
          statusMessage = 'Receiving live telemetry data';
        });
      } else {
        await telemetryCharacteristic!.setNotifyValue(false);
        telemetrySubscription?.cancel();
        setState(() {
          isSubscribed = false;
          statusMessage = 'Telemetry updates paused';
          _solarAnimationController.stop();
          _tankFlowController.stop();
        });
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Subscription toggle failed: $e';
      });
    }
  }

  void _updateAnimations() {
    if (telemetryData != null) {
      // Solar animation - pulse when power > 0
      if (telemetryData!.totalSolarPower > 0 && !_solarAnimationController.isAnimating) {
        _solarAnimationController.repeat(reverse: true);
      } else if (telemetryData!.totalSolarPower <= 0) {
        _solarAnimationController.stop();
      }
      
      // Tank flow animation - animate when flow rate > 0
      if (telemetryData!.waterTank.flowRate > 0 && !_tankFlowController.isAnimating) {
        _tankFlowController.repeat();
      } else if (telemetryData!.waterTank.flowRate <= 0) {
        _tankFlowController.stop();
      }
    }
  }

  Future<void> _writeUpdateRate() async {
    if (updateRateCharacteristic == null) return;

    try {
      int newRate = int.tryParse(_updateRateController.text) ?? 1000;
      if (newRate < 100 || newRate > 60000) {
        setState(() {
          statusMessage = 'Update rate must be between 100-60000 ms';
        });
        return;
      }
      
      List<int> bytes = _int32ToBytes(newRate);
      await updateRateCharacteristic!.write(bytes);
      
      setState(() {
        updateRateMs = newRate;
        statusMessage = 'Update rate set to: ${updateRateMs}ms';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Write failed: $e';
      });
    }
  }

  Future<void> _updateRssi() async {
    if (isConnected && mounted) {
      try {
        int rssi = await widget.device.readRssi();
        if (mounted) {
          setState(() {
            currentRssi = rssi;
          });
          //print('RSSI updated: $rssi dBm');
        }
      } catch (e) {
        //print('Failed to read RSSI: $e');
      }
    }
  }

  void _startRssiUpdates() {
    _rssiTimer?.cancel(); // Cancel any existing timer
    _rssiTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!isConnected) {
        timer.cancel();
        _rssiTimer = null;
        return;
      }
      _updateRssi();
    });
  }

  Widget _buildSignalStrengthIndicator() {
    if (!isConnected) {
      return Icon(Icons.signal_cellular_nodata, color: Colors.grey);
    }

    // Convert RSSI to signal strength (0-5 bars)
    // RSSI ranges: -30 to -45 (excellent 5 bars), -45 to -60 (very good 4 bars), 
    // -60 to -75 (good 3 bars), -75 to -90 (fair 2 bars), -90 to -105 (poor 1 bar)
    int bars = 0;
    Color color = Colors.red;
    
    if (currentRssi >= -45) {
      bars = 5;  // Excellent signal
      color = Colors.green;
    } else if (currentRssi >= -60) {
      bars = 4;  // Very good signal
      color = Colors.green;
    } else if (currentRssi >= -75) {
      bars = 3;  // Good signal
      color = Colors.lightGreen;
    } else if (currentRssi >= -90) {
      bars = 2;  // Fair signal
      color = Colors.orange;
    } else if (currentRssi >= -105) {
      bars = 1;  // Poor signal
      color = Colors.red;
    }

    // Custom 5-bar signal strength indicator
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          height: 16,
          child: CustomPaint(
            painter: SignalStrengthPainter(bars: bars, color: color),
          ),
        ),
        // Text(
        //   '${currentRssi}dBm',
        //   style: TextStyle(fontSize: 8, color: color),
        // ),
      ],
    );
  }

  Widget _buildBatteryCard() {
    if (telemetryData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.battery_unknown, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text('Battery', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              Text('No data available', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    
    double avgSoC = telemetryData!.averageStateOfCharge;
    double totalPower = telemetryData!.totalBatteryPower;
    bool isCharging = totalPower > 0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCharging ? Icons.battery_charging_full : Icons.battery_std,
                  color: avgSoC > 20 ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'Battery - ${isCharging ? 'Charging' : 'Discharging'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Average State of Charge bar
            LinearProgressIndicator(
              value: avgSoC / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                avgSoC > 50 ? Colors.green : 
                avgSoC > 20 ? Colors.orange : Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${avgSoC.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Battery Monitors Side by Side
            Row(
              children: [
                // Battery Monitor 1
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Itechworld', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        Text('${telemetryData!.batteryMonitor1.voltage.toStringAsFixed(2)}V', 
                             style: TextStyle(fontSize: 13)),
                        Text('${telemetryData!.batteryMonitor1.current.toStringAsFixed(2)}A',
                             style: TextStyle(fontSize: 13)),
                        Text('${telemetryData!.batteryMonitor1.stateOfCharge.toStringAsFixed(1)}%',
                             style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        Text('${telemetryData!.batteryMonitor1.power.toStringAsFixed(1)}W',
                             style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Battery Monitor 2
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Victron', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        Text('${telemetryData!.batteryMonitor2.voltage.toStringAsFixed(2)}V',
                             style: TextStyle(fontSize: 13)),
                        Text('${telemetryData!.batteryMonitor2.current.toStringAsFixed(2)}A',
                             style: TextStyle(fontSize: 13)),
                        Text('${telemetryData!.batteryMonitor2.stateOfCharge.toStringAsFixed(1)}%',
                             style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        Text('${telemetryData!.batteryMonitor2.power.toStringAsFixed(1)}W',
                             style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolarPanel1Card() {
    if (telemetryData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wb_sunny, color: Colors.grey, size: 20),
                  const SizedBox(width: 4),
                  Text('Roof Panel', style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              Text('No data', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    
    bool isActive = telemetryData!.solarPanel1.power > 0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _solarPulse,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: isActive ? _solarPulse.value : 1.0,
                      child: Icon(
                        Icons.wb_sunny,
                        color: isActive ? Colors.orange : Colors.grey,
                        size: 20,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  'Roof Panel',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Text(
              '${telemetryData!.solarPanel1.power.toStringAsFixed(1)}W',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: isActive ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 4),
            Text('${telemetryData!.solarPanel1.voltage.toStringAsFixed(1)}V', 
                 style: TextStyle(fontSize: 12)),
            Text('${telemetryData!.solarPanel1.current.toStringAsFixed(2)}A', 
                 style: TextStyle(fontSize: 12)),
            
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (telemetryData!.solarPanel1.power / 300).clamp(0.0, 1.0),
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                isActive ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolarPanel2Card() {
    if (telemetryData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wb_sunny, color: Colors.grey, size: 20),
                  const SizedBox(width: 4),
                  Text('Blanket', style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              Text('No data', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    
    bool isActive = telemetryData!.solarPanel2.power > 0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _solarPulse,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: isActive ? _solarPulse.value : 1.0,
                      child: Icon(
                        Icons.wb_sunny,
                        color: isActive ? Colors.orange : Colors.grey,
                        size: 20,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  'Blanket',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Text(
              '${telemetryData!.solarPanel2.power.toStringAsFixed(1)}W',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: isActive ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 4),
            Text('${telemetryData!.solarPanel2.voltage.toStringAsFixed(1)}V', 
                 style: TextStyle(fontSize: 12)),
            Text('${telemetryData!.solarPanel2.current.toStringAsFixed(2)}A', 
                 style: TextStyle(fontSize: 12)),
            
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (telemetryData!.solarPanel2.power / 200).clamp(0.0, 1.0),
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                isActive ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTankCard() {
    if (telemetryData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.opacity, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text('Water Tank', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              Text('No data available', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    
    double tankPercent = telemetryData!.waterTank.percentage;
    bool hasFlow = telemetryData!.waterTank.flowRate > 0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    Icon(
                      Icons.opacity,
                      color: tankPercent > 20 ? Colors.blue : Colors.red,
                    ),
                    if (hasFlow)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: AnimatedBuilder(
                          animation: _tankFlow,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(0, -2 * _tankFlow.value),
                              child: Icon(
                                Icons.water_drop,
                                size: 12,
                                color: Colors.blue.withOpacity(_tankFlow.value),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                Text(
                  'Water Tank',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Tank level visualization
            Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 100 * (tankPercent / 100),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: tankPercent > 20 ? Colors.blue.withOpacity(0.7) : Colors.red.withOpacity(0.7),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(7),
                          bottomRight: Radius.circular(7),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${tankPercent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Tank Information Grid
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current Level', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${telemetryData!.waterTank.litresRemaining.toStringAsFixed(0)} L'),
                      const SizedBox(height: 8),
                      Text('Flow Rate', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${telemetryData!.waterTank.flowRate.toStringAsFixed(2)} L/min',
                        style: TextStyle(
                          color: hasFlow ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Daily Average', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${telemetryData!.waterTank.averageLPerDay.toStringAsFixed(1)} L/day'),
                      const SizedBox(height: 8),
                      Text('Est. Days Left', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        telemetryData!.waterTank.estimatedDaysLeft > 999 
                            ? '∞ days' 
                            : '${telemetryData!.waterTank.estimatedDaysLeft.toStringAsFixed(1)} days',
                        style: TextStyle(
                          color: telemetryData!.waterTank.estimatedDaysLeft > 7 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Last refill info
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Last refill: ${telemetryData!.waterTank.lastRefillDate} days ago',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Row(
          children: [
            const FlutterLogo(size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Tallulah Deets'),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: _buildSignalStrengthIndicator(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            // Card(
            //   child: Padding(
            //     padding: const EdgeInsets.all(16.0),
            //     child: Column(
            //       children: [
            //         Text(
            //           'Connection Status 1',
            //           style: Theme.of(context).textTheme.titleMedium,
            //         ),
            //         const SizedBox(height: 8),
            //         Text(
            //           statusMessage,
            //           textAlign: TextAlign.center,
            //           style: TextStyle(
            //             color: isConnected ? Colors.green : Colors.red,
            //           ),
            //         ),
            //         if (lastDataUpdate != null)
            //           Text(
            //             'Last update: ${DateTime.now().difference(lastDataUpdate!).inSeconds}s ago',
            //             style: TextStyle(
            //               fontSize: 12,
            //               color: Colors.grey[600],
            //             ),
            //           ),
            //         if (telemetryData != null)
            //           Text(
            //             'Counter: ${telemetryData!.counter}',
            //             style: TextStyle(
            //               fontSize: 12,
            //               color: Colors.blue,
            //             ),
            //           ),
            //         const SizedBox(height: 12),
            //         Row(
            //           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            //           children: [
            //             ElevatedButton.icon(
            //               onPressed: isConnected ? _toggleSubscription : null,
            //               icon: Icon(isSubscribed ? Icons.pause : Icons.play_arrow),
            //               label: Text(isSubscribed ? 'Pause Updates' : 'Resume Updates'),
            //               style: ElevatedButton.styleFrom(
            //                 backgroundColor: isSubscribed ? Colors.orange : Colors.green,
            //                 foregroundColor: Colors.white,
            //               ),
            //             ),
            //             ElevatedButton.icon(
            //               onPressed: isConnected ? _readCurrentValues : null,
            //               icon: const Icon(Icons.refresh),
            //               label: const Text('Refresh'),
            //             ),
            //           ],
            //         ),
            //       ],
            //     ),
            //   ),
            // ),
            
            const SizedBox(height: 16),
            
            // Battery Card (Full Width)
            _buildBatteryCard(),
            
            const SizedBox(height: 16),
            
            // Solar Panel Cards (Half Width Each)
            Row(
              children: [
                Expanded(child: _buildSolarPanel1Card()),
                const SizedBox(width: 8),
                Expanded(child: _buildSolarPanel2Card()),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Water Tank Card
            _buildTankCard(),
            
            const SizedBox(height: 16),
            
            // Update Rate Control
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Update Rate Control',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _updateRateController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Update Rate (ms)',
                              border: OutlineInputBorder(),
                              helperText: 'Between 100-60000 ms',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: isConnected ? _writeUpdateRate : null,
                          child: const Text('Set Rate'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Current rate: ${updateRateMs}ms',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            
            // Add extra space at bottom to prevent keyboard overflow
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 80),
          ],
        ),
      ),
    );
  }
}
