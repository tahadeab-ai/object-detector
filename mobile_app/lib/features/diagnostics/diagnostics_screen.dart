import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/diagnostics_service.dart';

class DiagnosticsScreen extends StatefulWidget {
  final bool isArabic;

  const DiagnosticsScreen({super.key, this.isArabic = false});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final DiagnosticsService _diagService = DiagnosticsService();

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isArabic
              ? 'تم نسخ بيانات التشخيص إلى الحافظة'
              : 'Diagnostics copied to clipboard',
        ),
        backgroundColor: Colors.cyanAccent.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DiagnosticsData>(
      valueListenable: _diagService.dataNotifier,
      builder: (context, data, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0D0D12),
          appBar: AppBar(
            backgroundColor: const Color(0xFF16161F),
            title: Text(
              widget.isArabic
                  ? 'تشخيص محرك الاستدلال (Diagnostics)'
                  : 'Engine Diagnostics',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.cyanAccent),
                tooltip: widget.isArabic ? 'نسخ التقرير' : 'Copy Diagnostics',
                onPressed: () =>
                    _copyToClipboard(context, data.toFormattedString()),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Engine Initialization Card
              _buildSectionCard(
                title: widget.isArabic ? 'حالة المحرك' : 'Engine Status',
                icon: data.isEngineInitialized
                    ? Icons.check_circle_rounded
                    : Icons.error_rounded,
                iconColor: data.isEngineInitialized
                    ? Colors.greenAccent
                    : Colors.redAccent,
                children: [
                  _buildRow(
                    widget.isArabic ? 'التهيئة' : 'Initialized',
                    data.isEngineInitialized ? 'YES' : 'NO',
                    color: data.isEngineInitialized
                        ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                  _buildRow(
                    widget.isArabic ? 'رمز الاستجابة' : 'Return Code',
                    '${data.engineInitReturnCode}',
                  ),
                  _buildRow(
                    widget.isArabic ? 'طبقة الإدخال' : 'Input Blob',
                    data.inBlobName,
                  ),
                  _buildRow(
                    widget.isArabic ? 'طبقة الإخراج' : 'Output Blob',
                    data.outBlobName,
                  ),
                  _buildRow(
                    widget.isArabic ? 'المعالج الفعال' : 'Active Backend',
                    data.activeBackend == 1
                        ? 'Vulkan GPU (1)'
                        : 'ARM NEON CPU (0)',
                    color: data.activeBackend == 1
                        ? Colors.amberAccent
                        : Colors.cyanAccent,
                  ),
                  _buildRow(
                    widget.isArabic ? 'دعم Vulkan' : 'Vulkan Available',
                    data.isVulkanAvailable ? 'TRUE' : 'FALSE',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Stream & Watchdog Metrics Card
              _buildSectionCard(
                title: widget.isArabic
                    ? 'إحصائيات التدفق وحارس الكاميرا'
                    : 'Stream & Watchdog Metrics',
                icon: Icons.speed_rounded,
                iconColor: Colors.cyanAccent,
                children: [
                  _buildRow(
                    widget.isArabic ? 'الإطارات المستلمة' : 'Frames Received',
                    '${data.framesReceived}',
                  ),
                  _buildRow(
                    widget.isArabic ? 'الإطارات المعالجة' : 'Frames Processed',
                    '${data.framesProcessed}',
                  ),
                  _buildRow(
                    widget.isArabic ? 'الإطارات المسقطة' : 'Frames Dropped',
                    '${data.framesDropped}',
                  ),
                  _buildRow(
                    widget.isArabic ? 'آخر إطار' : 'Last Frame',
                    data.lastFrameTime != null
                        ? data.lastFrameTime!.toIso8601String().substring(11, 19)
                        : 'None',
                  ),
                  _buildRow(
                    widget.isArabic ? 'آخر خطأ' : 'Last Error',
                    data.lastError,
                    color: data.lastError == 'None'
                        ? Colors.white70
                        : Colors.amberAccent,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Extracted Model Assets & Hashes
              _buildSectionCard(
                title: widget.isArabic
                    ? 'ملفات النموذج والتوقيع الرقمي'
                    : 'Extracted Model Assets & SHA256',
                icon: Icons.fingerprint_rounded,
                iconColor: Colors.purpleAccent,
                children: [
                  _buildHashBlock(
                    label: 'Param File Path',
                    value: data.paramPath.isEmpty ? 'N/A' : data.paramPath,
                  ),
                  _buildHashBlock(
                    label: 'Param SHA256',
                    value:
                        data.paramSha256.isEmpty ? 'N/A' : data.paramSha256,
                  ),
                  const Divider(color: Colors.white12),
                  _buildHashBlock(
                    label: 'Bin File Path',
                    value: data.binPath.isEmpty ? 'N/A' : data.binPath,
                  ),
                  _buildHashBlock(
                    label: 'Bin SHA256',
                    value: data.binSha256.isEmpty ? 'N/A' : data.binSha256,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Action button: Copy diagnostics
              ElevatedButton.icon(
                onPressed: () =>
                    _copyToClipboard(context, data.toFormattedString()),
                icon: const Icon(Icons.copy_all_rounded),
                label: Text(
                  widget.isArabic
                      ? 'نسخ كامل تقرير التشخيص'
                      : 'Copy Full Diagnostics Report',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: color ?? Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHashBlock({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
