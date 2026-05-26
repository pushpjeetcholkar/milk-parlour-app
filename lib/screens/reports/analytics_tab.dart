import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/milk_entry_provider.dart';

// ── Granularity enum ──────────────────────────────────────────────────────────
enum _Gran { day, week, month }

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to   = DateTime.now();

  bool _loading      = false;
  bool _shiftLoading = false;

  List<Map<String, dynamic>> _customers    = [];
  List<Map<String, dynamic>> _daily        = [];
  List<Map<String, dynamic>> _shiftTotals  = [];
  List<Map<String, dynamic>> _custShifts   = [];
  List<Map<String, dynamic>> _periodShifts = [];

  _Gran _gran = _Gran.day;

  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _customers = []; _daily = [];
      _shiftTotals = []; _custShifts = []; _periodShifts = [];
    });
    final prov = context.read<MilkEntryProvider>();
    try {
      final results = await Future.wait([
        prov.getCustomerRangeSummary(_from, _to),
        prov.getDailyBreakdown(_from, _to),
        prov.getShiftTotals(_from, _to),
        prov.getCustomerShiftSummary(_from, _to),
        _fetchPeriodShifts(prov),
      ]);
      if (mounted) {
        setState(() {
          _customers    = results[0];
          _daily        = results[1];
          _shiftTotals  = results[2];
          _custShifts   = results[3];
          _periodShifts = results[4];
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPeriodShifts(
      MilkEntryProvider prov) {
    switch (_gran) {
      case _Gran.day:   return prov.getDailyShiftBreakdown(_from, _to);
      case _Gran.week:  return prov.getWeeklyShiftBreakdown(_from, _to);
      case _Gran.month: return prov.getMonthlyShiftBreakdown(_from, _to);
    }
  }

  Future<void> _reloadPeriodShifts() async {
    if (!mounted) return;
    setState(() => _shiftLoading = true);
    final prov = context.read<MilkEntryProvider>();
    final data = await _fetchPeriodShifts(prov);
    if (mounted) setState(() { _periodShifts = data; _shiftLoading = false; });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildDateBar(),
        Expanded(
          child: _loading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Crunching the numbers…',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : _customers.isEmpty
                  ? _buildEmpty()
                  : _buildCharts(),
        ),
      ],
    );
  }

  // ── Date bar ──────────────────────────────────────────────────────────────

  Widget _buildDateBar() {
    return Container(
      color: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _DateChip(
            label: 'From',
            date: _dateFmt.format(_from),
            onTap: () => _pickDate(isFrom: true),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('→', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          _DateChip(
            label: 'To',
            date: _dateFmt.format(_to),
            onTap: () => _pickDate(isFrom: false),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Load'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('No data for this period.',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
          SizedBox(height: 6),
          Text('Add milk entries or adjust the date range.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  // ── Chart sections ────────────────────────────────────────────────────────

  Widget _buildCharts() {
    final totalQty = _customers.fold<double>(
        0, (s, r) => s + (r['total_quantity'] as num).toDouble());
    final totalKgF = _customers.fold<double>(
        0, (s, r) => s + ((r['total_kgfat'] as num?)?.toDouble() ?? 0));
    final totalAmt = _customers.fold<double>(
        0, (s, r) => s + (r['total_amount'] as num).toDouble());
    final totalDays = _to.difference(_from).inDays + 1;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSummaryStrip(totalQty, totalKgF, totalAmt, totalDays),
        const SizedBox(height: 16),

        _ChartCard(
          title: '🥛 Milk Volume Leaders',
          subtitle: 'Top customers by total litres collected',
          child: _buildMilkVolumeChart(),
        ),
        const SizedBox(height: 16),

        _ChartCard(
          title: '💰 Payment Leaders',
          subtitle: 'Who we pay the most (total amount)',
          child: _buildAmountChart(),
        ),
        const SizedBox(height: 16),

        _ChartCard(
          title: '📈 Daily Milk Trend',
          subtitle: 'Total litres collected per day',
          child: _buildDailyTrendChart(),
        ),
        const SizedBox(height: 16),

        _ChartCard(
          title: '⭐ FAT Quality Rankings',
          subtitle: 'Average FAT% — higher means richer milk',
          child: _buildFatQualityList(),
        ),
        const SizedBox(height: 16),

        _ChartCard(
          title: '📅 Attendance & Consistency',
          subtitle: 'Present (green) vs Absent (red) out of $totalDays days',
          child: _buildAttendanceList(totalDays),
        ),
        const SizedBox(height: 16),

        _ChartCard(
          title: '☀️🌙 Shift Distribution',
          subtitle: 'Morning vs Evening — milk, KG FAT & payment breakdown',
          child: _buildShiftSection(),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Summary strip ─────────────────────────────────────────────────────────

  Widget _buildSummaryStrip(double qty, double kgf, double amt, int days) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat('Customers', '${_customers.length}', Icons.people),
          _Stat('Total Qty', '${qty.toStringAsFixed(1)} L', Icons.water_drop),
          _Stat('KG FAT', kgf.toStringAsFixed(2), Icons.oil_barrel),
          _Stat('Amount', 'INR ${_compactNum(amt)}', Icons.currency_rupee),
        ],
      ),
    );
  }

  String _compactNum(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)   return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  // ── Chart 1: Milk Volume ──────────────────────────────────────────────────

  Widget _buildMilkVolumeChart() {
    final top = _customers.take(8).toList();
    if (top.isEmpty) return const _NoData();
    final maxY = top.fold<double>(
        0, (m, r) => max(m, (r['total_quantity'] as num).toDouble()));

    return SizedBox(
      height: 220,
      child: BarChart(BarChartData(
        maxY: maxY * 1.25,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey.shade800,
            getTooltipItem: (group, _, rod, __) {
              final name = top[group.x]['customer_name'] as String? ?? '';
              return BarTooltipItem('$name\n${rod.toY.toStringAsFixed(2)} L',
                  const TextStyle(color: Colors.white, fontSize: 11));
            },
          ),
        ),
        titlesData: _barTitles(
          bottomLabels: top.map((r) => (r['customer_name'] as String? ?? '').split(' ').first).toList(),
        ),
        gridData: _gridData(),
        borderData: FlBorderData(show: false),
        barGroups: top.asMap().entries.map((e) {
          final qty = (e.value['total_quantity'] as num).toDouble();
          return BarChartGroupData(x: e.key, barRods: [
            BarChartRodData(
              toY: qty,
              gradient: LinearGradient(
                colors: [Colors.blue.shade300, Colors.blue.shade700],
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
              ),
              width: 22,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ]);
        }).toList(),
      )),
    );
  }

  // ── Chart 2: Amount ───────────────────────────────────────────────────────

  Widget _buildAmountChart() {
    final sorted = List<Map<String, dynamic>>.from(_customers)
      ..sort((a, b) => (b['total_amount'] as num).compareTo(a['total_amount'] as num));
    final top = sorted.take(8).toList();
    if (top.isEmpty) return const _NoData();
    final maxY = (top.first['total_amount'] as num).toDouble();

    return SizedBox(
      height: 220,
      child: BarChart(BarChartData(
        maxY: maxY * 1.25,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey.shade800,
            getTooltipItem: (group, _, rod, __) {
              final name = top[group.x]['customer_name'] as String? ?? '';
              return BarTooltipItem('$name\nINR ${_currFmt.format(rod.toY)}',
                  const TextStyle(color: Colors.white, fontSize: 11));
            },
          ),
        ),
        titlesData: _barTitles(
          bottomLabels: top.map((r) => (r['customer_name'] as String? ?? '').split(' ').first).toList(),
          leftFormatter: _compactNum,
        ),
        gridData: _gridData(),
        borderData: FlBorderData(show: false),
        barGroups: top.asMap().entries.map((e) {
          final amt = (e.value['total_amount'] as num).toDouble();
          return BarChartGroupData(x: e.key, barRods: [
            BarChartRodData(
              toY: amt,
              gradient: LinearGradient(
                colors: [Colors.green.shade300, Colors.green.shade700],
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
              ),
              width: 22,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ]);
        }).toList(),
      )),
    );
  }

  // ── Chart 3: Daily Trend ──────────────────────────────────────────────────

  Widget _buildDailyTrendChart() {
    if (_daily.isEmpty) return const _NoData();
    final maxY = _daily.fold<double>(
            0, (m, r) => max(m, (r['total_quantity'] as num).toDouble())) * 1.25;
    final interval = max(1, (_daily.length / 6).floor()).toDouble();

    return SizedBox(
      height: 220,
      child: LineChart(LineChartData(
        minY: 0, maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: _daily.asMap().entries.map((e) {
              final qty = (e.value['total_quantity'] as num).toDouble();
              return FlSpot(e.key.toDouble(), qty);
            }).toList(),
            isCurved: true, curveSmoothness: 0.35,
            color: Colors.blue.shade600, barWidth: 2.5,
            dotData: FlDotData(
              show: _daily.length <= 20,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3, color: Colors.blue.shade700,
                strokeColor: Colors.white, strokeWidth: 1.5,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade200.withValues(alpha: 0.4),
                  Colors.blue.shade50.withValues(alpha: 0.05),
                ],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 24, interval: interval,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= _daily.length) return const SizedBox();
                final s = _daily[i]['period_label'] as String? ?? '';
                try {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(DateFormat('d/M').format(DateTime.parse(s)),
                        style: const TextStyle(fontSize: 9)),
                  );
                } catch (_) {
                  return Text(s, style: const TextStyle(fontSize: 9));
                }
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 44,
              getTitlesWidget: (v, _) =>
                  Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 9)),
            ),
          ),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: _gridData(),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey.shade800,
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.x.toInt();
              final ds = i < _daily.length ? _daily[i]['period_label'] as String? ?? '' : '';
              String label = ds;
              try { label = DateFormat('dd MMM').format(DateTime.parse(ds)); } catch (_) {}
              return LineTooltipItem('$label\n${s.y.toStringAsFixed(2)} L',
                  const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold));
            }).toList(),
          ),
        ),
      )),
    );
  }

  // ── Chart 4: FAT Quality ──────────────────────────────────────────────────

  Widget _buildFatQualityList() {
    final sorted = List<Map<String, dynamic>>.from(_customers)
      ..sort((a, b) => (b['avg_fat'] as num).compareTo(a['avg_fat'] as num));
    if (sorted.isEmpty) return const _NoData();
    final maxFat = (sorted.first['avg_fat'] as num).toDouble();

    return Column(
      children: sorted.take(10).map((r) {
        final name  = r['customer_name'] as String? ?? '—';
        final fat   = (r['avg_fat'] as num).toDouble();
        final pct   = maxFat > 0 ? fat / maxFat : 0.0;
        final color = fat >= 6.0
            ? Colors.green.shade600
            : fat >= 4.5 ? Colors.orange.shade600 : Colors.red.shade400;
        return _RankRow(
          name: name, value: '${fat.toStringAsFixed(2)}%',
          fraction: pct, color: color, icon: Icons.star_rounded,
        );
      }).toList(),
    );
  }

  // ── Chart 5: Attendance — stacked Present + Absent bar ───────────────────

  Widget _buildAttendanceList(int totalDays) {
    final sorted = List<Map<String, dynamic>>.from(_customers)
      ..sort((a, b) =>
          (b['days_present'] as int).compareTo(a['days_present'] as int));
    if (sorted.isEmpty) return const _NoData();

    return Column(
      children: [
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: Colors.green.shade500, label: 'Present'),
            const SizedBox(width: 16),
            _LegendDot(color: Colors.red.shade300, label: 'Absent'),
          ],
        ),
        const SizedBox(height: 10),
        ...sorted.take(10).map((r) {
          final name    = r['customer_name'] as String? ?? '—';
          final present = r['days_present'] as int;
          final absent  = (totalDays - present).clamp(0, totalDays);
          final pct     = totalDays > 0 ? present / totalDays : 0.0;
          final color   = pct >= 0.85
              ? Colors.green.shade600
              : pct >= 0.6 ? Colors.orange.shade600 : Colors.red.shade600;
          return _AttendanceRow(
            name: name,
            present: present,
            absent: absent,
            total: totalDays,
            presentColor: color,
            pct: pct,
          );
        }),
      ],
    );
  }

  // ── Chart 6: Shift Distribution — full rewrite ────────────────────────────

  Widget _buildShiftSection() {
    if (_shiftTotals.isEmpty) return const _NoData();

    // Helper to find shift row
    Map<String, dynamic> shiftRow(String name) => _shiftTotals.firstWhere(
        (r) => (r['shift'] as String? ?? '').toLowerCase() ==
            name.toLowerCase(),
        orElse: () => {});

    final mRow = shiftRow('Morning');
    final eRow = shiftRow('Evening');

    final mQty = (mRow['total_quantity'] as num?)?.toDouble() ?? 0;
    final eQty = (eRow['total_quantity'] as num?)?.toDouble() ?? 0;
    final mKgf = (mRow['total_kgfat'] as num?)?.toDouble() ?? 0;
    final eKgf = (eRow['total_kgfat'] as num?)?.toDouble() ?? 0;
    final mAmt = (mRow['total_amount'] as num?)?.toDouble() ?? 0;
    final eAmt = (eRow['total_amount'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Overall shift summary cards ──────────────────────────────────
        Row(
          children: [
            Expanded(child: _ShiftCard(
              label: '☀️ Morning', qty: mQty, kgf: mKgf, amt: mAmt,
              color: Colors.blue.shade600,
            )),
            const SizedBox(width: 8),
            Expanded(child: _ShiftCard(
              label: '🌙 Evening', qty: eQty, kgf: eKgf, amt: eAmt,
              color: Colors.orange.shade600,
            )),
          ],
        ),
        const SizedBox(height: 16),

        // ── Granularity selector ─────────────────────────────────────────
        Row(
          children: [
            Text('View by:', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: Colors.grey.shade700)),
            const SizedBox(width: 8),
            ..._Gran.values.map((g) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(g == _Gran.day ? 'Day' : g == _Gran.week ? 'Week' : 'Month',
                    style: const TextStyle(fontSize: 11)),
                selected: _gran == g,
                selectedColor: Colors.blue.shade100,
                onSelected: (_) {
                  setState(() => _gran = g);
                  _reloadPeriodShifts();
                },
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            )),
          ],
        ),
        const SizedBox(height: 10),

        // ── Period grouped bar chart ─────────────────────────────────────
        if (_shiftLoading)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else if (_periodShifts.isNotEmpty)
          _buildPeriodShiftChart(),

        const SizedBox(height: 4),

        // Legend for chart
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: Colors.blue.shade600,   label: 'Morning'),
            const SizedBox(width: 16),
            _LegendDot(color: Colors.orange.shade600, label: 'Evening'),
          ],
        ),
        const SizedBox(height: 16),

        // ── Per-customer shift breakdown ─────────────────────────────────
        Text('By Customer', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold,
            color: Colors.grey.shade800)),
        const SizedBox(height: 8),
        _buildCustomerShiftList(),
      ],
    );
  }

  Widget _buildPeriodShiftChart() {
    // Pivot: period_label → {morning: qty, evening: qty}
    final Map<String, Map<String, double>> grouped = {};
    for (final row in _periodShifts) {
      final period = (row['week_start'] ?? row['period_label']) as String? ?? '';
      final shift  = (row['shift'] as String? ?? '').toLowerCase();
      final qty    = (row['total_quantity'] as num?)?.toDouble() ?? 0;
      grouped.putIfAbsent(period, () => {});
      grouped[period]![shift] = qty;
    }

    final periods = grouped.keys.toList()..sort();
    if (periods.isEmpty) return const _NoData();

    double maxY = 0;
    for (final v in grouped.values) {
      maxY = max(maxY, (v['morning'] ?? 0));
      maxY = max(maxY, (v['evening'] ?? 0));
    }
    maxY = (maxY * 1.3).ceilToDouble();
    if (maxY == 0) maxY = 10;

    final showEveryN = max(1, (periods.length / 7).ceil());

    return SizedBox(
      height: 210,
      child: BarChart(BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey.shade800,
            getTooltipItem: (group, _, rod, rodIndex) {
              final shiftName = rodIndex == 0 ? '☀️ Morning' : '🌙 Evening';
              return BarTooltipItem(
                '$shiftName\n${rod.toY.toStringAsFixed(2)} L',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 32,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= periods.length || i % showEveryN != 0) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_formatPeriodLabel(periods[i]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 8)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 40,
              getTitlesWidget: (v, _) =>
                  Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 9)),
            ),
          ),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: _gridData(),
        borderData: FlBorderData(show: false),
        barGroups: periods.asMap().entries.map((e) {
          final data    = grouped[e.value]!;
          final morning = data['morning'] ?? 0;
          final evening = data['evening'] ?? 0;
          return BarChartGroupData(
            x: e.key,
            barsSpace: 2,
            barRods: [
              BarChartRodData(
                toY: morning, color: Colors.blue.shade600, width: 9,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
              BarChartRodData(
                toY: evening, color: Colors.orange.shade500, width: 9,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ],
          );
        }).toList(),
      )),
    );
  }

  String _formatPeriodLabel(String period) {
    try {
      if (period.contains('-W')) return 'W${period.split('-W')[1]}';
      if (period.length == 7) {
        return DateFormat('MMM\nyy').format(DateTime.parse('$period-01'));
      }
      return DateFormat('d\nMMM').format(DateTime.parse(period));
    } catch (_) { return period; }
  }

  Widget _buildCustomerShiftList() {
    if (_custShifts.isEmpty) return const _NoData();

    // Group by customer name
    final Map<String, Map<String, double>> byCustomer = {};
    for (final row in _custShifts) {
      final name  = row['customer_name'] as String? ?? '—';
      final shift = (row['shift'] as String? ?? '').toLowerCase();
      final qty   = (row['total_quantity'] as num?)?.toDouble() ?? 0;
      final kgf   = (row['total_kgfat'] as num?)?.toDouble() ?? 0;
      byCustomer.putIfAbsent(name, () => {});
      byCustomer[name]!['${shift}_qty'] = qty;
      byCustomer[name]!['${shift}_kgf'] = kgf;
    }

    return Column(
      children: byCustomer.entries.map((e) {
        final name    = e.key;
        final mQty    = e.value['morning_qty'] ?? 0;
        final eQty    = e.value['evening_qty'] ?? 0;
        final mKgf    = e.value['morning_kgf'] ?? 0;
        final eKgf    = e.value['evening_kgf'] ?? 0;
        final total   = mQty + eQty;
        final mFlex   = total > 0 ? ((mQty / total) * 100).round().clamp(1, 99) : 50;
        final eFlex   = (100 - mFlex).clamp(1, 99);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person, size: 13, color: Colors.blueGrey),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(name, style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${total.toStringAsFixed(1)} L',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    flex: mFlex,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade500,
                            borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('☀️ ${mQty.toStringAsFixed(1)}L  ${mKgf.toStringAsFixed(2)}kgf',
                            style: TextStyle(fontSize: 9, color: Colors.blue.shade700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: eFlex,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade500,
                            borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('🌙 ${eQty.toStringAsFixed(1)}L  ${eKgf.toStringAsFixed(2)}kgf',
                            style: TextStyle(fontSize: 9, color: Colors.orange.shade700)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  FlTitlesData _barTitles({
    required List<String> bottomLabels,
    String Function(double)? leftFormatter,
  }) {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true, reservedSize: 30,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= bottomLabels.length) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(bottomLabels[i], style: const TextStyle(fontSize: 8.5)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true, reservedSize: 48,
          getTitlesWidget: (v, _) => Text(
            leftFormatter != null ? leftFormatter(v) : v.toStringAsFixed(0),
            style: const TextStyle(fontSize: 9),
          ),
        ),
      ),
      topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  FlGridData _gridData() => FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (v) =>
            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  Reusable widgets
// ═══════════════════════════════════════════════════════════════════════════

class _ChartCard extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  const _ChartCard({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: Colors.white70, size: 18),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
    ]);
  }
}

class _RankRow extends StatelessWidget {
  final String name, value;
  final double fraction;
  final Color color;
  final IconData icon;
  final String? trailing;
  const _RankRow({required this.name, required this.value, required this.fraction,
      required this.color, required this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis)),
          Text(trailing ?? value,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        if (trailing != null)
          Align(alignment: Alignment.centerRight,
              child: Text(value, style: const TextStyle(fontSize: 10, color: Colors.grey))),
      ]),
    );
  }
}

