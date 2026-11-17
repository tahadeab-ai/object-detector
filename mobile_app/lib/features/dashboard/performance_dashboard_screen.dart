import 'package:flutter/material.dart';
import '../../core/models/engine_telemetry.dart';
import '../../core/services/detection_event_bus.dart';
import '../../core/services/model_manager.dart';
import '../../core/theme/design_tokens.dart';

class PerformanceDashboardScreen extends StatefulWidget {
  final bool isArabic;

  const PerformanceDashboardScreen({super.key, required this.isArabic});

  @override
  State<PerformanceDashboardScreen> createState() =>
      _PerformanceDashboardScreenState();
}

class _PerformanceDashboardScreenState
    extends State<PerformanceDashboardScreen> {
  EngineTelemetry _telemetry = const EngineTelemetry();
  final List<double> _latencyHistory = [];
  static const int _maxHistory = 30;

  @override
  void initState() {
    super.initState();
    DetectionEventBus().stream.listen((event) {
      if (!mounted) return;
      setState(() {
        _telemetry = event.telemetry;
        _latencyHistory.add(event.telemetry.inferenceTimeMs);
        if (_latencyHistory.length > _maxHistory) {
          _latencyHistory.removeAt(0);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final modelMgr = ModelManager();
    final profile = modelMgr.activeProfile;
    final isAr = widget.isArabic;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppTokens.bg,
        appBar: AppBar(
          backgroundColor: AppTokens.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTokens.text),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            isAr ? 'لوحة قياس الأداء المباشر' : 'Performance Dashboard',
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              color: AppTokens.text,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTokens.surfaceGlass,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTokens.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, size: 8, color: AppTokens.ok),
                  const SizedBox(width: 6),
                  Text(
                    isAr ? 'متصل' : 'LIVE',
                    style: const TextStyle(
                      fontFamily: AppTokens.fontCairo,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTokens.ok,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Primary Metrics Grid (FPS, Latency, Dropped, Backend)
            _buildMetricsGrid(isAr),
            const SizedBox(height: 16),

            // 2. Real-Time Latency Waveform
            _buildLatencyChartCard(isAr),
            const SizedBox(height: 16),

            // 3. Pipeline Latency Breakdown
            _buildPipelineBreakdownCard(isAr),
            const SizedBox(height: 16),

            // 4. Active Model & Runtime Configuration
            _buildModelConfigCard(profile, modelMgr, isAr),
            const SizedBox(height: 16),

            // 5. Hardware Specifications & Thermal Status
            _buildHardwareSpecsCard(isAr),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid(bool isAr) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMetricTile(
          title: isAr ? 'معدل الإطارات (FPS)' : 'Inference Rate (FPS)',
          value: _telemetry.fps.toStringAsFixed(1),
          subtitle: isAr ? 'المستهدف: 30-60' : 'Target: 30-60 FPS',
          icon: Icons.speed_rounded,
          color: _telemetry.fps >= 25 ? AppTokens.ok : AppTokens.warn,
        ),
        _buildMetricTile(
          title: isAr ? 'زمن الاستدلال الكلي' : 'Total Latency',
          value: '${_telemetry.totalLatencyMs.toStringAsFixed(1)} ms',
          subtitle: isAr ? 'معالجة + استدلال + تعقب' : 'Prep + Infer + Post',
          icon: Icons.timer_outlined,
          color: _telemetry.totalLatencyMs <= 35 ? AppTokens.accent : AppTokens.warn,
        ),
        _buildMetricTile(
          title: isAr ? 'المسارات النشطة' : 'Active Tracks',
          value: '${_telemetry.activeTracks}',
          subtitle: isAr
              ? '${_telemetry.confirmedTracks} مؤكد'
              : '${_telemetry.confirmedTracks} Confirmed',
          icon: Icons.radar_rounded,
          color: AppTokens.catVehicle,
        ),
        _buildMetricTile(
          title: isAr ? 'محرك التنفيذ' : 'Execution Backend',
          value: _getBackendLabel(_telemetry.activeBackend, isAr),
          subtitle: 'Snapdragon 855',
          icon: Icons.memory_rounded,
          color: AppTokens.catElectronics,
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTokens.fontCairo,
                    fontSize: 11,
                    color: AppTokens.muted,
                  ),
                ),
              ),
              Icon(icon, size: 16, color: color),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTokens.fontCairo,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              fontSize: 10,
              color: AppTokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyChartCard(bool isAr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isAr ? 'مخطط زمن الاستدلال (آخر 30 إطار)' : 'Inference Latency Timeline (Last 30 Frames)',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTokens.text,
                ),
              ),
              Text(
                '${_telemetry.inferenceTimeMs.toStringAsFixed(1)} ms',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_maxHistory, (index) {
                final val = index < _latencyHistory.length ? _latencyHistory[index] : 0.0;
                final heightFrac = (val / 60.0).clamp(0.05, 1.0);
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    height: 60 * heightFrac,
                    decoration: BoxDecoration(
                      color: val <= 25
                          ? AppTokens.ok
                          : (val <= 45 ? AppTokens.accent : AppTokens.warn),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineBreakdownCard(bool isAr) {
    final inferMs = _telemetry.inferenceTimeMs;
    final trackerMs = _telemetry.trackerTimeMs;
    final total = inferMs + trackerMs > 0 ? (inferMs + trackerMs) : 1.0;
    final inferFrac = (inferMs / total).clamp(0.0, 1.0);
    final trackerFrac = (trackerMs / total).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isAr ? 'توزيع زمن خط الأنابيب' : 'Pipeline Execution Breakdown',
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTokens.text,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: (inferFrac * 100).toInt(),
                    child: Container(color: AppTokens.accent),
                  ),
                  Expanded(
                    flex: (trackerFrac * 100).toInt().clamp(1, 100),
                    child: Container(color: AppTokens.catIndoor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLegendItem(
                color: AppTokens.accent,
                label: isAr ? 'استدلال NCNN' : 'NCNN Inference',
                value: '${inferMs.toStringAsFixed(1)} ms',
              ),
              _buildLegendItem(
                color: AppTokens.catIndoor,
                label: isAr ? 'تعقب وفك ترميز Rust' : 'Rust Decoder & Tracker',
                value: '${trackerMs.toStringAsFixed(1)} ms',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: AppTokens.fontCairo,
            fontSize: 11,
            color: AppTokens.muted,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppTokens.fontCairo,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppTokens.text,
          ),
        ),
      ],
    );
  }

  Widget _buildModelConfigCard(dynamic profile, ModelManager modelMgr, bool isAr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isAr ? 'النموذج النشط والإعدادات' : 'Active Model & Configuration',
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTokens.text,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            isAr ? 'اسم النموذج' : 'Model Name',
            isAr ? profile.nameAr : profile.nameEn,
          ),
          _buildInfoRow(
            isAr ? 'المهمة البصرية' : 'Vision Task',
            isAr ? profile.task.labelAr : profile.task.labelEn,
          ),
          _buildInfoRow(
            isAr ? 'دقة الإدخال' : 'Input Resolution',
            '${modelMgr.activeResolution}x${modelMgr.activeResolution}',
          ),
          _buildInfoRow(
            isAr ? 'عدد الأصناف' : 'Classes',
            '${profile.classesCount}',
          ),
          _buildInfoRow(
            isAr ? 'الصيغة والحجم' : 'Format & Size',
            'NCNN FP16 (~5.2 MB)',
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareSpecsCard(bool isAr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isAr ? 'مواصفات العتاد (المعدة المستهدفة)' : 'Target Hardware Specifications',
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTokens.text,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Device', 'Samsung Galaxy Note 10 (SM-N970U)'),
          _buildInfoRow('Chipset', 'Qualcomm Snapdragon 855 (SM8150)'),
          _buildInfoRow('CPU Architecture', '8-Core Kryo 485 (1+3+4) arm64-v8a'),
          _buildInfoRow('Vector Extensions', 'ARM NEON + FP16 SIMD (4 Threads)'),
          _buildInfoRow('GPU Acceleration', 'Adreno 640 @ 585 MHz (Vulkan 1.1)'),
          _buildInfoRow('Open-Source Driver', 'Mesa Turnip Driver (Optional)'),
          _buildInfoRow('Camera Pipeline', 'Android NDK YUV420 → NCNN Subsampled'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              fontSize: 11,
              color: AppTokens.muted,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTokens.text,
            ),
          ),
        ],
      ),
    );
  }

  String _getBackendLabel(int backend, bool isAr) {
    switch (backend) {
      case 1:
        return 'Vulkan GPU';
      case 2:
        return 'Mesa Turnip';
      default:
        return isAr ? 'معالج CPU (4T NEON)' : 'CPU NEON (4 Threads)';
    }
  }
}
