import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/scanned_entry.dart';
import '../../providers/customer_provider.dart';
import '../../providers/milk_entry_provider.dart';

class ScanReviewScreen extends StatefulWidget {
  final File        imageFile;
  final List<ScannedEntry> entries;
  final double      defaultRate;
  final String      rawOcrText;

  const ScanReviewScreen({
    super.key,
    required this.imageFile,
    required this.entries,
    required this.defaultRate,
    this.rawOcrText = '',
  });

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late List<ScannedEntry> _entries;
  bool _saving = false;

  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _entries = List.from(widget.entries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerProvider>().loadAll();
    });
  }

  // ── Counts ──────────────────────────────────────────────────────────────────

  int get _validCount    => _entries.where((e) => e.canSave && e.selected).length;
  int get _errorCount    => _entries.where((e) => !e.canSave).length;
  int get _selectedCount => _entries.where((e) => e.selected).length;

  // ── Save all selected valid entries ─────────────────────────────────────────

  Future<void> _saveAll() async {
    final toSave = _entries.where((e) => e.canSave && e.selected).toList();
    if (toSave.isEmpty) return;

    // Confirm
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Save'),
        content: Text(
          'Save ${toSave.length} milk entr${toSave.length == 1 ? 'y' : 'ies'} '
          'to the database?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);

    final milkProv   = context.read<MilkEntryProvider>();
    int saved = 0, failed = 0;

    for (final entry in toSave) {
      try {
        final milkEntry = entry.toMilkEntry();
        await milkProv.add(milkEntry);
        saved++;
      } catch (e) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    final msg = failed == 0
        ? '✅ $saved entr${saved == 1 ? 'y' : 'ies'} saved successfully!'
        : '✅ $saved saved, ⚠️ $failed failed.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: failed == 0 ? Colors.green.shade700 : Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );

    if (saved > 0) Navigator.pop(context);
  }

  // ── Edit one entry ───────────────────────────────────────────────────────────

  Future<void> _editEntry(int idx) async {
    final edited = await showDialog<ScannedEntry>(
      context: context,
      builder: (_) => _EntryEditDialog(
        entry:       _entries[idx],
        defaultRate: widget.defaultRate,
      ),
    );
    if (edited == null || !mounted) return;
    setState(() {
      edited.calculate(widget.defaultRate);
      edited.validate();
      _entries[idx] = edited;
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Scanned Entries'),
        actions: [
          if (widget.rawOcrText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.text_snippet_outlined),
              tooltip: 'Raw OCR text',
              onPressed: () => _showRawOcr(),
            ),
          if (!_saving)
            TextButton(
              onPressed: _validCount > 0 ? _saveAll : null,
              child: Text(
                'Save $_validCount',
                style: TextStyle(
                  color: _validCount > 0 ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Summary bar ──────────────────────────────────────────────────
          _buildSummaryBar(),

          // ── Thumbnail of scanned page ────────────────────────────────────
          GestureDetector(
            onTap: () => _showFullImage(),
            child: Container(
              height: 90,
              color: Colors.black,
              child: Row(children: [
                Image.file(
                  widget.imageFile,
                  width: 70, height: 90,
                  fit: BoxFit.cover,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Scanned page',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11)),
                      Text(
                        '${_entries.length} row${_entries.length == 1 ? '' : 's'} detected',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text('Tap to view full image',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 10)),
                    ],
                  ),
                ),
                const Icon(Icons.fullscreen, color: Colors.white54),
                const SizedBox(width: 8),
              ]),
            ),
          ),

          // ── Entries list ─────────────────────────────────────────────────
          Expanded(
            child: _saving
                ? const Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Saving entries…'),
                    ],
                  ))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _entries.length,
                    itemBuilder: (_, i) => _EntryCard(
                      entry:    _entries[i],
                      index:    i,
                      dateFmt:  _dateFmt,
                      currFmt:  _currFmt,
                      onEdit:   () => _editEntry(i),
                      onToggle: (val) => setState(() =>
                          _entries[i].selected = val ?? false),
                    ),
                  ),
          ),

          // ── Bottom save bar ──────────────────────────────────────────────
          if (!_saving)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _validCount > 0 ? _saveAll : null,
                    icon: const Icon(Icons.save),
                    label: Text(
                      _validCount > 0
                          ? 'Save $_validCount Valid Entr${_validCount == 1 ? 'y' : 'ies'}'
                          : 'No valid entries to save',
                      style: const TextStyle(fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    return Container(
      color: Colors.blue.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryChip(
              label: 'Total',
              value: '${_entries.length}',
              color: Colors.white),
          _SummaryChip(
              label: 'Valid',
              value: '$_validCount',
              color: Colors.greenAccent),
          _SummaryChip(
              label: 'Errors',
              value: '$_errorCount',
              color: _errorCount > 0 ? Colors.redAccent : Colors.white),
          _SummaryChip(
              label: 'Selected',
              value: '$_selectedCount',
              color: Colors.amberAccent),
        ],
      ),
    );
  }

  void _showRawOcr() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Raw OCR Text'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              widget.rawOcrText.isEmpty
                  ? '(empty)'
                  : widget.rawOcrText,
              style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace'),
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

  void _showFullImage() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          InteractiveViewer(
            child: Image.file(widget.imageFile, fit: BoxFit.contain),
          ),
          Positioned(
            top: 8, right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(_),
            ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Entry card widget
// ═══════════════════════════════════════════════════════════════════════════

class _EntryCard extends StatelessWidget {
  final ScannedEntry entry;
  final int          index;
  final DateFormat   dateFmt;
  final NumberFormat currFmt;
  final VoidCallback onEdit;
  final ValueChanged<bool?> onToggle;

  const _EntryCard({
    required this.entry,
    required this.index,
    required this.dateFmt,
    required this.currFmt,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final status      = entry.status;
    final headerColor = status == ScanStatus.hasErrors
        ? Colors.red.shade700
        : status == ScanStatus.hasWarnings
            ? Colors.orange.shade700
            : Colors.green.shade700;
    final bgColor = status == ScanStatus.hasErrors
        ? Colors.red.shade50
        : status == ScanStatus.hasWarnings
            ? Colors.orange.shade50
            : Colors.green.shade50;

    return Card(
      margin:       const EdgeInsets.only(bottom: 10),
      color:        bgColor,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: headerColor.withValues(alpha: 0.4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10)),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            child: Row(children: [
              // Include checkbox
              Transform.scale(
                scale: 0.85,
                child: Checkbox(
                  value:           entry.selected,
                  onChanged:       entry.canSave ? onToggle : null,
                  fillColor:       WidgetStateProperty.all(Colors.white),
                  checkColor:      headerColor,
                  side: const BorderSide(color: Colors.white),
                ),
              ),
              Text(
                'Row ${index + 1}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status == ScanStatus.valid
                      ? '✓ Valid'
                      : status == ScanStatus.hasWarnings
                          ? '⚠ Warnings'
                          : '✗ Errors',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Row(mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 14),
                      SizedBox(width: 4),
                      Text('Edit', style: TextStyle(fontSize: 12)),
                    ]),
              ),
            ]),
          ),

          // ── Field grid ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Field('CID',    entry.customerId?.toString() ?? '—'),
                _Field('Date',   entry.date != null
                    ? dateFmt.format(entry.date!)
                    : '—'),
                _Field('Shift',  entry.shift ?? '—'),
                _Field('Type',   entry.milkType ?? '—'),
                _Field('Qty',    entry.quantity != null
                    ? '${entry.quantity!.toStringAsFixed(2)} L'
                    : '—'),
                _Field('FAT%',   entry.fat != null
                    ? '${entry.fat!.toStringAsFixed(2)}%'
                    : '—'),
                _Field('Rate',   entry.rate != null
                    ? entry.rate!.toStringAsFixed(2)
                    : '—'),
                _Field('KG Fat', entry.kgFat != null
                    ? entry.kgFat!.toStringAsFixed(3)
                    : 'Auto'),
                if (entry.itemName != null)
                  _Field('Item', entry.itemName!),
                if ((entry.itemAmount ?? 0) > 0)
                  _Field('Deduction',
                      '−₹${entry.itemAmount!.toStringAsFixed(0)}'),
                _Field('Amount', entry.amount != null
                    ? '₹${currFmt.format(entry.amount!)}'
                    : 'Auto'),
              ],
            ),
          ),

          // ── Errors / Warnings ────────────────────────────────────────────
          if (entry.errors.isNotEmpty || entry.warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...entry.errors.map((e) => _IssueRow(
                      icon: Icons.error_outline,
                      color: Colors.red.shade700,
                      text: e)),
                  ...entry.warnings.map((w) => _IssueRow(
                      icon: Icons.warning_amber_outlined,
                      color: Colors.orange.shade700,
                      text: w)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label, value;
  const _Field(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9, color: Colors.grey.shade500)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   text;
  const _IssueRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: color))),
      ]),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _SummaryChip(
      {required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: const TextStyle(
              color: Colors.white70, fontSize: 10)),
      const SizedBox(height: 2),
      Text(value,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16)),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Entry Edit Dialog
