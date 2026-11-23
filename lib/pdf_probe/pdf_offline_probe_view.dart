import 'package:flutter/material.dart';

import 'pdf_probe_models.dart';
import 'pdf_probe_session.dart';

String locateFailureLabel(LocateFailure failure) {
  return switch (failure) {
    LocateFailure.noLines => '没有可定位的行',
    LocateFailure.emptyLineText => '有空行，已失败关闭',
    LocateFailure.invalidPage => '页码无效，已失败关闭',
    LocateFailure.crossPage => '选区跨页，已失败关闭',
    LocateFailure.badBounds => '行框无效，已失败关闭',
    LocateFailure.pageSizeUnavailable => '没有页面尺寸，已失败关闭',
    LocateFailure.boundsOutsidePage => '行框超出页面，已失败关闭',
    LocateFailure.orderAmbiguous => '行序无法证明，已失败关闭',
    LocateFailure.textMismatch => '文本与行不一致，已失败关闭',
    LocateFailure.fileHashMissing => '没有文件身份，已失败关闭',
    LocateFailure.pageIdentityUnproven => '未能确认选区所在页',
  };
}

String restoreVerdictLabel(RestoreVerdict verdict) {
  return switch (verdict) {
    RestoreVerdict.selectionRestored => '原句已恢复',
    RestoreVerdict.unverified => '回位未验证',
    RestoreVerdict.failed => '回位失败',
  };
}

/// Offline probe surface. It is not registered from the shelf, catalog,
/// Finder import, text reader, or scan reader.
class PdfOfflineProbeView extends StatelessWidget {
  const PdfOfflineProbeView({
    super.key,
    required this.session,
    required this.readViewport,
  });

  final PdfProbeSession session;
  final PdfViewport Function() readViewport;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final decision = session.decision;
        final anchor = session.anchor;
        final leave = session.leaveRecord;
        final verdict = session.reopenVerdict;
        return Material(
          color: const Color(0xFFF6F4EE),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(
                key: Key('pdf-probe-page-slot'),
                height: 180,
                child: ColoredBox(color: Color(0xFFE7E1D6)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: DecoratedBox(
                  key: const Key('pdf-probe-card'),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFCF8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x14000000)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('离线占位，未请求模型'),
                        const SizedBox(height: 8),
                        Text(
                          decision is LocateRejected
                              ? locateFailureLabel(decision.failure)
                              : (anchor == null ? '尚未提交锚点' : '锚点已由夹具页证据提交'),
                          key: const Key('pdf-probe-status'),
                        ),
                        if (anchor != null) ...[
                          const SizedBox(height: 8),
                          for (var i = 0; i < anchor.lines.length; i += 1)
                            Text(
                              anchor.lines[i].text,
                              key: Key('pdf-probe-line-$i'),
                            ),
                        ],
                        if (session.annotation != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '内存标注已记录，尚未验证是否压住字形',
                            key: const Key('pdf-probe-annotation'),
                          ),
                        ],
                        if (session.nativeCleared)
                          const Text('已收到无标签清除信号，锚点未因此撤销'),
                        if (leave != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '离开时 zoom ${leave.viewport.zoom} '
                            'x ${leave.viewport.scrollX} '
                            'y ${leave.viewport.scrollY}',
                            key: const Key('pdf-probe-leave-viewport'),
                          ),
                        ],
                        if (verdict != null)
                          Text(
                            restoreVerdictLabel(verdict),
                            key: const Key('pdf-probe-verdict'),
                          ),
                        const SizedBox(height: 8),
                        TextButton(
                          key: const Key('pdf-probe-leave'),
                          onPressed: () => session.leave(readViewport()),
                          child: const Text('记录离开时视野'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
