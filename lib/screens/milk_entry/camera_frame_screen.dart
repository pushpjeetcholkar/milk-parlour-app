import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full-screen camera with a document-frame guide overlay, torch toggle,
/// and a properly-scaled preview that fills the screen without white bars.
class CameraFrameScreen extends StatefulWidget {
  const CameraFrameScreen({super.key});

  @override
  State<CameraFrameScreen> createState() => _CameraFrameScreenState();
}

class _CameraFrameScreenState extends State<CameraFrameScreen>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  bool    _ready      = false;
  bool    _capturing  = false;
  bool    _torchOn    = false;
  bool    _torchAvail = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _ctrl!.dispose();
      if (mounted) setState(() { _ctrl = null; _ready = false; });
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Camera init ──────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    if (mounted) setState(() { _error = null; _ready = false; });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera found on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }

      // Default to AUTO flash: the camera hardware fires the flash on capture
      // automatically when the scene is dark (zero cost, works on all devices).
      bool torchAvail = false;
      try {
        await ctrl.setFlashMode(FlashMode.auto);
        torchAvail = true;
      } catch (_) {}

      setState(() {
        _ctrl       = ctrl;
        _ready      = true;
        _torchAvail = torchAvail;
        _torchOn    = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e');
    }
  }

  // ── Flash / torch ────────────────────────────────────────────────────────────

  Future<void> _toggleTorch() async {
    if (_ctrl == null || !_ready || !_torchAvail) return;
    try {
      // ON  → continuous torch (lights up the live preview so you can see in dark)
      // OFF → back to AUTO (flash still fires automatically on capture if dark)
      final next = _torchOn ? FlashMode.auto : FlashMode.torch;
      await _ctrl!.setFlashMode(next);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  // ── Capture ──────────────────────────────────────────────────────────────────

  Future<void> _capture() async {
    if (_ctrl == null || !_ready || _capturing) return;
    setState(() => _capturing = true);
    try {
      final xFile = await _ctrl!.takePicture();
      if (mounted) Navigator.pop(context, File(xFile.path));
    } catch (e) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Camera preview (properly scaled to fill screen) ────────────
            if (_ready && _ctrl != null)
              _buildFullScreenPreview()
            else if (_error != null)
              _buildErrorState()
            else
              const Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Starting camera…',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              )),

            // ── Frame overlay (only when preview is live) ──────────────────
            if (_ready)
              CustomPaint(
                painter: _FrameOverlayPainter(),
                child: const SizedBox.expand(),
              ),

            // ── Top control bar ────────────────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 4),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                  const Expanded(
                    child: Text('Scan Register',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                  // Torch toggle (auto-flash is on by default for capture)
                  if (_torchAvail)
                    IconButton(
                      tooltip: _torchOn
                          ? 'Torch ON (tap for Auto)'
                          : 'Auto flash (tap for Torch)',
                      icon: Icon(
                        _torchOn
                            ? Icons.flashlight_on
                            : Icons.flash_auto,
                        color: _torchOn
                            ? Colors.amber.shade300
                            : Colors.white,
                        size: 26,
                      ),
                      onPressed: _toggleTorch,
                    )
                  else
                    const SizedBox(width: 48),
                ]),
              ),
            ),

            // ── Alignment instruction (above frame) ────────────────────────
            if (_ready)
              LayoutBuilder(builder: (_, box) {
                final fr = _FrameOverlayPainter.frameRect(
                    box.maxWidth, box.maxHeight);
                return Positioned(
                  top: (fr.top - 38).clamp(50.0, double.infinity),
                  left: 0, right: 0,
                  child: const Text(
                    'Align register page inside the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        shadows: [Shadow(blurRadius: 6,
                            color: Colors.black87)]),
                  ),
                );
              }),

            // ── Bottom shutter bar ─────────────────────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _capturing
                          ? 'Capturing…'
                          : _torchOn
                              ? '🔦 Torch ON — keep steady'
                              : '⚡ Auto-flash on · tap torch icon if too dark',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    // Shutter button
                    GestureDetector(
                      onTap: _ready ? _capture : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width:  _capturing ? 68 : 74,
                        height: _capturing ? 68 : 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _capturing
                              ? Colors.grey.shade600
                              : Colors.white,
                          border: Border.all(
                              color: Colors.white54, width: 4),
                          boxShadow: _capturing
                              ? []
                              : [BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  blurRadius: 8)],
                        ),
                        child: _capturing
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt,
                                size: 32, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Tap to capture',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Preview: fill screen — official Flutter camera example approach ──────────
  //
  // Root cause of white screen: OverflowBox(maxWidth: infinity) passes
  // unconstrained layout to AspectRatio, which then renders with 0×0 size.
  //
  // Fix: Transform.scale using the ratio between the screen's and the
  // camera's aspect ratios.  This is the approach in the official Flutter
  // camera example and works on all Android devices.

  Widget _buildFullScreenPreview() {
    final screenSize = MediaQuery.of(context).size;
    // _ctrl.value.aspectRatio = previewSize.width / previewSize.height
    // For a landscape-native camera this is e.g. 1920/1080 = 1.777
    var scale = screenSize.aspectRatio * _ctrl!.value.aspectRatio;
    // If scale < 1 the camera is narrower than the screen → invert to fill
    if (scale < 1) scale = 1 / scale;
    // ClipRect prevents the scaled-up preview from bleeding over the bars,
    // Center keeps it aligned so the frame overlay matches what's captured.
    return ClipRect(
      child: Center(
        child: Transform.scale(
          scale: scale,
          child: Center(child: CameraPreview(_ctrl!)),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt,
                color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _initCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Frame overlay painter
// ═══════════════════════════════════════════════════════════════════════════

class _FrameOverlayPainter extends CustomPainter {
  static Rect frameRect(double w, double h) {
    const hPad  = 16.0;
    final fw    = w - hPad * 2;
    final fh    = fw * 1.25;
    final topY  = ((h - fh) / 2).clamp(80.0, h * 0.2);
    return Rect.fromLTWH(hPad, topY, fw, fh);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = frameRect(size.width, size.height);

    // Dark overlay outside the frame
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRect(frame)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Faint border
    canvas.drawRect(
      frame,
      Paint()
        ..color       = Colors.white.withValues(alpha: 0.4)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Bright corner L-markers
    final cp = Paint()
      ..color       = Colors.white
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap   = StrokeCap.square;
    const cl = 30.0;

    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, Offset(o.dx + dx, o.dy), cp);
      canvas.drawLine(o, Offset(o.dx, o.dy + dy), cp);
    }

    corner(frame.topLeft,      cl,  cl);
    corner(frame.topRight,    -cl,  cl);
    corner(frame.bottomLeft,   cl, -cl);
    corner(frame.bottomRight, -cl, -cl);

    // Faint centre crosshair
    final xp = Paint()
      ..color       = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(frame.center.dx - 14, frame.center.dy),
        Offset(frame.center.dx + 14, frame.center.dy), xp);
    canvas.drawLine(
        Offset(frame.center.dx, frame.center.dy - 14),
        Offset(frame.center.dx, frame.center.dy + 14), xp);
  }

  @override
  bool shouldRepaint(_FrameOverlayPainter o) => false;
}