// ═══════════════════════════════════════════════════════════════════════════

class _EntryEditDialog extends StatefulWidget {
  final ScannedEntry entry;
  final double       defaultRate;
  const _EntryEditDialog(
      {required this.entry, required this.defaultRate});

  @override
  State<_EntryEditDialog> createState() => _EntryEditDialogState();
}

class _EntryEditDialogState extends State<_EntryEditDialog> {
  late final TextEditingController _cidCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _itemCtrl;
  late final TextEditingController _dedCtrl;

  late String  _shift;
  late String  _milkType;

  final _dateFmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _cidCtrl  = TextEditingController(
        text: e.customerId?.toString() ?? '');
    _dateCtrl = TextEditingController(
        text: e.date != null ? _dateFmt.format(e.date!) : '');
    _qtyCtrl  = TextEditingController(
        text: e.quantity?.toStringAsFixed(2) ?? '');
    _fatCtrl  = TextEditingController(
        text: e.fat?.toStringAsFixed(2) ?? '');
    _rateCtrl = TextEditingController(
        text: e.rate?.toStringAsFixed(2) ?? '');
    _itemCtrl = TextEditingController(text: e.itemName ?? '');
    _dedCtrl  = TextEditingController(
        text: e.itemAmount != null && e.itemAmount! > 0
            ? e.itemAmount!.toStringAsFixed(2)
            : '');
    _shift    = e.shift    ?? 'Morning';
    _milkType = e.milkType ?? 'Cow';
  }

  @override
  void dispose() {
    _cidCtrl.dispose(); _dateCtrl.dispose();
    _qtyCtrl.dispose(); _fatCtrl.dispose();
    _rateCtrl.dispose(); _itemCtrl.dispose();
    _dedCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String s) {
    try {
      return DateFormat('dd/MM/yyyy').parse(s.trim());
    } catch (_) {
      try { return DateFormat('d/M/yyyy').parse(s.trim()); }
      catch (_) { return null; }
    }
  }

  void _save() {
    final edited = widget.entry.copyWith(
      customerId:  int.tryParse(_cidCtrl.text.trim()),
      date:        _parseDate(_dateCtrl.text),
      shift:       _shift,
      milkType:    _milkType,
      quantity:    double.tryParse(_qtyCtrl.text.trim()),
      fat:         double.tryParse(_fatCtrl.text.trim()),
      rate:        double.tryParse(_rateCtrl.text.trim()),
      itemName:    _itemCtrl.text.trim().isEmpty
                       ? null : _itemCtrl.text.trim(),
      itemAmount:  double.tryParse(_dedCtrl.text.trim()),
    )
      // Force recalculate
      ..kgFat = null
      ..amount = null;
    Navigator.of(context).pop(edited);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Entry'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Row: CID + Date ──────────────────────────────────────
              Row(children: [
                Expanded(
                  child: _tf(_cidCtrl, 'CID *',
                      keyboardType: TextInputType.number),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _tf(_dateCtrl, 'Date (dd/MM/yyyy) *'),
                ),
              ]),
              const SizedBox(height: 10),

              // ── Row: Shift + Type ────────────────────────────────────
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _shift,
                    decoration: const InputDecoration(
                        labelText: 'Shift *',
                        isDense: true),
                    items: const [
                      DropdownMenuItem(
                          value: 'Morning', child: Text('Morning')),
                      DropdownMenuItem(
                          value: 'Evening', child: Text('Evening')),
                    ],
                    onChanged: (v) =>
                        setState(() => _shift = v ?? 'Morning'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _milkType,
                    decoration: const InputDecoration(
                        labelText: 'Type *',
                        isDense: true),
                    items: const [
                      DropdownMenuItem(
                          value: 'Cow', child: Text('Cow (C)')),
                      DropdownMenuItem(
                          value: 'Buffalo',
                          child: Text('Buffalo (B)')),
                    ],
                    onChanged: (v) =>
                        setState(() => _milkType = v ?? 'Cow'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),

              // ── Row: Qty + FAT ───────────────────────────────────────
              Row(children: [
                Expanded(
                  child: _tf(_qtyCtrl, 'Qty (L) *',
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _tf(_fatCtrl, 'FAT % *',
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true)),
                ),
              ]),
              const SizedBox(height: 10),

              // ── Rate ─────────────────────────────────────────────────
              _tf(_rateCtrl, 'Rate (leave blank for default)',
                  keyboardType: const TextInputType
                      .numberWithOptions(decimal: true)),
              const SizedBox(height: 10),

              // ── Row: Item + Deduction ────────────────────────────────
              Row(children: [
                Expanded(child: _tf(_itemCtrl, 'Item Purchased')),
                const SizedBox(width: 8),
                Expanded(
                  child: _tf(_dedCtrl, 'Deduction (₹)',
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true)),
                ),
              ]),
              const SizedBox(height: 6),

              // Note about CLR
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: Colors.amber.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline,
                      size: 13,
                      color: Colors.amber.shade800),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'KG Fat and Amount are auto-calculated. '
                      'CLR defaults to 0 for scanned entries.',
                      style:
                          TextStyle(fontSize: 11, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _tf(TextEditingController ctrl, String label,
      {TextInputType? keyboardType}) {
    return TextField(
      controller:  ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText:       label,
        isDense:         true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
