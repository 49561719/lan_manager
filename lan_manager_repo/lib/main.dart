import 'dart:async';
import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const AliBakarNetworkApp());

// ============================================================
//  التطبيق
// ============================================================

class AliBakarNetworkApp extends StatelessWidget {
  const AliBakarNetworkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'فاحص الشبكة - علي بكر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          surface: Color(0xFF1A1A2E),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const NetworkScannerScreen(),
    );
  }
}

// ============================================================
//  النماذج
// ============================================================

enum DeviceType { router, computer, mobile, iot, device }

extension DeviceTypeX on DeviceType {
  String get label => switch (this) {
        DeviceType.router => 'راوتر / بوابة',
        DeviceType.computer => 'كمبيوتر / لابتوب',
        DeviceType.mobile => 'هاتف',
        DeviceType.iot => 'جهاز IoT / طابعة',
        DeviceType.device => 'جهاز متصل',
      };

  IconData get icon => switch (this) {
        DeviceType.router => Icons.router,
        DeviceType.computer => Icons.laptop,
        DeviceType.mobile => Icons.smartphone,
        DeviceType.iot => Icons.devices_other,
        DeviceType.device => Icons.devices,
      };
}

class NetworkDevice {
  final String ip;
  final List<int> openPorts;
  final String? hostname;
  final DeviceType type;

  const NetworkDevice({
    required this.ip,
    required this.openPorts,
    required this.type,
    this.hostname,
  });

  /// الرابط الذي يُفتح في المتصفح: يختار أول منفذ ويب مفتوح،
  /// وإن لم يوجد يستخدم http://IP مباشرة.
  Uri get webUri {
    const webPorts = [80, 443, 8080, 8008];
    final port = webPorts.firstWhere(
      (p) => openPorts.contains(p),
      orElse: () => 80,
    );
    final scheme = port == 443 ? 'https' : 'http';
    final isDefaultPort =
        (scheme == 'http' && port == 80) || (scheme == 'https' && port == 443);
    return Uri(
      scheme: scheme,
      host: ip,
      port: isDefaultPort ? null : port,
    );
  }
}

// ============================================================
//  محرك الفحص
// ============================================================

class LanProbe {
  static const _ports = [
    22, 23, 53, 80, 443, 445, 554, 631, 5555, 8008, 8080, 9100, 62078,
  ];
  static const _connectTimeout = Duration(milliseconds: 350);
  static const _dnsTimeout = Duration(milliseconds: 800);

  /// يفحص المنافذ الشائعة لعنوان واحد.
  /// - اتصال ناجح → الجهاز موجود والمنفذ مفتوح.
  /// - رفض الاتصال (ECONNREFUSED = 111) → الجهاز موجود ويرد.
  static Future<({bool alive, List<int> ports})> probe(String ip) async {
    final open = <int>[];
    var alive = false;

    await Future.wait(_ports.map((port) async {
      try {
        final socket = await Socket.connect(ip, port, timeout: _connectTimeout);
        socket.destroy();
        open.add(port);
        alive = true;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 111) alive = true;
      } catch (_) {}
    }));

    open.sort();
    return (alive: alive, ports: open);
  }

  static Future<String?> reverseLookup(String ip) async {
    try {
      final host = (await InternetAddress(ip)
              .reverse()
              .timeout(_dnsTimeout))
          .host;
      return host == ip || host.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
  }

  static DeviceType classify(
    String ip,
    List<int> ports,
    String? gateway,
    String? hostname,
  ) {
    final name = (hostname ?? '').toLowerCase();

    if (ip == gateway) return DeviceType.router;
    if (ports.contains(62078) ||
        ports.contains(5555) ||
        name.contains('iphone') ||
        name.contains('android') ||
        name.contains('galaxy')) {
      return DeviceType.mobile;
    }
    if (ports.contains(445) ||
        name.contains('desktop') ||
        name.contains('laptop')) {
      return DeviceType.computer;
    }
    if (ports.contains(9100) ||
        ports.contains(631) ||
        ports.contains(554) ||
        ports.contains(8008)) {
      return DeviceType.iot;
    }
    if (ports.contains(53) &&
        (ports.contains(80) || ports.contains(443))) {
      return DeviceType.router;
    }
    return DeviceType.device;
  }
}

