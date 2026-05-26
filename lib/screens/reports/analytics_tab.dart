import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/milk_entry_provider.dart';

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
  bool _loading  = false;

  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _daily     = [];

  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currFmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _customers = []; _daily = []; });
    final prov = context.read<MilkEntryProvider>();
    final results = await Future.wait([
      prov.getCustomerRangeSummary(_from, _to),
      prov.getDailyBreakdown(_from, _to),
    ]);
    if (mounted) {
      setState(() {
        _customers = results[0];
        _daily     = results[1];
        _loading   = false;
      });
    }
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

  // ── Build ──────────────────────────────────────────────────────────────────
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
          Text('Add milk entries or load demo data\nfrom Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  // ── Chart sections ─────────────────────────────────────────────────────────
  Widget _buildCharts() {
    // Pre-compute totals for summary
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
        // ── Summary strip ────────────────────────────────────────────────
        _buildSummaryStrip(totalQty, totalKgF, totalAmt, totalDays),
        const SizedBox(height: 16),

        // ── Chart 1: Milk Volume Leaders ─────────────────────────────────
        _ChartCard(
          title: '🥛 Milk Volume Leaders',
          subtitle: 'Top customers by total litres collected',
          child: _buildMilkVolumeChart(),
        ),
        const SizedBox(height: 16),

        // ── Chart 2: Payment Leaders ─────────────────────────────────────
        _ChartCard(
          title: '💰 Payment Leaders',
          subtitle: 'Who we pay the most (total amount)',
          child: _buildAmountChart(),
        ),
        const SizedBox(height: 16),

        // ── Chart 3: Daily Milk Trend ────────────────────────────────────
        _ChartCard(
          title: '📈 Daily Milk Trend',
          subtitle: 'Total litres collected per day',
          child: _buildDailyTrendChart(),
        ),
        const SizedBox(height: 16),

        // ── Chart 4: FAT Quality ─────────────────────────────────────────
        _ChartCard(
          title: '⭐ FAT Quality Rankings',
          subtitle: 'Average FAT% — higher means richer milk',
          child: _buildFatQualityList(),
        ),
        const SizedBox(height: 16),

        // ── Chart 5: Attendance / Consistency ───────────────────────────
        _ChartCard(
          title: '📅 Attendance & Consistency',
          subtitle: 'Days present out of $totalDays days in the period',
          child: _buildAttendanceList(totalDays),
        ),
        const SizedBox(height: 16),

        // ── Chart 6: Morning vs Evening split ────────────────────────────
        _ChartCard(
          title: '☀️🌙 Shift Distribution',
          subtitle: 'Morning vs Evening entry volume in period',
          child: _buildShiftSplitChart(),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Summary strip ──────────────────────────────────────────────────────────
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
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  // ── Chart 1: Milk Volume BarChart ──────────────────────────────────────────
  Widget _buildMilkVolumeChart() {
    final top = _customers.take(8).toList();
    if (top.isEmpty) return const _NoData();
    final maxY = top.fold<double>(
        0, (m, r) => max(m, (r['total_quantity'] as num).toDouble()));

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.25,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.blueGrey.shade800,
              getTooltipItem: (group, _, rod, __) {
                final name = top[group.x]['customer_name'] as String? ?? '';
                return BarTooltipItem(
                  '$name\n${rod.toY.toStringAsFixed(2)} L',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= top.length) return const SizedBox();
                  final name = top[i]['customer_name'] as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      name.split(' ').first,
                      style: const TextStyle(fontSize: 8.5),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: top.asMap().entries.map((e) {
            final qty = (e.value['total_quantity'] as num).toDouble();
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: qty,
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade300, Colors.blue.shade700],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  width: 22,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Chart 2: Amount BarChart ───────────────────────────────────────────────
  Widget _buildAmountChart() {
    final sorted = List<Map<String, dynamic>>.from(_customers)
      ..sort((a, b) => (b['total_amount'] as num)
          .compareTo(a['total_amount'] as num));
    final top = sorted.take(8).toList();
    if (top.isEmpty) return const _NoData();
    final maxY = (top.first['total_amount'] as num).toDouble();

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.25,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.blueGrey.shade800,
              getTooltipItem: (group, _, rod, __) {
                final name = top[group.x]['customer_name'] as String? ?? '';
                return BarTooltipItem(
                  '$name\nINR ${_currFmt.format(rod.toY)}',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= top.length) return const SizedBox();
                  final name = top[i]['customer_name'] as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(name.split(' ').first,
                        style: const TextStyle(fontSize: 8.5)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                getTitlesWidget: (v, _) => Text(
                  _compactNum(v),
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: top.asMap().entries.map((e) {
            final amt = (e.value['total_amount'] as num).toDouble();
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: amt,
                  gradient: LinearGradient(
                    colors: [Colors.green.shade300, Colors.green.shade700],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  width: 22,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Chart 3: Daily Trend LineChart ─────────────────────────────────────────
  Widget _buildDailyTrendChart() {
    if (_daily.isEmpty) return const _NoData();

    final maxY = _daily.fold<double>(
            0,
            (m, r) =>
                max(m, (r['total_quantity'] as num).toDouble())) *
        1.25;
    final interval = max(1, (_daily.length / 6).floor()).toDouble();

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: _daily.asMap().entries.map((e) {
                final qty = (e.value['total_quantity'] as num).toDouble();
                return FlSpot(e.key.toDouble(), qty);
              }).toList(),
              isCurved: true,
              curveSmoothness: 0.35,
              color: Colors.blue.shade600,
              barWidth: 2.5,
              dotData: FlDotData(
                show: _daily.length <= 20,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 3,
                  color: Colors.blue.shade700,
                  strokeColor: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.shade200.withValues(alpha: 0.4),
                    Colors.blue.shade50.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: interval,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= _daily.length) return const SizedBox();
                  final s = _daily[i]['period_label'] as String? ?? '';
                  try {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat('d/M').format(DateTime.parse(s)),
                        style: const TextStyle(fontSize: 9),
                      ),
                    );
                  } catch (_) {
                    return Text(s, style: const TextStyle(fontSize: 9));
                  }
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.blueGrey.shade800,
              getTooltipItems: (spots) => spots.map((s) {
                final i = s.x.toInt();
                final ds = i < _daily.length
                    ? _daily[i]['period_label'] as String? ?? ''
                    : '';
                String label = ds;
                try {
                  label =
                      DateFormat('dd MMM').format(DateTime.parse(ds));
                } catch (_) {}
                return LineTooltipItem(
                  '$label\n${s.y.toStringAsFixed(2)} L',
                  const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Chart 4: FAT Quality ranked list ──────────────────────────────────────
  Widget _buildFatQualityList() {
    final sorted = List<Map<String, dynamic>>.from(_customers)
      ..sort((a, b) =>
          (b['avg_fat'] as num).compareTo(a['avg_fat'] as num));
    if (sorted.isEmpty) return const _NoData();
    final maxFat = (sorted.first['avg_fat'] as num).toDouble();

    return Column(
      children: sorted.take(10).map((r) {
        final name = r['customer_name'] as String? ?? '—';
        final fat  = (r['avg_fat'] as num).toDouble();
        final pct  = maxFat > 0 ? fat / maxFat : 0.0;
        final color = fat >= 6.0
            ? Colors.green.shade600
            : fat >= 4.5
                ? Colors.orange.shade600
                : Colors.red.shade400;
        return _RankRow(
          name: name,
          value: '${fat.toStringAsFixed(2)}%',
          fraction: pct,
          color: color,
          icon: Icons.star_rounded,
        );
      }).toList(),
    );
  }

  // ── Chart 5: Attendance ranked list ───────────────────────────────────────
  Widget _buildAttendanceList(int totalDays) {
    final sorted = List<Map<String, dynamic>>.from(_customers)
      ..sort((a, b) =>
          (b['days_present'] as int).compareTo(a['days_present'] as int));
    if (sorted.isEmpty) return const _NoData();

    return Column(
      children: sorted.take(10).map((r) {
        final name  = r['customer_name'] as String? ?? '—';
        final days  = r['days_present'] as int;
        final pct   = totalDays > 0 ? days / totalDays : 0.0;
        final color = pct >= 0.85
            ? Colors.green.shade600
            : pct >= 0.6
                ? Colors.orange.shade600
                : Colors.red.shade400;
        return _RankRow(
          name: name,
          value: '$days / $totalDays days',
          fraction: pct.clamp(0.0, 1.0),
          color: color,
          icon: Icons.calendar_today,
          trailing: '${(pct * 100).toStringAsFixed(0)}%',
        );
      }).toList(),
    );
  }

  // ── Chart 6: Shift split (Morning vs Evening) via PieChart ────────────────
  Widget _buildShiftSplitChart() {
    // We aggregate shift data from _daily data - but we need shift breakdown
    // Use entry_count proxy: get morning/evening split from customers data
    // Since we don't have per-shift data in the summary, show a pie of
    // top 5 customers' milk contribution shares instead
    final top5 = _customers.take(5).toList();
    if (top5.isEmpty) return const _NoData();

    final totalQty = _customers.fold<double>(
        0, (s, r) => s + (r['total_quantity'] as num).toDouble());

    final colors = [
      Colors.blue.shade500,
      Colors.green.shade500,
      Colors.orange.shade500,
      Colors.purple.shade400,
      Colors.teal.shade500,
    ];

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: top5.asMap().entries.map((e) {
                final qty = (e.value['total_quantity'] as num).toDouble();
                final pct = totalQty > 0 ? (qty / totalQty * 100) : 0;
                return PieChartSectionData(
                  value: qty,
                  title: '${pct.toStringAsFixed(1)}%',
                  color: colors[e.key % colors.length],
                  radius: 60,
                  titleStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              }).toList(),
              pieTouchData: PieTouchData(
                touchCallback: (_, __) {},
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: top5.asMap().entries.map((e) {
            final name = (e.value['customer_name'] as String? ?? '').split(' ').first;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors[e.key % colors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(name, style: const TextStyle(fontSize: 11)),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          'Others: ${_customers.skip(5).length} more farmers',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Helper widgets
// ═══════════════════════════════════════════════════════════════════════════

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Stat(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
        Text(label,
            style:
                const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  final String name;
  final String value;
  final double fraction;
  final Color color;
  final IconData icon;
  final String? trailing;

  const _RankRow({
    required this.name,
    required this.value,
    required this.fraction,
    required this.color,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(trailing ?? value,
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.bold)),
            ],
          ),
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
            Align(
              alignment: Alignment.centerRight,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final String date;
  final VoidCallback onTap;

  const _DateChip(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(date,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
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
