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

  Map<String, double> get _expenseByMonth {
    final Map<String, double> data = {};
    for (var t in _transactions) {
      if (t['type'] == 'expense') {
        final raw = (t['transaction_date'] ?? t['date'] ?? '').toString();
        if (raw.length >= 7) {
          final monthKey = raw.substring(0, 7);
          final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
          data[monthKey] = (data[monthKey] ?? 0) + amt;
        }
      }
    }
    return Map.fromEntries(data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
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

                        // 6. Bar Chart Pengeluaran per Bulan (Aman dari crash)
                        const Text('Tren Pengeluaran per Bulan',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        _expenseByMonth.isEmpty
                            ? Center(child: Text('Belum ada data bulanan', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))))
                            : SizedBox(
                                height: 220,
                                child: BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.spaceAround,
                                    maxY: () {
                                      final maxVal = _expenseByMonth.values.reduce((a, b) => a > b ? a : b);
                                      return maxVal > 0 ? maxVal * 1.25 : 100000.0;
                                    }(),
                                    barTouchData: BarTouchData(
                                      enabled: true,
                                      touchTooltipData: BarTouchTooltipData(
                                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                          final keys = _expenseByMonth.keys.toList();
                                          final month = groupIndex < keys.length ? keys[groupIndex] : '';
                                          return BarTooltipItem(
                                            '$month\n${_formatCurrency(rod.toY)}',
                                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
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
                                          getTitlesWidget: (value, meta) {
                                            final keys = _expenseByMonth.keys.toList();
                                            final idx = value.toInt();
                                            if (idx < 0 || idx >= keys.length) return const SizedBox.shrink();
                                            final key = keys[idx];
                                            String label = key;
                                            if (key.length >= 7 && key.contains('-')) {
                                              final mInt = int.tryParse(key.substring(5, 7)) ?? 0;
                                              const shortMonths = [
                                                '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
                                                'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
                                              ];
                                              if (mInt >= 1 && mInt <= 12) {
                                                label = shortMonths[mInt];
                                              }
                                            }
                                            return Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: Text(
                                                label,
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    gridData: const FlGridData(show: false),
                                    borderData: FlBorderData(show: false),
                                    barGroups: _expenseByMonth.entries.toList().asMap().entries.map((entry) {
                                      return BarChartGroupData(
                                        x: entry.key,
                                        barRods: [
                                          BarChartRodData(
                                            toY: entry.value.value,
                                            color: const Color(0xFF6C63FF),
                                            width: 18,
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
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