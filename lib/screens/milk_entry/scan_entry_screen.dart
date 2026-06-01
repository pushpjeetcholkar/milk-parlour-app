import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/settings_service.dart';
import '../../services/ocr_service.dart';
import 'camera_frame_screen.dart';
import 'scan_review_screen.dart';

class ScanEntryScreen extends StatefulWidget {
  const ScanEntryScreen({super.key});

  @override
  State<ScanEntryScreen> createState() => _ScanEntryScreenState();
}

class _ScanEntryScreenState extends State<ScanEntryScreen> {
  File?   _imageFile;
  bool    _processing = false;
  bool    _cropping   = false;
  String  _statusMsg  = '';
  String  _rawOcr     = '';
  int     _rotateDeg  = 0;   // 0 · 90 · 180 · 270
  bool    _useCloudVision = false;
  String? _cloudApiKey;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final key = await SettingsService.getCloudVisionApiKey();
    if (mounted) setState(() => _cloudApiKey = key);
  }

  // ── State reset ──────────────────────────────────────────────────────────────

  void _resetState(File file) => setState(() {
        _imageFile = file;
        _rotateDeg = 0;
        _statusMsg = '';
        _rawOcr    = '';
      });

  // ── Rotation ─────────────────────────────────────────────────────────────────

  void _rotateLeft()  => setState(() => _rotateDeg = (_rotateDeg - 90 + 360) % 360);
  void _rotateRight() => setState(() => _rotateDeg = (_rotateDeg + 90) % 360);
  void _rotate180()   => setState(() => _rotateDeg = (_rotateDeg + 180) % 360);

  /// Writes a rotated copy of [_imageFile] to a temp file if needed.
  Future<File> _applyRotation(File source) async {
    if (_rotateDeg == 0) return source;
    try {
      final bytes    = await source.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return source;
      final rotated  = img.copyRotate(original, angle: _rotateDeg.toDouble());
      final dir      = await getTemporaryDirectory();
      final out      = File(
          '${dir.path}/scan_rot_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(img.encodeJpg(rotated, quality: 92));
      return out;
    } catch (_) {
      return source;
    }
  }

  // ── Crop ─────────────────────────────────────────────────────────────────────

  /// Apply any pending rotation first, then open the native crop UI.
  Future<void> _cropImage() async {
    if (_imageFile == null) return;
    setState(() => _cropping = true);

    try {
      // Apply manual rotation before cropping so the crop handles match
      // what the user sees in the preview.
      final rotated = await _applyRotation(_imageFile!);

      final cropped = await ImageCropper().cropImage(
        sourcePath: rotated.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle:        'Select Data Rows',
            toolbarColor:        Colors.blue.shade800,
            toolbarWidgetColor:  Colors.white,
            activeControlsWidgetColor: Colors.blue.shade400,
            backgroundColor:     Colors.black,
            // Free-form crop — user can drag any corner/edge
            initAspectRatio:     CropAspectRatioPreset.original,
            lockAspectRatio:     false,
            hideBottomControls:  false,
            showCropGrid:        true,
          ),
        ],
      );

      if (!mounted) return;
      if (cropped != null) {
        // Rotation was baked into the rotated file so reset the angle
        setState(() {
          _imageFile = File(cropped.path);
          _rotateDeg = 0;
          _statusMsg = '';
          _rawOcr    = '';
        });
      }
    } finally {
      if (mounted) setState(() => _cropping = false);
    }
  }

  // ── OCR pipeline ─────────────────────────────────────────────────────────────

  Future<void> _processImage() async {
    if (_imageFile == null) return;
    setState(() {
      _processing = true;
      _statusMsg  = _rotateDeg != 0
          ? 'Applying rotation…'
          : 'Starting OCR…';
      _rawOcr     = '';
    });

    try {
      // ── Step 1: rotate if needed ───────────────────────────────────────
      File fileToProcess;
      try {
        fileToProcess = await _applyRotation(_imageFile!);
      } catch (e) {
        fileToProcess = _imageFile!;
      }

      if (!mounted) return;

      // ── Step 2: OCR ────────────────────────────────────────────────────
      OcrResult ocrResult;

      if (_useCloudVision && _cloudApiKey != null) {
        // Cloud Vision API (handwriting-capable)
        setState(() => _statusMsg = 'Calling Google Cloud Vision API…');
        try {
          ocrResult = await OcrService.extractWithCloudVision(
              fileToProcess, _cloudApiKey!);
        } catch (e) {
          // Fallback to ML Kit on Cloud Vision failure
          if (mounted) {
            setState(() => _statusMsg =
                'Cloud Vision failed ($e). Falling back to ML Kit…');
          }
          try {
            ocrResult = await OcrService.extractStructured(fileToProcess);
          } catch (e2) {
            if (mounted) {
              setState(() {
                _processing = false;
                _statusMsg  = 'Error: Both OCR engines failed.\n'
                    'Cloud Vision: $e\nML Kit: $e2';
                _rawOcr     = '';
              });
            }
            return;
          }
        }
      } else {
        // ML Kit (offline, printed text only)
        setState(() => _statusMsg = 'Running ML Kit OCR…');
        try {
          ocrResult = await OcrService.extractStructured(fileToProcess);
        } catch (e) {
          if (mounted) {
            setState(() {
              _processing = false;
              _statusMsg  = 'Error: OCR failed — $e\n\n'
                  'Make sure the image is clear and try again.';
              _rawOcr     = '';
            });
          }
          return;
        }
      }

      if (!mounted) return;

      // Store raw text regardless of whether parsing succeeds
      setState(() {
        _rawOcr    = ocrResult.rawText;
        _statusMsg = ocrResult.rawText.isEmpty
            ? '⚠️ ML Kit found no text in the image.'
            : 'Parsing entries from ${ocrResult.rawText.split('\n').length} text lines…';
      });

      // ── Step 3: parse ──────────────────────────────────────────────────
      if (ocrResult.rawText.isEmpty) {
        setState(() {
          _processing = false;
          _statusMsg  = '⚠️ No text detected. Check image quality / lighting, '
              'or try rotating / cropping.';
        });
        return;
      }

      final defaultRate = await SettingsService.getDefaultRate();
      if (!mounted) return;

      final entries = OcrService.parseOcrResult(
          ocrResult, defaultRate: defaultRate);
      if (!mounted) return;

      if (entries.isEmpty) {
        setState(() {
          _processing = false;
          _statusMsg  = '⚠️ Text was extracted but no valid data rows found.\n'
              'Tap "View Raw OCR" to see what was read.';
        });
        return;
      }

      // ── Step 4: navigate to review ─────────────────────────────────────
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScanReviewScreen(
            imageFile:   _imageFile!,
            entries:     entries,
            defaultRate: defaultRate,
            rawOcrText:  ocrResult.rawText,
          ),
        ),
      );
      if (mounted) setState(() { _processing = false; _statusMsg = ''; });

    } catch (e, stack) {
      if (mounted) {
        setState(() {
          _processing = false;
          _statusMsg  = 'Unexpected error: $e';
        });
        debugPrint('ScanEntry error: $e\n$stack');
      }
    }
  }

  // ── Image sources ────────────────────────────────────────────────────────────

  Future<void> _openFrameCamera() async {
    final result = await Navigator.push<File?>(
      context,
      MaterialPageRoute(builder: (_) => const CameraFrameScreen()),
    );
    if (result != null && mounted) _resetState(result);
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 2400,
        maxHeight: 3200,
      );
      if (picked == null || !mounted) return;
      _resetState(File(picked.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery error: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── API key prompt ────────────────────────────────────────────────────────────

  Future<void> _showApiKeyPrompt() async {
    final ctrl = TextEditingController(text: _cloudApiKey ?? '');
    final key = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cloud Vision API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your Google Cloud Vision API key to enable '
              'handwriting recognition.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'AIza…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Get a key from Google Cloud Console → APIs & Services → Credentials. '
              'Enable the Cloud Vision API.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          if (_cloudApiKey != null)
            TextButton(
              onPressed: () => Navigator.pop(_, ''),
              child: const Text('Remove Key',
                  style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(_),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (key == null || !mounted) return;

    if (key.isEmpty) {
      await SettingsService.setCloudVisionApiKey(null);
      setState(() {
        _cloudApiKey = null;
        _useCloudVision = false;
      });
    } else {
      await SettingsService.setCloudVisionApiKey(key);
      setState(() {
        _cloudApiKey = key;
        _useCloudVision = true;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageFile != null;
    final busy     = _processing || _cropping;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Register Page'),
        actions: [
          if (hasImage && !busy)
            TextButton.icon(
              onPressed: _processImage,
              icon: const Icon(Icons.document_scanner, color: Colors.white),
              label: const Text('Extract',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Tip strip ──────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: Colors.blue.shade50,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              Icon(Icons.tips_and_updates_outlined,
                  size: 15, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rotate to align · Crop to keep only data rows · then Extract',
                  style: TextStyle(
                      fontSize: 11, color: Colors.blue.shade800),
                ),
              ),
            ]),
          ),

          // ── OCR engine toggle ─────────────────────────────────────────
          Container(
            color: _useCloudVision
                ? Colors.deepPurple.shade50
                : Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(children: [
              Icon(
                _useCloudVision ? Icons.cloud : Icons.phone_android,
                size: 16,
                color: _useCloudVision
                    ? Colors.deepPurple.shade700
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _useCloudVision
                      ? 'Cloud Vision (handwriting)'
                      : 'ML Kit (printed text, offline)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _useCloudVision
                        ? Colors.deepPurple.shade700
                        : Colors.grey.shade700,
                  ),
                ),
              ),
              if (_cloudApiKey == null && !_useCloudVision)
                GestureDetector(
                  onTap: () => _showApiKeyPrompt(),
                  child: Text(
                    'Set API Key',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue.shade600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              Switch(
                value: _useCloudVision,
                onChanged: _cloudApiKey != null
                    ? (v) => setState(() => _useCloudVision = v)
                    : (_) => _showApiKeyPrompt(),
                activeTrackColor: Colors.deepPurple.shade200,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.deepPurple
                      : null,
                ),
              ),
            ]),
          ),

          // ── Image preview ──────────────────────────────────────────────
          Expanded(
            child: hasImage ? _buildPreview() : _buildPlaceholder(),
          ),

          // ── Toolbar (rotation + crop) ──────────────────────────────────
          if (hasImage && !busy) _buildToolbar(),

          // ── Status strip ───────────────────────────────────────────────
          if (busy || _statusMsg.isNotEmpty) _buildStatusStrip(),

          // ── Bottom buttons ─────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : _openFrameCamera,
                    icon: const Icon(Icons.document_scanner),
                    label: const Text('Camera + Frame'),
                    style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13)),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),

      floatingActionButton: (hasImage && !busy)
          ? FloatingActionButton.extended(
              onPressed: _processImage,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Extract Data'),
              backgroundColor: Colors.green.shade700,
            )
          : null,
    );
  }

  // ── Toolbar: rotate + crop ────────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          // ── Rotate section ───────────────────────────────────────────
          const Icon(Icons.screen_rotation, size: 14, color: Colors.white54),
          const SizedBox(width: 4),
          const Text('Rotate',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 6),

          _ToolBtn(
            icon: Icons.rotate_left,
            label: '−90°',
            onTap: _rotateLeft,
            tooltip: 'Rotate left 90°',
          ),
          const SizedBox(width: 2),

          // Current angle badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _rotateDeg != 0
                  ? Colors.blue.shade700
                  : Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$_rotateDeg°',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          const SizedBox(width: 2),

          _ToolBtn(
            icon: Icons.rotate_right,
            label: '+90°',
            onTap: _rotateRight,
            tooltip: 'Rotate right 90°',
          ),
          const SizedBox(width: 2),

          _ToolBtn(
            icon: Icons.flip,
            label: '180°',
            onTap: _rotate180,
            tooltip: 'Rotate 180°',
          ),

          if (_rotateDeg != 0) ...[
            const SizedBox(width: 2),
            _ToolBtn(
              icon: Icons.restart_alt,
              label: 'Reset',
              onTap: () => setState(() => _rotateDeg = 0),
              tooltip: 'Reset rotation',
              color: Colors.orange.shade300,
            ),
          ],

          const Spacer(),

          // ── Divider ──────────────────────────────────────────────────
          Container(
              width: 1, height: 28, color: Colors.white24),
          const SizedBox(width: 8),

          // ── Crop button ───────────────────────────────────────────────
          _ToolBtn(
            icon: Icons.crop,
            label: 'Crop',
            onTap: _cropImage,
            tooltip: 'Select & crop data rows',
            color: Colors.greenAccent.shade200,
            large: true,
          ),
        ],
      ),
    );
  }

  // ── Placeholder & preview ─────────────────────────────────────────────────────

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No page selected',
              style: TextStyle(
                  fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Tap "Camera + Frame" to scan the register',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: InteractiveViewer(
            child: Transform.rotate(
              angle: _rotateDeg * pi / 180,
              child: Image.file(_imageFile!, fit: BoxFit.contain),
            ),
          ),
        ),
        // Retake chip
        Positioned(
          top: 8, right: 8,
          child: Material(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _openFrameCamera,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text('Retake',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
        // Crop hint overlay (shown when no crop done yet)
        Positioned(
          bottom: 8, left: 0, right: 0,
          child: Center(
            child: Material(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.crop, size: 13, color: Colors.white70),
                  SizedBox(width: 5),
                  Text('Tap Crop to select only the data rows',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 11)),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusStrip() {
    final isError   = _statusMsg.startsWith('Error:');
    final isWarning = _statusMsg.startsWith('⚠️');
    final isBusy    = _processing || _cropping;
    final bgColor   = isError
        ? Colors.red.shade50
        : isWarning
            ? Colors.orange.shade50
            : Colors.blue.shade50;
    final msgColor  = isError ? Colors.red.shade800 : Colors.black87;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: bgColor,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isBusy)
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 10),
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (isError)
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 8),
                child: Icon(Icons.error_outline,
                    size: 18, color: Colors.red.shade700),
              )
            else if (isWarning)
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 8),
                child: Icon(Icons.warning_amber_outlined,
                    size: 18, color: Colors.orange.shade700),
              ),
            Expanded(
              child: Text(
                _cropping
                    ? 'Opening crop tool…'
                    : _statusMsg.isEmpty
                        ? 'Processing…'
                        : _statusMsg,
                style: TextStyle(fontSize: 13, color: msgColor),
              ),
            ),
          ]),
        ),
        // Show "View Raw OCR" whenever processing fails, even if text is empty
        if (!isBusy && (isWarning || isError))
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showRawOcr(_rawOcr),
                  icon: const Icon(Icons.text_snippet_outlined, size: 16),
                  label: Text(
                    _rawOcr.isEmpty
                        ? 'Raw OCR (empty — check image quality)'
                        : 'View Raw OCR Text',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  void _showRawOcr(String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Raw OCR Output'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty ? '(No text detected)' : text,
              style: const TextStyle(
                  fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Compact toolbar button
// ═══════════════════════════════════════════════════════════════════════════

class _ToolBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final String       tooltip;
  final VoidCallback onTap;
  final Color?       color;
  final bool         large;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white70;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: large ? 10 : 6, vertical: 4),
          decoration: large
              ? BoxDecoration(
                  color: Colors.green.shade800.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.4)),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: c, size: large ? 22 : 18),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      color: c,
                      fontSize: large ? 11 : 9,
                      fontWeight: large
                          ? FontWeight.bold
                          : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}