/// Attendance row: single stacked bar — green (present) + red (absent).
class _AttendanceRow extends StatelessWidget {
  final String name;
  final int present, absent, total;
  final Color presentColor;
  final double pct;

  const _AttendanceRow({
    required this.name, required this.present, required this.absent,
    required this.total, required this.presentColor, required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    final presentFlex = total > 0 ? present.clamp(0, total) : 0;
    final absentFlex  = total > 0 ? absent.clamp(0, total)  : total;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calendar_today, size: 13, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Expanded(child: Text(name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis)),
          Text('$present / $total',
              style: TextStyle(fontSize: 12, color: presentColor, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Text('${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(children: [
            if (presentFlex > 0)
              Expanded(
                flex: presentFlex,
                child: Container(height: 8, color: presentColor),
              ),
            if (absentFlex > 0)
              Expanded(
                flex: absentFlex,
                child: Container(height: 8, color: Colors.red.shade200),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final String label;
  final double qty, kgf, amt;
  final Color color;
  const _ShiftCard({required this.label, required this.qty, required this.kgf,
      required this.amt, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
        const SizedBox(height: 6),
        Text('${qty.toStringAsFixed(1)} L', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        Text('${kgf.toStringAsFixed(3)} KG FAT', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text('INR ${NumberFormat('#,##0.00').format(amt)}',
            style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
      ]),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ]);
  }
}

class _DateChip extends StatelessWidget {
  final String label, date;
  final VoidCallback onTap;
  const _DateChip({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white, border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text('No data available for this period.',
            style: TextStyle(color: Colors.grey)),
      ),
    );
  }
}
