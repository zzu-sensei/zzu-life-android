import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ai_service.dart';
import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';

/// 弹出自定义 OpenAI 兼容 API 配置面板，保存成功时返回最新 [AiConfig]。
Future<AiConfig?> showAiConfigSheet(
  BuildContext context, {
  AiConfig? initialConfig,
}) {
  return showMiuixSheet<AiConfig>(
    context,
    builder: (sheetContext) => _AiConfigSheetContent(
      initialConfig: initialConfig,
    ),
  );
}

class _AiConfigSheetContent extends StatefulWidget {
  const _AiConfigSheetContent({this.initialConfig});

  final AiConfig? initialConfig;

  @override
  State<_AiConfigSheetContent> createState() => _AiConfigSheetContentState();
}

class _AiConfigSheetContentState extends State<_AiConfigSheetContent> {
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _systemPromptCtrl = TextEditingController();

  bool _loading = true;
  bool _obscureKey = true;
  bool _toolsEnabled = true;
  bool _showAdvanced = false;
  bool _fetchingModels = false;
  bool _testing = false;
  bool _saving = false;
  double _temperature = 0.7;

  String? _testMessage;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialConfig != null) {
      _applyConfig(widget.initialConfig!);
      _loading = false;
    } else {
      _loadFromNative();
    }
  }

  Future<void> _loadFromNative() async {
    try {
      final raw = await NativeApi.call('getAiConfig');
      if (!mounted) return;
      _applyConfig(AiConfig.fromJson(raw));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _applyConfig(AiConfig cfg) {
    _baseUrlCtrl.text = cfg.baseUrl;
    _apiKeyCtrl.text = cfg.apiKey;
    _modelCtrl.text = cfg.model;
    _systemPromptCtrl.text = cfg.systemPrompt;
    _temperature = cfg.temperature.clamp(0.0, 2.0);
    _toolsEnabled = cfg.toolsEnabled;
    if (cfg.systemPrompt.isNotEmpty || (cfg.temperature - 0.7).abs() > 0.05) {
      _showAdvanced = true;
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _systemPromptCtrl.dispose();
    super.dispose();
  }

  AiConfig _draftConfig() {
    return AiConfig(
      baseUrl: _baseUrlCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      systemPrompt: _systemPromptCtrl.text.trim(),
      temperature: _temperature,
      toolsEnabled: _toolsEnabled,
    );
  }

  void _selectPreset(AiProviderPreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      if (preset.baseUrl.isNotEmpty) {
        _baseUrlCtrl.text = preset.baseUrl;
      }
      if (preset.defaultModel.isNotEmpty) {
        _modelCtrl.text = preset.defaultModel;
      }
      _testMessage = null;
    });
  }

  Future<void> _fetchModels() async {
    final draft = _draftConfig();
    if (draft.baseUrl.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testMessage = '请先填写 API Base URL';
      });
      return;
    }
    setState(() {
      _fetchingModels = true;
      _testMessage = null;
    });
    try {
      final models = await AiService.fetchModels(draft);
      if (!mounted) return;
      final picked = await _showModelPicker(models);
      if (picked != null && mounted) {
        setState(() => _modelCtrl.text = picked);
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _testSuccess = false;
          _testMessage = '拉取模型失败：$err';
        });
      }
    }
    if (mounted) setState(() => _fetchingModels = false);
  }

  Future<String?> _showModelPicker(List<String> models) {
    return showMiuixSheet<String>(
      context,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setPickerState) {
            final filtered = query.trim().isEmpty
                ? models
                : models
                      .where(
                        (m) => m.toLowerCase().contains(query.toLowerCase()),
                      )
                      .toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MiuixSheetHeader(
                  title: '选择模型',
                  subtitle: '共拉取 ${models.length} 个可用模型',
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 19),
                    hintText: '搜索模型名…',
                    isDense: true,
                  ),
                  onChanged: (v) => setPickerState(() => query = v),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: palette.divider),
                    itemBuilder: (_, idx) {
                      final name = filtered[idx];
                      final selected = name == _modelCtrl.text.trim();
                      return ListTile(
                        dense: true,
                        title: Text(
                          name,
                          style: TextStyle(
                            color: selected ? palette.primary : palette.ink,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 13.5,
                          ),
                        ),
                        trailing: selected
                            ? Icon(
                                Icons.check_rounded,
                                color: palette.primary,
                                size: 18,
                              )
                            : null,
                        onTap: () => Navigator.pop(sheetContext, name),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _testConnection() async {
    final draft = _draftConfig();
    if (!draft.isConfigured) {
      setState(() {
        _testSuccess = false;
        _testMessage = '请先填写 API 地址与模型名称';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final res = await AiService.testConnection(draft);
      if (!mounted) return;
      setState(() {
        _testSuccess = true;
        _testMessage = '连接成功（${res.latencyMs} ms）· 回复：${res.reply}';
      });
    } catch (err) {
      if (mounted) {
        setState(() {
          _testSuccess = false;
          _testMessage = '连接失败：$err';
        });
      }
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _save() async {
    final draft = _draftConfig();
    if (!draft.isConfigured) {
      setState(() {
        _testSuccess = false;
        _testMessage = '请先填写 API 地址与模型名称后再保存';
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await NativeApi.call('saveAiConfig', draft.toJson());
      if (!mounted) return;
      Navigator.pop(context, AiConfig.fromJson(saved));
    } catch (err) {
      if (mounted) {
        setState(() {
          _testSuccess = false;
          _testMessage = '保存失败：$err';
        });
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Loader()),
      );
    }

    final currentUrl = _baseUrlCtrl.text.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MiuixSheetHeader(
          title: '自定义 AI 接口',
          subtitle: '支持任何 OpenAI 兼容协议（DeepSeek / OpenAI / OneAPI / Ollama）',
        ),
        const SizedBox(height: 14),
        Text(
          '快速预设',
          style: TextStyle(
            color: palette.inkSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final preset in aiProviderPresets)
              ChoiceChip(
                label: Text(preset.name, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selected: preset.baseUrl.isNotEmpty
                    ? currentUrl == preset.baseUrl
                    : aiProviderPresets.every(
                        (p) => p.baseUrl.isEmpty || p.baseUrl != currentUrl,
                      ),
                onSelected: (_) => _selectPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _baseUrlCtrl,
          keyboardType: TextInputType.url,
          style: const TextStyle(fontSize: 13.5),
          decoration: const InputDecoration(
            labelText: 'API Base URL',
            hintText: 'https://api.deepseek.com/v1',
            helperText: '自动兼容带或不带 /v1、/chat/completions 后缀的地址',
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKeyCtrl,
          obscureText: _obscureKey,
          style: const TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            labelText: 'API Key（本地加密存储）',
            hintText: 'sk-...（本地免鉴权模型可留空）',
            isDense: true,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
              icon: Icon(
                _obscureKey
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _modelCtrl,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  labelText: '模型名称 (Model)',
                  hintText: 'deepseek-chat / gpt-4o-mini',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _fetchingModels ? null : _fetchModels,
                icon: _fetchingModels
                    ? const Loader(size: 14)
                    : const Icon(Icons.view_list_rounded, size: 17),
                label: const Text('拉取列表'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MiuixCard(
          color: palette.cardSubtle,
          showShadow: false,
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _toolsEnabled,
            onChanged: (v) => setState(() => _toolsEnabled = v),
            title: Text(
              '允许 AI 按需查询校园数据',
              style: TextStyle(
                color: palette.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              '仅在你提问课表、成绩、考试、电费或培养方案时才从本机调取并发送给当前模型',
              style: TextStyle(color: palette.inkSecondary, fontSize: 11.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              children: [
                Text(
                  '高级选项（System Prompt / Temperature）',
                  style: TextStyle(
                    color: palette.inkSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  _showAdvanced
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: palette.inkMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _systemPromptCtrl,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: '自定义系统提示词（可选）',
              hintText: '例如：请用要点列表总结，优先给出具体时间与教室',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '随机性 (Temperature)',
                style: TextStyle(
                  color: palette.inkSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _temperature.toStringAsFixed(1),
                style: TextStyle(
                  color: palette.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: _temperature.clamp(0.0, 1.5),
            min: 0.0,
            max: 1.5,
            divisions: 15,
            onChanged: (v) => setState(() => _temperature = v),
          ),
        ],
        if (_testMessage != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: ShapeDecoration(
              color: _testSuccess ? palette.successSoft : palette.dangerSoft,
              shape: miuixShape(14),
            ),
            child: Text(
              _testMessage!,
              style: TextStyle(
                color: _testSuccess ? palette.success : palette.danger,
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: (_testing || _saving) ? null : _testConnection,
                child: _testing ? const Loader(size: 16) : const Text('测试连接'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: (_saving || _testing) ? null : _save,
                child: _saving ? const Loader(size: 16) : const Text('保存配置'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