// ============================================================
//  الشاشة الرئيسية
// ============================================================

class NetworkScannerScreen extends StatefulWidget {
  const NetworkScannerScreen({super.key});

  @override
  State<NetworkScannerScreen> createState() => _NetworkScannerScreenState();
}

class _NetworkScannerScreenState extends State<NetworkScannerScreen> {
  static const _batchSize = 40;
  static const _hostsPerSubnet = 254;

  final _netInfo = NetworkInfo();
  final List<NetworkDevice> _devices = [];

  bool _scanning = false;
  bool _cancelRequested = false;
  int _scanned = 0;

  String _localIp = 'جارٍ جلب العنوان...';
  String? _subnet;
  String? _gatewayIp;

  @override
  void initState() {
    super.initState();
    _refreshNetworkInfo();
  }

  // ---------- رسائل ----------

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : null,
      ));
  }

  // ---------- معلومات الشبكة ----------

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices,
      ].request();
    } catch (_) {}
  }

  Future<String?> _fallbackIpv4() async {
    try {
      for (final ni in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _refreshNetworkInfo() async {
    await _requestPermissions();

    String? ip;
    String? gateway;
    try {
      ip = await _netInfo.getWifiIP();
    } catch (_) {}
    try {
      gateway = await _netInfo.getWifiGatewayIP();
    } catch (_) {}

    if (ip == null || !ip.contains('.')) {
      ip = await _fallbackIpv4();
    }

    if (!mounted) return;

    if (ip != null && ip.contains('.')) {
      final subnet = ip.substring(0, ip.lastIndexOf('.'));
      setState(() {
        _localIp = ip!;
        _subnet = subnet;
        _gatewayIp = (gateway != null && gateway.contains('.'))
            ? gateway
            : '$subnet.1';
      });
    } else {
      setState(() {
        _localIp = 'غير متصل بشبكة Wi-Fi';
        _subnet = null;
        _gatewayIp = null;
      });
    }
  }

  // ---------- الفحص ----------

  Future<void> _startScan() async {
    if (_scanning) return;

    await _refreshNetworkInfo();
    final subnet = _subnet;
    if (subnet == null) {
      _toast('تأكد من الاتصال بشبكة Wi-Fi وتفعيل الموقع (GPS)', error: true);
      return;
    }

    final gateway = _gatewayIp;
    final hosts = [
      for (var i = 1; i <= _hostsPerSubnet; i++) '$subnet.$i',
    ];

    setState(() {
      _scanning = true;
      _cancelRequested = false;
      _scanned = 0;
      _devices.clear();
    });

    try {
      for (var i = 0; i < hosts.length && !_cancelRequested; i += _batchSize) {
        final end = min(i + _batchSize, hosts.length);
        final chunk = hosts.sublist(i, end);
        final results =
            await Future.wait(chunk.map((ip) => _inspect(ip, gateway)));

        if (!mounted) return;
        setState(() {
          _scanned += chunk.length;
          for (final d in results) {
            if (d != null) _devices.add(d);
          }
          _devices.sort((a, b) => _lastOctet(a.ip).compareTo(_lastOctet(b.ip)));
        });
      }

      if (mounted) {
        _toast(_cancelRequested
            ? 'تم إيقاف الفحص'
            : 'اكتمل الفحص: تم العثور على ${_devices.length} جهاز');
      }
    } catch (_) {
      _toast('حدث خطأ أثناء الفحص', error: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _stopScan() {
    if (!_scanning) return;
    setState(() => _cancelRequested = true);
  }

  Future<NetworkDevice?> _inspect(String ip, String? gateway) async {
    try {
      final probe = await LanProbe.probe(ip);
      if (!probe.alive) return null;

      final hostname = await LanProbe.reverseLookup(ip);
      return NetworkDevice(
        ip: ip,
        openPorts: probe.ports,
        hostname: hostname,
        type: LanProbe.classify(ip, probe.ports, gateway, hostname),
      );
    } catch (_) {
      return null;
    }
  }

  static int _lastOctet(String ip) => int.parse(ip.split('.').last);

  // ---------- الإجراءات على الجهاز ----------

  Future<void> _openInBrowser(NetworkDevice device) async {
    try {
      final ok = await launchUrl(
        device.webUri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) _toast('تعذر فتح المتصفح', error: true);
    } catch (_) {
      _toast('تعذر فتح المتصفح', error: true);
    }
  }

  Future<void> _copyIp(NetworkDevice device) async {
    await Clipboard.setData(ClipboardData(text: device.ip));
    _toast('تم نسخ ${device.ip}');
  }

  // ---------- واجهة المستخدم ----------

  @override
  Widget build(BuildContext context) {
    final progress = _hostsPerSubnet == 0 ? 0.0 : _scanned / _hostsPerSubnet;

    return Scaffold(
      appBar: AppBar(
        title: const Text('فاحص الشبكة - علي بكر'),
        centerTitle: true,
        backgroundColor: const Color(0xFF16162C),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث معلومات الشبكة',
            onPressed: _scanning ? null : _refreshNetworkInfo,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildHeader(progress),
              const SizedBox(height: 12),
              Expanded(child: _buildDeviceList()),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'تصميم وتطوير: علي بكر (Ali Bakar)',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double progress) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurpleAccent.withAlpha(77)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statColumn('IP الهاتف', _localIp, Colors.greenAccent),
              _statColumn(
                'الأجهزة المكتشفة',
                '${_devices.length} جهاز',
                Colors.deepPurpleAccent,
                alignEnd: true,
              ),
            ],
          ),
          if (_subnet != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'النطاق: $_subnet.0/24',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_scanning) ...[
            LinearProgressIndicator(
              value: progress,
              color: Colors.deepPurpleAccent,
              backgroundColor: Colors.white10,
            ),
            const SizedBox(height: 8),
            Text(
              'جارٍ الفحص... ${(progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            _actionButton(
              label: 'إيقاف الفحص',
              icon: Icons.stop_circle_outlined,
              color: Colors.redAccent,
              onPressed: _stopScan,
            ),
          ] else
            _actionButton(
              label: 'بدء الفحص',
              icon: Icons.radar,
              color: Colors.deepPurpleAccent,
              onPressed: _startScan,
            ),
        ],
      ),
    );
  }

  Widget _statColumn(String title, String value, Color color,
      {bool alignEnd = false}) {
    return Flexible(
      child: Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return Center(
        child: Text(
          _scanning
              ? 'جارٍ البحث عن الأجهزة...'
              : 'اضغط "بدء الفحص" لاكتشاف الأجهزة\n(تأكد من تفعيل الموقع GPS)',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) => _buildDeviceCard(_devices[index]),
    );
  }

  Widget _buildDeviceCard(NetworkDevice device) {
    final isGateway = device.type == DeviceType.router;

    return Card(
      color: const Color(0xFF16162C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: () => _openInBrowser(device),
        onLongPress: () => _copyIp(device),
        leading: CircleAvatar(
          backgroundColor: Colors.deepPurple.withAlpha(51),
          child: Icon(device.type.icon, color: Colors.deepPurpleAccent),
        ),
        title: Text(
          device.ip,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              device.type.label,
              if (isGateway) '(Gateway)',
              if (device.hostname != null) device.hostname!,
              if (device.openPorts.isNotEmpty)
                'المنافذ: ${device.openPorts.join(', ')}',
            ].join('  •  '),
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withAlpha(51),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.greenAccent),
          ),
          child: const Text(
            'متصل',
            style: TextStyle(color: Colors.greenAccent, fontSize: 11),
          ),
        ),
      ),
    );
  }
}
