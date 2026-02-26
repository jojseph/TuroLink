import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/p2p_provider.dart';
import '../providers/profile_provider.dart';
import '../services/database_service.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      if (code != null) {
        setState(() => _isProcessing = true);
        
        try {
          // Parse JSON payload
          final data = jsonDecode(code) as Map<String, dynamic>;
          final type = data['type'] as String?;
          
          if (type == 'student_sync') {
             final hostName = data['hostName'] as String?;
             final classroomId = data['classroomId'] as String?;
             
             if (hostName != null && classroomId != null) {
                final db = DatabaseService();
                final classroom = await db.getClassroom(classroomId);
                
                if (classroom != null) {
                   final p2p = Provider.of<P2PProvider>(context, listen: false);
                   final profile = Provider.of<ProfileProvider>(context, listen: false).profile!;
                   await _scannerController.stop();
                   if (!mounted) return;
                   
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('Syncing updates with $hostName...'), backgroundColor: Colors.green),
                   );
                   
                   await p2p.joinStudentSync(hostName, classroom, profile.displayName);
                   if (!mounted) return;
                   Navigator.pop(context, true);
                   return;
                } else {
                   if (mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       const SnackBar(content: Text('You must join this classroom before you can sync with peers.'), backgroundColor: Colors.red),
                     );
                     await Future.delayed(const Duration(seconds: 2));
                     setState(() => _isProcessing = false);
                   }
                   return;
                }
             }
          }

          final teacherName = data['teacherName'] as String?;
          final classroomName = data['classroomName'] as String?;
          final password = data['password'] as String?;

          if (teacherName != null && classroomName != null && password != null) {
            final p2p = Provider.of<P2PProvider>(context, listen: false);
            final profile = Provider.of<ProfileProvider>(context, listen: false).profile!;
            
            // Stop scanner to prevent multiple triggers
            await _scannerController.stop();
            
            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('QR Code scanned successfully! Connecting...'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );

            // Initiate auto-connect
            await p2p.joinViaQRCode(teacherName, classroomName, password, profile.displayName);
            
            if (!mounted) return;
            // Pop back to Hub Screen (hub screen will handle auto-navigating to Dashboard on connect)
            Navigator.pop(context, true);
            return;
          }
        } catch (e) {
          // Invalid QR code structure
          debugPrint('Invalid QR Code: $e');
        }

        // Delay before allowing another scan
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid classroom QR code. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
          await Future.delayed(const Duration(seconds: 2));
          setState(() => _isProcessing = false);
        }
      }
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Scan Classroom QR', style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          // Scanner UI Overlay
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: const Color(0xFF00C9A7),
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: MediaQuery.of(context).size.width * 0.7,
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Point camera at the Teacher\'s QR Code',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF00C9A7)),
              ),
            ),
        ],
      ),
    );
  }
}

// Simple overlay shape for the scanner
class QrScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  QrScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 3.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10.0);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path path = Path();
    path.addRect(rect);

    path.moveTo(
      rect.left + rect.width / 2.0 - cutOutSize / 2.0,
      rect.top + rect.height / 2.0 - cutOutSize / 2.0,
    );
    path.lineTo(
      rect.left + rect.width / 2.0 + cutOutSize / 2.0,
      rect.top + rect.height / 2.0 - cutOutSize / 2.0,
    );
    path.lineTo(
      rect.left + rect.width / 2.0 + cutOutSize / 2.0,
      rect.top + rect.height / 2.0 + cutOutSize / 2.0,
    );
    path.lineTo(
      rect.left + rect.width / 2.0 - cutOutSize / 2.0,
      rect.top + rect.height / 2.0 + cutOutSize / 2.0,
    );
    path.lineTo(
      rect.left + rect.width / 2.0 - cutOutSize / 2.0,
      rect.top + rect.height / 2.0 - cutOutSize / 2.0,
    );
    path.close();

    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final borderWidthSize = width / 2;
    final height = rect.height;
    final borderOffset = borderWidth / 2;
    final _borderLength = borderLength > cutOutSize / 2 + borderWidthSize
        ? cutOutSize / 2 + borderWidthSize
        : borderLength;
    final _cutOutSize = cutOutSize < width ? cutOutSize : width - borderOffset;

    final backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final boxPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.dstOut;

    final cutOutRect = Rect.fromLTWH(
      rect.left + width / 2 - _cutOutSize / 2 + borderOffset,
      rect.top + height / 2 - _cutOutSize / 2 + borderOffset,
      _cutOutSize - borderOffset * 2,
      _cutOutSize - borderOffset * 2,
    );

    canvas
      ..saveLayer(rect, backgroundPaint)
      ..drawRect(rect, backgroundPaint)
      ..drawRRect(
        RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
        boxPaint,
      )
      ..restore();

    // Top left corner
    canvas.drawLine(
      Offset(cutOutRect.left, cutOutRect.top + borderRadius),
      Offset(cutOutRect.left, cutOutRect.top + _borderLength),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cutOutRect.left + borderRadius, cutOutRect.top),
      Offset(cutOutRect.left + _borderLength, cutOutRect.top),
      borderPaint,
    );
    // Draw corner arc
    canvas.drawArc(
        Rect.fromCircle(
            center: Offset(
                cutOutRect.left + borderRadius, cutOutRect.top + borderRadius),
            radius: borderRadius),
        3.14159,
        3.14159 / 2,
        false,
        borderPaint);

    // Top right corner
    canvas.drawLine(
      Offset(cutOutRect.right, cutOutRect.top + borderRadius),
      Offset(cutOutRect.right, cutOutRect.top + _borderLength),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cutOutRect.right - borderRadius, cutOutRect.top),
      Offset(cutOutRect.right - _borderLength, cutOutRect.top),
      borderPaint,
    );
    // Draw corner arc
    canvas.drawArc(
        Rect.fromCircle(
            center: Offset(
                cutOutRect.right - borderRadius, cutOutRect.top + borderRadius),
            radius: borderRadius),
        1.5708 * 3,
        1.5708,
        false,
        borderPaint);

    // Bottom right corner
    canvas.drawLine(
      Offset(cutOutRect.right, cutOutRect.bottom - borderRadius),
      Offset(cutOutRect.right, cutOutRect.bottom - _borderLength),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cutOutRect.right - borderRadius, cutOutRect.bottom),
      Offset(cutOutRect.right - _borderLength, cutOutRect.bottom),
      borderPaint,
    );
    // Draw corner arc
    canvas.drawArc(
        Rect.fromCircle(
            center: Offset(cutOutRect.right - borderRadius,
                cutOutRect.bottom - borderRadius),
            radius: borderRadius),
        0,
        1.5708,
        false,
        borderPaint);

    // Bottom left corner
    canvas.drawLine(
      Offset(cutOutRect.left, cutOutRect.bottom - borderRadius),
      Offset(cutOutRect.left, cutOutRect.bottom - _borderLength),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cutOutRect.left + borderRadius, cutOutRect.bottom),
      Offset(cutOutRect.left + _borderLength, cutOutRect.bottom),
      borderPaint,
    );
    // Draw corner arc
    canvas.drawArc(
        Rect.fromCircle(
            center: Offset(
                cutOutRect.left + borderRadius, cutOutRect.bottom - borderRadius),
            radius: borderRadius),
        1.5708,
        1.5708,
        false,
        borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      overlayColor: overlayColor,
      borderRadius: borderRadius * t,
      borderLength: borderLength * t,
      cutOutSize: cutOutSize * t,
    );
  }
}
