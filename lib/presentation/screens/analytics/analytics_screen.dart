import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:expense_tracker_flutter/data/services/firestore_service.dart';
import 'package:expense_tracker_flutter/utils/export_helper.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _transactions = [];
  int _touchedExpenseIndex = -1;
  int _touchedIncomeIndex = -1;

  // Navigasi bulan yang dipilih (default: bulan & tahun sekarang)
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = FirestoreService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final transactions = await FirestoreService.getTransactions(userId);
      if (mounted) {
        setState(() {
          _transactions = transactions;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      _touchedExpenseIndex = -1;
      _touchedIncomeIndex = -1;
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      _touchedExpenseIndex = -1;
      _touchedIncomeIndex = -1;
    });
  }

  // Transaksi bulan yang dipilih
  List<Map<String, dynamic>> get _currentMonthTransactions {
    return _transactions.where((t) {
      final raw = t['transaction_date'] ?? t['date'];
      if (raw == null) return false;
      final date = DateTime.tryParse(raw.toString());
      if (date == null) return false;
      return date.year == _selectedMonth.year && date.month == _selectedMonth.month;
    }).toList();
  }

  // Transaksi 1 bulan sebelum bulan yang dipilih
  List<Map<String, dynamic>> get _previousMonthTransactions {
    final prev = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    return _transactions.where((t) {
      final raw = t['transaction_date'] ?? t['date'];
      if (raw == null) return false;
      final date = DateTime.tryParse(raw.toString());
      if (date == null) return false;
      return date.year == prev.year && date.month == prev.month;
    }).toList();
  }

  double _sumByType(List<Map<String, dynamic>> list, String type) {
    return list
        .where((t) => t['type'] == type)
        .fold(0.0, (sum, t) => sum + ((t['amount'] as num?)?.toDouble() ?? 0.0));
  }

  Map<String, double> _groupByCategory(List<Map<String, dynamic>> list, String type) {
    final Map<String, double> data = {};
    for (var t in list) {
      if (t['type'] == type) {
        final name = t['category'] ?? (t['categories'] != null ? t['categories']['name'] : 'Lainnya');
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        data[name] = (data[name] ?? 0) + amt;
      }
    }
    return data;
  }

  List<Map<String, dynamic>> get _dailyCashflowForSelectedMonth {
    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final List<Map<String, dynamic>> dailyList = List.generate(daysInMonth, (index) {
      final day = index + 1;
      return {
        'day': day,
        'income': 0.0,
        'expense': 0.0,
      };
    });

    for (var t in _currentMonthTransactions) {
      final raw = t['transaction_date'] ?? t['date'];
      if (raw == null) continue;
      final date = DateTime.tryParse(raw.toString());
      if (date != null && date.year == _selectedMonth.year && date.month == _selectedMonth.month) {
        final day = date.day;
        if (day >= 1 && day <= daysInMonth) {
          final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
          if (t['type'] == 'income') {
            dailyList[day - 1]['income'] = (dailyList[day - 1]['income'] as double) + amt;
          } else if (t['type'] == 'expense') {
            dailyList[day - 1]['expense'] = (dailyList[day - 1]['expense'] as double) + amt;
          }
        }
      }
    }

    return dailyList;
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
        ),
      ],
    );
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  String _percentChange(double current, double previous) {
    if (previous == 0) {
      if (current == 0) return '0%';
      return '+100%';
    }
    final change = ((current - previous) / previous * 100);
    return '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%';
  }

  final List<Color> _chartColors = [
    const Color(0xFF6C63FF),
    const Color(0xFFFF6584),
    const Color(0xFF4ECDC4),
    const Color(0xFFFFE66D),
    const Color(0xFF96CEB4),
    const Color(0xFFFF8B94),
    const Color(0xFF45B7D1),
    const Color(0xFFA8E6CF),
  ];

  Widget _buildPieChart(Map<String, double> data, int touchedIndex, Function(int) onTouch) {
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text('Belum ada data di bulan ini', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions || response == null || response.touchedSection == null) {
                    onTouch(-1);
                    return;
                  }
                  onTouch(response.touchedSection!.touchedSectionIndex);
                },
              ),
              sections: data.entries.toList().asMap().entries.map((entry) {
                final index = entry.key;
                final e = entry.value;
                final isTouched = index == touchedIndex;
                return PieChartSectionData(
                  color: _chartColors[index % _chartColors.length],
                  value: e.value,
                  title: isTouched ? _formatCurrency(e.value) : '',
                  radius: isTouched ? 70 : 55,
                  titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                );
              }).toList(),
              centerSpaceRadius: 45,
              sectionsSpace: 3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: data.entries.toList().asMap().entries.map((entry) {
            final index = entry.key;
            final e = entry.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _chartColors[index % _chartColors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${e.key} (${_formatCurrency(e.value)})',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final isCurrentOrFutureMonth = _selectedMonth.year > now.year ||
        (_selectedMonth.year == now.year && _selectedMonth.month >= now.month);

    final monthNames = [
      '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    final monthLabel = '${monthNames[_selectedMonth.month]} ${_selectedMonth.year}';

    final thisIncome = _sumByType(_currentMonthTransactions, 'income');
    final thisExpense = _sumByType(_currentMonthTransactions, 'expense');
    final lastIncome = _sumByType(_previousMonthTransactions, 'income');
    final lastExpense = _sumByType(_previousMonthTransactions, 'expense');
    final thisBalance = thisIncome - thisExpense;

    // Hitung rata-rata pengeluaran harian
    final int daysElapsed = isCurrentMonth
        ? now.day
        : DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final double dailyAverageExpense = thisExpense / (daysElapsed > 0 ? daysElapsed : 1);

    final expenseByCategory = _groupByCategory(_currentMonthTransactions, 'expense');
    final incomeByCategory = _groupByCategory(_currentMonthTransactions, 'income');

    // Top kategori pengeluaran
    String topCategory = '-';
    double topAmount = 0;
    expenseByCategory.forEach((key, value) {
      if (value > topAmount) {
        topAmount = value;
        topCategory = key;
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text('Analitik', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
            tooltip: 'Unduh Laporan PDF ($monthLabel)',
            onPressed: () async {
              final toExport = _currentMonthTransactions.isNotEmpty
                  ? _currentMonthTransactions
                  : _transactions;
              if (toExport.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tidak ada data transaksi untuk diekspor.')),
                );
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Menyiapkan Laporan PDF untuk $monthLabel...')),
              );
              await ExportHelper.exportToPDF(toExport);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : _transactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bar_chart, size: 80, color: Colors.white.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada data transaksi',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tambahkan transaksi pertamamu!',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pengatur Periode Bulan
                        Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chevron_left, color: Colors.white),
                                onPressed: _previousMonth,
                                tooltip: 'Bulan Sebelumnya',
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_month, color: Color(0xFF6C63FF), size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    monthLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (isCurrentMonth) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Sekarang', style: TextStyle(color: Color(0xFF6C63FF), fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.chevron_right,
                                  color: isCurrentOrFutureMonth ? Colors.white24 : Colors.white,
                                ),
                                onPressed: isCurrentOrFutureMonth ? null : _nextMonth,
                                tooltip: 'Bulan Berikutnya',
                              ),
                            ],
                          ),
                        ),

                        // 1. Ringkasan Bulan Ini
                        Text('Ringkasan $monthLabel',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _summaryCard('Pemasukan', thisIncome, Colors.greenAccent, Icons.arrow_downward)),
                            const SizedBox(width: 12),
                            Expanded(child: _summaryCard('Pengeluaran', thisExpense, Colors.redAccent, Icons.arrow_upward)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6C63FF), Color(0xFF9C95FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(thisBalance >= 0 ? 'Surplus Bulan Ini' : 'Defisit Bulan Ini',
                                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
                              Text(
                                _formatCurrency(thisBalance),
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Metrik Rata-rata Pengeluaran Harian
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.speed, color: Colors.amberAccent, size: 20),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Rata-rata Pengeluaran / Hari',
                                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text(
                                        isCurrentMonth ? '$daysElapsed hari terhitung' : '$daysElapsed hari total',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                _formatCurrency(dailyAverageExpense),
                                style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // 2. Perbandingan vs Bulan Lalu (Warna sudah diperbaiki!)
                        const Text('Perbandingan vs Bulan Lalu',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _compareCard('Pemasukan', thisIncome, lastIncome, isExpense: false)),
                            const SizedBox(width: 12),
                            Expanded(child: _compareCard('Pengeluaran', thisExpense, lastExpense, isExpense: true)),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // 3. Kategori Terbesar
                        const Text('Pengeluaran Terbesar',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.trending_up, color: Color(0xFF6C63FF)),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(topCategory,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                    Text('Kategori terbanyak $monthLabel',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                                  ],
                                ),
                              ),
                              Text(_formatCurrency(topAmount),
                                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // 4. Pie Chart Pengeluaran per Kategori
                        const Text('Pengeluaran per Kategori',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        _buildPieChart(expenseByCategory, _touchedExpenseIndex,
                            (i) => setState(() => _touchedExpenseIndex = i)),
                        const SizedBox(height: 32),

                        // 5. Pie Chart Pemasukan per Kategori
                        const Text('Pemasukan per Kategori',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        _buildPieChart(incomeByCategory, _touchedIncomeIndex,
                            (i) => setState(() => _touchedIncomeIndex = i)),
                        const SizedBox(height: 32),

                        // 6. Bar Chart Tren Arus Kas Harian (Pemasukan & Pengeluaran)
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            const Text(
                              'Tren Harian per Tanggal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildLegendItem(const Color(0xFF00E676), 'Masuk'),
                                const SizedBox(width: 10),
                                _buildLegendItem(const Color(0xFFFF5252), 'Keluar'),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.swipe, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Geser grafik ke samping untuk melihat seluruh tanggal (1 - ${DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day})',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        () {
                          final dailyData = _dailyCashflowForSelectedMonth;
                          final daysInMonth = dailyData.length;
                          final maxDailyTotal = dailyData
                              .map((e) => (e['income'] as double) + (e['expense'] as double))
                              .fold(0.0, (m, v) => v > m ? v : m);

                          if (maxDailyTotal == 0) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 30),
                                child: Text('Belum ada transaksi di bulan ini',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                              ),
                            );
                          }

                          final maxY = maxDailyTotal * 1.25;
                          final chartWidth = (daysInMonth * 22.0).clamp(MediaQuery.of(context).size.width - 48, 1200.0);

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: chartWidth,
                              height: 230,
                              child: BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceAround,
                                  maxY: maxY,
                                  barTouchData: BarTouchData(
                                    enabled: true,
                                    touchTooltipData: BarTouchTooltipData(
                                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                        final day = group.x;
                                        final item = dailyData.firstWhere(
                                          (e) => e['day'] == day,
                                          orElse: () => {'income': 0.0, 'expense': 0.0},
                                        );
                                        final inc = item['income'] as double;
                                        final exp = item['expense'] as double;

                                        return BarTooltipItem(
                                          'Tgl $day $monthLabel\n',
                                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                          children: [
                                            if (inc > 0)
                                              TextSpan(
                                                text: 'Masuk: ${_formatCurrency(inc)}\n',
                                                style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.w600),
                                              ),
                                            if (exp > 0)
                                              TextSpan(
                                                text: 'Keluar: ${_formatCurrency(exp)}',
                                                style: const TextStyle(color: Color(0xFFFF5252), fontSize: 11, fontWeight: FontWeight.w600),
                                              ),
                                            if (inc == 0 && exp == 0)
                                              const TextSpan(
                                                text: 'Tidak ada transaksi',
                                                style: TextStyle(color: Colors.white54, fontSize: 11),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  titlesData: FlTitlesData(
                                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 24,
                                        getTitlesWidget: (value, meta) {
                                          final day = value.toInt();
                                          if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 6),
                                            child: Text(
                                              '$day',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.6),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  gridData: const FlGridData(show: false),
                                  borderData: FlBorderData(show: false),
                                  barGroups: dailyData.map((item) {
                                    final day = item['day'] as int;
                                    final inc = item['income'] as double;
                                    final exp = item['expense'] as double;
                                    final total = inc + exp;

                                    List<BarChartRodStackItem> stackItems = [];
                                    Color? singleColor;

                                    if (inc > 0 && exp > 0) {
                                      // Stacked: bawah pengeluaran (merah), atas pemasukan (hijau)
                                      stackItems = [
                                        BarChartRodStackItem(0, exp, const Color(0xFFFF5252)),
                                        BarChartRodStackItem(exp, total, const Color(0xFF00E676)),
                                      ];
                                    } else if (exp > 0) {
                                      singleColor = const Color(0xFFFF5252);
                                    } else if (inc > 0) {
                                      singleColor = const Color(0xFF00E676);
                                    }

                                    return BarChartGroupData(
                                      x: day,
                                      barRods: [
                                        BarChartRodData(
                                          toY: total,
                                          color: stackItems.isEmpty ? (singleColor ?? Colors.transparent) : null,
                                          rodStackItems: stackItems,
                                          width: 12,
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          );
                        }(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _summaryCard(String title, double amount, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_formatCurrency(amount),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _compareCard(String title, double current, double previous, {required bool isExpense}) {
    final percent = _percentChange(current, previous);
    final isUp = current >= previous;
    // Logika warna cerdas:
    // Pemasukan naik = Bagus (Hijau). Pemasukan turun = Buruk (Merah).
    // Pengeluaran naik = Boros (Merah). Pengeluaran turun = Hemat (Hijau).
    final bool isGood = isExpense ? !isUp : isUp;
    final Color trendColor = (current == previous)
        ? Colors.white54
        : (isGood ? Colors.greenAccent : Colors.redAccent);
    final IconData trendIcon = isUp ? Icons.arrow_upward : Icons.arrow_downward;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
          const SizedBox(height: 8),
          Text(_formatCurrency(current),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(trendIcon, color: trendColor, size: 14),
              const SizedBox(width: 4),
              Text(
                percent,
                style: TextStyle(color: trendColor, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Text('vs bulan lalu', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
        ],
      ),
    );
  }
}