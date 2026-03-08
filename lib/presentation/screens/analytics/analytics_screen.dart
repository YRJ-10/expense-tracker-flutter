import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _transactions = [];
  int _touchedExpenseIndex = -1;
  int _touchedIncomeIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser!.id;
    final transactions = await _supabase
        .from('transactions')
        .select('*, categories(name, icon, color)')
        .eq('user_id', userId)
        .order('date', ascending: false);

    setState(() {
      _transactions = List<Map<String, dynamic>>.from(transactions);
      _isLoading = false;
    });
  }

  // Bulan ini
  List<Map<String, dynamic>> get _thisMonth {
    final now = DateTime.now();
    return _transactions.where((t) {
      final date = DateTime.parse(t['date']);
      return date.year == now.year && date.month == now.month;
    }).toList();
  }

  // Bulan lalu
  List<Map<String, dynamic>> get _lastMonth {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1);
    return _transactions.where((t) {
      final date = DateTime.parse(t['date']);
      return date.year == last.year && date.month == last.month;
    }).toList();
  }

  double _sumByType(List<Map<String, dynamic>> list, String type) {
    return list.where((t) => t['type'] == type).fold(0.0, (sum, t) => sum + t['amount'].toDouble());
  }

  Map<String, double> _groupByCategory(List<Map<String, dynamic>> list, String type) {
    final Map<String, double> data = {};
    for (var t in list) {
      if (t['type'] == type) {
        final name = t['categories'] != null ? t['categories']['name'] : 'Lainnya';
        data[name] = (data[name] ?? 0) + t['amount'].toDouble();
      }
    }
    return data;
  }

  Map<String, double> get _expenseByMonth {
    final Map<String, double> data = {};
    for (var t in _transactions) {
      if (t['type'] == 'expense') {
        final month = t['date'].toString().substring(0, 7);
        data[month] = (data[month] ?? 0) + t['amount'].toDouble();
      }
    }
    return Map.fromEntries(data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  String _formatCurrency(double amount) {
    return 'Rp ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  String _percentChange(double current, double previous) {
    if (previous == 0) return '+0%';
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
        child: Text('Belum ada data', style: TextStyle(color: Colors.white.withOpacity(0.4))),
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
                  titleStyle: const TextStyle(color: Colors.white, fontSize: 11),
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
                Text(e.key, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final thisIncome = _sumByType(_thisMonth, 'income');
    final thisExpense = _sumByType(_thisMonth, 'expense');
    final lastIncome = _sumByType(_lastMonth, 'income');
    final lastExpense = _sumByType(_lastMonth, 'expense');
    final thisBalance = thisIncome - thisExpense;

    final expenseByCategory = _groupByCategory(_thisMonth, 'expense');
    final incomeByCategory = _groupByCategory(_thisMonth, 'income');

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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : _transactions.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 80, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              'Belum ada data transaksi',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Tambahkan transaksi pertamamu!',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
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

              // 1. Ringkasan Bulan Ini
              const Text('Ringkasan Bulan Ini',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
                    const Text('Selisih Bulan Ini', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text(
                      _formatCurrency(thisBalance),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 2. Perbandingan Bulan Ini vs Bulan Lalu
              const Text('Bulan Ini vs Bulan Lalu',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _compareCard('Pemasukan', thisIncome, lastIncome, Colors.greenAccent)),
                  const SizedBox(width: 12),
                  Expanded(child: _compareCard('Pengeluaran', thisExpense, lastExpense, Colors.redAccent)),
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
                        color: const Color(0xFF6C63FF).withOpacity(0.2),
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
                          Text('Kategori terbanyak bulan ini',
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
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

              // 6. Bar Chart Pengeluaran per Bulan
              const Text('Pengeluaran per Bulan',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _expenseByMonth.isEmpty
                  ? Center(child: Text('Belum ada data', style: TextStyle(color: Colors.white.withOpacity(0.4))))
                  : SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: _expenseByMonth.values.reduce((a, b) => a > b ? a : b) * 1.2,
                    barTouchData: BarTouchData(enabled: true),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final keys = _expenseByMonth.keys.toList();
                            if (value.toInt() >= keys.length) return const Text('');
                            final month = keys[value.toInt()].substring(5);
                            return Text(month,
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11));
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
                            width: 20,
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
              Text(title, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_formatCurrency(amount),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _compareCard(String title, double current, double previous, Color color) {
    final percent = _percentChange(current, previous);
    final isUp = current >= previous;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          const SizedBox(height: 8),
          Text(_formatCurrency(current),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isUp ? Colors.redAccent : Colors.greenAccent, size: 14),
              Text(percent,
                  style: TextStyle(
                      color: isUp ? Colors.redAccent : Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          Text('vs bulan lalu', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
        ],
      ),
    );
  }
}