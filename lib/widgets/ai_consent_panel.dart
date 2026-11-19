import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/companion/lingfer_theme.dart';
import '../services/ai_consent_store.dart';

final ValueNotifier<int> _aiConsentChanges = ValueNotifier<int>(0);

Future<void> showAiConsentPanel(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: LingferColors.paper,
      builder: (_) => const AiConsentPanel(),
    );

class AiConsentPanel extends StatefulWidget {
  const AiConsentPanel({super.key});
  @override
  State<AiConsentPanel> createState() => _AiConsentPanelState();
}

class _AiConsentPanelState extends State<AiConsentPanel> {
  bool saving = false;
  String? error;
  Future<void> choose(bool allowed) async {
    setState(() {
      saving = true;
      error = null;
    });
    final state = await AiConsentStore.setAllowed(allowed);
    if (!mounted) return;
    if (!state.decided || state.allowed != allowed) {
      setState(() {
        saving = false;
        error = '选择暂未保存，请重试或在设置中核对状态。';
      });
      return;
    }
    _aiConsentChanges.value++;
    Navigator.pop(context);
  }

  Future<void> policy() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(AiConsentStore.policyUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened && mounted)
      setState(
        () => error =
            '暂时无法打开政策页面。你可以先选择仅本机阅读；联系邮箱：${AiConsentStore.contactEmail}。',
      );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .86,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('使用联网 AI', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            const Text(
              AiConsentStore.disclosure,
              style: TextStyle(height: 1.65),
            ),
            const SizedBox(height: 16),
            const Text(
              '本机记录与隐私',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '资料、收藏原句、熟词、复习进度、最近阅读原文及部分译文缓存可保存在这台设备；分享扩展通过本机 App Group 共享必要状态。当前没有账号云同步。移除应用内资料不会同时删除你另行导出的备份。',
              style: TextStyle(height: 1.6),
            ),
            TextButton(
              onPressed: policy,
              key: const ValueKey('ai-consent-policy'),
              child: const Text('打开隐私政策'),
            ),
            const Text(
              '联系邮箱：${AiConsentStore.contactEmail}',
              style: TextStyle(fontSize: 12, color: LingferColors.muted),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: const TextStyle(color: LingferColors.warning),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : () => choose(true),
              key: const ValueKey('ai-consent-allow'),
              child: const Text('允许联网 AI'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: saving ? null : () => choose(false),
              key: const ValueKey('ai-consent-local'),
              child: const Text('仅本机阅读／关闭联网 AI'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// First use stays readable without a forced consent dialog. Settings always
/// retain this entry, including after the user allows or withdraws permission.
class AiConsentEntry extends StatefulWidget {
  const AiConsentEntry({super.key, this.firstUseOnly = false});
  final bool firstUseOnly;
  @override
  State<AiConsentEntry> createState() => _AiConsentEntryState();
}

class _AiConsentEntryState extends State<AiConsentEntry>
    with WidgetsBindingObserver {
  late Future<AiConsentState> state;
  @override
  void initState() {
    super.initState();
    state = AiConsentStore.read();
    WidgetsBinding.instance.addObserver(this);
    _aiConsentChanges.addListener(refresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _aiConsentChanges.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (!mounted) return;
    final pending = AiConsentStore.read();
    setState(() {
      state = pending;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) refresh();
  }

  Future<void> open() async {
    await showAiConsentPanel(context);
    refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AiConsentState>(
    future: state,
    builder: (context, snapshot) {
      final consent = snapshot.data ?? const AiConsentState();
      if (widget.firstUseOnly && (!snapshot.hasData || consent.decided))
        return const SizedBox.shrink();
      return ListTile(
        key: const ValueKey('ai-consent-entry'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.privacy_tip_outlined),
        title: Text(widget.firstUseOnly ? '联网 AI 尚未开启' : '联网 AI 与隐私'),
        subtitle: Text(
          consent.allowed
              ? '已允许 · 可查看说明或关闭'
              : consent.decided
              ? '仅本机阅读 · 联网 AI 已关闭，可重新选择'
              : '腾讯云中转与 DeepSeek · 查看并选择；仅本机阅读可用',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: open,
      );
    },
  );
}
