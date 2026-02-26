
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/p2p_provider.dart';
import '../providers/profile_provider.dart';
import '../services/permission_service.dart';
import 'qr_scanner_screen.dart';

class P2PHubScreen extends StatefulWidget {
  const P2PHubScreen({super.key});

  @override
  State<P2PHubScreen> createState() => _P2PHubScreenState();
}

class _P2PHubScreenState extends State<P2PHubScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isScanning = false;
  bool _dialogShown = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleScan() async {
    final p2p = Provider.of<P2PProvider>(context, listen: false);
    final profile =
        Provider.of<ProfileProvider>(context, listen: false).profile!;

    if (_isScanning) {
      await p2p.stopAll();
      setState(() => _isScanning = false);
    } else {
      // Request all P2P permissions before starting discovery
      final granted = await PermissionService.requestP2PPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Location permission is required to scan for nearby classrooms. Please enable it in Settings.'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      await p2p.startDiscovering(profile.displayName);
      setState(() => _isScanning = true);
    }
  }

  void _connectToPeer(String endpointId) async {
    final p2p = Provider.of<P2PProvider>(context, listen: false);
    final profile =
        Provider.of<ProfileProvider>(context, listen: false).profile!;
    await p2p.connectToPeer(endpointId, profile.displayName);
  }

  void _showPasswordDialog(String endpointId) {
    final passwordController = TextEditingController();
    final profile =
        Provider.of<ProfileProvider>(context, listen: false).profile!;
    final p2p = Provider.of<P2PProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Enter Classroom Password',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: passwordController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle:
                TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              p2p.sendJoinRequest(
                endpointId,
                passwordController.text.trim(),
                profile.displayName,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Join',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0C29),
              Color(0xFF302B63),
              Color(0xFF24243E),
            ],
          ),
        ),
        child: SafeArea(
          child: Consumer<P2PProvider>(
            builder: (context, p2p, _) {
              // Show password dialog when connected & classroom info received
              if (p2p.state == P2PState.connected &&
                  p2p.currentClassroom != null &&
                  !_dialogShown &&
                  p2p.statusMessage.contains('Enter password')) {
                _dialogShown = true;
                // Find the connected endpoint from discovered peers
                final connectedEndpointId = p2p.discoveredPeers.isNotEmpty
                    ? p2p.discoveredPeers.first.endpointId
                    : '';
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (connectedEndpointId.isNotEmpty) {
                    _showPasswordDialog(connectedEndpointId);
                  }
                });
              }

              // Navigate back to dashboard after successful auth
              if (p2p.statusMessage == 'Joined classroom!' &&
                  p2p.currentClassroom != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_navigated) {
                    _navigated = true;
                    p2p.stopDiscovery(); // Stop scanning, but keep connection
                    Navigator.pop(context); // Back to Dashboard
                  }
                });
              }

              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios,
                              color: Colors.white70),
                          onPressed: () {
                            p2p.stopAll();
                            Navigator.pop(context);
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'P2P Hub',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Status bar
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isScanning
                                  ? Colors.greenAccent
                                  : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p2p.statusMessage,
                              style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Radar animation
                    if (_isScanning)
                      Center(
                        child: SizedBox(
                          height: 180,
                          width: 180,
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return CustomPaint(
                                painter: _RadarPainter(
                                  progress: _pulseController.value,
                                ),
                                child: child,
                              );
                            },
                            child: const Center(
                              child: Icon(
                                Icons.wifi_tethering_rounded,
                                size: 40,
                                color: Color(0xFF6C63FF),
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (!_isScanning)
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.radar_rounded,
                              size: 80,
                              color:
                                  Colors.white.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tap the button below to\nscan for nearby classrooms',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.4),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Discovered peers list
                    if (p2p.discoveredPeers.isNotEmpty) ...[
                      Text(
                        'NEARBY CLASSROOMS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.4),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    Expanded(
                      child: ListView.builder(
                        itemCount: p2p.discoveredPeers.length,
                        itemBuilder: (context, index) {
                          final peer = p2p.discoveredPeers[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF6C63FF)
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 8),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6C63FF)
                                        .withValues(alpha: 0.2),
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.school_rounded,
                                    color: Color(0xFF6C63FF),
                                  ),
                                ),
                                title: Text(
                                  peer.endpointName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  'Tap to join',
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.4),
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  color: Color(0xFF6C63FF),
                                  size: 18,
                                ),
                                onTap: () {
                                  if (p2p.state !=
                                      P2PState.connected) {
                                    _connectToPeer(peer.endpointId);
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Scan button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _toggleScan,
                        icon: Icon(
                          _isScanning
                              ? Icons.stop_rounded
                              : Icons.search_rounded,
                        ),
                        label: Text(
                          _isScanning
                              ? 'Stop Scanning'
                              : 'Scan for Classrooms',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isScanning
                              ? Colors.red.shade700
                              : const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // QR Scan button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final p2p = Provider.of<P2PProvider>(context, listen: false);
                          if (_isScanning) {
                            await p2p.stopAll();
                            setState(() => _isScanning = false);
                          }
                          
                          if (mounted) {
                            final connected = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                            );
                            
                            // If successfully connected via QR, we're done here
                            if (connected == true && mounted) {
                              Navigator.pop(context);
                            }
                          }
                        },
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text(
                          'Scan QR Code',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00C9A7),
                          side: const BorderSide(color: Color(0xFF00C9A7), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the radar pulse animation
class _RadarPainter extends CustomPainter {
  final double progress;

  _RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + i * 0.33) % 1.0;
      final radius = maxRadius * ringProgress;
      final opacity = (1.0 - ringProgress) * 0.4;

      final paint = Paint()
        ..color = const Color(0xFF6C63FF).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
