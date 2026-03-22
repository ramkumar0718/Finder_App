import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../profile_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final ApiService _apiService = ApiService();
  String _selectedFilter = 'Week';
  bool _isLoading = true;
  Map<String, dynamic>? _analyticsData;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final data = await _apiService.getAdminAnalytics(_selectedFilter);
      if (mounted) {
        setState(() {
          _analyticsData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading analytics: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error logging out: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Dashboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
              child: const CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Colors.blueAccent, size: 20),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _logout(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildHeader(),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_analyticsData == null)
                      const Center(child: Text('No data available'))
                    else ...[
                      _buildSummaryCards(),
                      const SizedBox(height: 24),
                      _buildBarChartCard(),
                      const SizedBox(height: 12),
                      _buildPieChartCard(),
                      const SizedBox(height: 12),
                      _buildCategoriesCard(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Analytics Report',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedFilter,
              items:
                  ['Week', 'Month', 'Year', 'All'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value, style: const TextStyle(fontSize: 16)),
                    );
                  }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() => _selectedFilter = newValue);
                  _fetchAnalytics();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    final summary = _analyticsData!['summary'];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),

      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatValue(summary['total_found'].toString(), Colors.green),
              _buildStatValue(summary['total_lost'].toString(), Colors.red),
              _buildStatValue(
                summary['total_resolved'].toString(),
                Colors.black,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatLabel('Found\nItems'),
              _buildStatLabel('Lost\nItems'),
              _buildStatLabel('Resolved\nStats'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatValue(String value, Color color) {
    return Expanded(
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 33,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStatLabel(String label) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.2),
      ),
    );
  }

  Widget _buildBarChartCard() {
    final comparisonData = _analyticsData!['comparison'] as List<dynamic>;

    double maxVal = 0;
    for (var item in comparisonData) {
      if (item['lost_count'] > maxVal) maxVal = item['lost_count'].toDouble();
      if (item['resolved_count'] > maxVal) {
        maxVal = item['resolved_count'].toDouble();
      }
    }

    double maxY = ((maxVal / 10).ceil() * 10).toDouble();
    if (maxY == 0) maxY = 50;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status Comparison',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildLegendItem('Lost', const Color(0xFF487CCB)),
                const SizedBox(width: 16),
                _buildLegendItem('Resolved', const Color(0xFF6AAF98)),
              ],
            ),
            const SizedBox(height: 30),
            if (comparisonData.isEmpty)
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'No comparison data available',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width:
                        comparisonData.length * 60.0 > 300
                            ? comparisonData.length * 60.0
                            : 300,
                    child: BarChart(
                      BarChartData(
                        minY: 0,
                        maxY: maxY,
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                int index = value.toInt();
                                if (index < 0 ||
                                    index >= comparisonData.length) {
                                  return const Text('');
                                }
                                String label = _getPeriodLabel(
                                  comparisonData[index]['period'],
                                  _selectedFilter,
                                  index,
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  _formatYAxisLabel(value),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey[600],
                                  ),
                                );
                              },
                              interval: maxY / 5,
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          checkToShowHorizontalLine: (value) => true,
                          horizontalInterval: maxY / 5,
                          getDrawingHorizontalLine:
                              (value) => FlLine(
                                color: Colors.grey[300]!,
                                strokeWidth: 1,
                              ),
                        ),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: 0,
                              color: Colors.grey[300]!,
                              strokeWidth: 1,
                            ),
                            HorizontalLine(
                              y: maxY,
                              color: Colors.grey[300]!,
                              strokeWidth: 1,
                            ),
                          ],
                        ),
                        barGroups: List.generate(comparisonData.length, (i) {
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: comparisonData[i]['lost_count'].toDouble(),
                                color: const Color(0xFF487CCB),
                                width: 23,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                              BarChartRodData(
                                toY:
                                    comparisonData[i]['resolved_count']
                                        .toDouble(),
                                color: const Color(0xFF6AAF98),
                                width: 23,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ],
                            barsSpace: 4,
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getPeriodLabel(dynamic period, String filter, int index) {
    if (filter == 'All') return 'AllTime';
    if (period == null) return '';

    try {
      if (filter == 'Week') {
        return 'Week ${index + 1}';
      }
      DateTime date = DateTime.parse(period.toString());
      if (filter == 'Month') {
        return DateFormat('MMM').format(date);
      }
      if (filter == 'Year') {
        return date.year.toString();
      }
    } catch (e) {
      return period.toString();
    }
    return '';
  }

  String _formatYAxisLabel(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toInt().toString();
  }

  Widget _buildPieChartCard() {
    final summary = _analyticsData!['summary'];
    double total = (summary['total_found'] + summary['total_lost']).toDouble();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Total Items',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Found', const Color(0xFF264752)),
                const SizedBox(width: 24),
                _buildLegendItem('Lost', const Color(0xFFE7C06E)),
              ],
            ),

            SizedBox(
              height: 170,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 40,
                  sections:
                      total == 0
                          ? [
                            PieChartSectionData(
                              value: 1,
                              color: Colors.grey[300],
                              title: '',
                              radius: 25,
                              titleStyle: const TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
                              ),
                            ),
                          ]
                          : [
                            PieChartSectionData(
                              value: summary['total_found'].toDouble(),
                              color: const Color(0xFF264752),
                              title: '',
                              radius: 25,
                            ),
                            PieChartSectionData(
                              value: summary['total_lost'].toDouble(),
                              color: const Color(0xFFE7C06E),
                              title: '',
                              radius: 25,
                            ),
                          ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, {String? value}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        if (value != null) ...[
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoriesCard() {
    final categories = _analyticsData!['categories'] as List<dynamic>;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Categories',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (categories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Center(
                  child: Text(
                    'No category data available',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ),
              )
            else
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(4),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    children: [
                      _buildTableCell('Category', isHeader: true),
                      _buildTableCell(
                        'Found',
                        isHeader: true,
                        align: TextAlign.center,
                      ),
                      _buildTableCell(
                        'Lost',
                        isHeader: true,
                        align: TextAlign.right,
                      ),
                    ],
                  ),
                  ...categories.map((cat) {
                    return TableRow(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey[100]!),
                        ),
                      ),
                      children: [
                        _buildTableCell(cat['category']),
                        _buildTableCell(
                          '${cat['found_pct']} %',
                          align: TextAlign.center,
                        ),
                        _buildTableCell(
                          '${cat['lost_pct']} %',
                          align: TextAlign.right,
                        ),
                      ],
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    TextAlign align = TextAlign.left,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: isHeader ? 16 : 14,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? Colors.black87 : Colors.grey[700],
        ),
      ),
    );
  }
}
