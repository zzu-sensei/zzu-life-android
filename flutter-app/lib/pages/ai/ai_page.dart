import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ai_service.dart';
import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';
import 'ai_config_sheet.dart';

/// AI 校园助手页面：支持自定义 OpenAI 兼容接口与按需检索校园数据。
class AiPage extends StatefulWidget {
  const AiPage({super.key});

  @override
  State<AiPage> createState() => AiPageState();
}

class AiPageState extends State<AiPage> {
  static const List<({IconData icon, String label, String prompt})>
      _quickPrompts = [
    (
      icon: Icons.today_rounded,
      label: '今明两天的课表',
      prompt: '帮我查一下今天和明天有哪些课，注意列出时间、地点和老师。',
    ),
    (
      icon: Icons.bolt_rounded,
      label: '寝室电量与校园卡',
      prompt: '帮我查一下寝室现在还剩多少度电（及预计可用天数）和校园一卡通余额。',
    ),
    (
      icon: Icons.meeting_room_outlined,
      label: '查空教室自习',
      prompt: '帮我查一下主校区今天第 5、6 节北1或北2有哪些空闲多媒体教室。',
    ),
    (
      icon: Icons.grade_rounded,
      label: '当前成绩与绩点',
      prompt: '帮我总结一下目前的加权平均绩点（GPA）和整体成绩情况。',
    ),
    (
      icon: Icons.event_note_rounded,
      label: '近期考试安排',
      prompt: '查一下最近有哪些考试安排、时间地点和座位号。',
    ),
    (
      icon: Icons.donut_large_rounded,
      label: '培养方案进度',
      prompt: '看看我培养方案还差多少学分，还有哪些未通过或正在修的课程？',
    ),
    (
      icon: Icons.calendar_view_week_rounded,
      label: '本周空闲时段',
      prompt: '查一下我这周的课表，告诉我哪几天比较空闲适合自习或安排事务。',
    ),
  ];

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final AiCampusToolRunner _toolRunner = AiCampusToolRunner();

  AiService? _activeService;
  AiConfig _config = const AiConfig();
  List<AiChatMessage> _messages = [];
  bool _loadingInit = true;
  bool _sending = false;
  final Set<String> _expandedReasoningIds = {};

  @override
  void initState() {
    super.initState();
    _initState();
  }

  @override
  void dispose() {
    _activeService?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 供外部（如「我的」页面修改 API 配置后）同步刷新配置。
  Future<void> reloadConfig() async {
    try {
      final raw = await NativeApi.call('getAiConfig');
      if (!mounted) return;
      setState(() => _config = AiConfig.fromJson(raw));
    } catch (_) {}
  }

  Future<void> _initState() async {
    await Future.wait([reloadConfig(), _loadHistory()]);
    if (mounted) setState(() => _loadingInit = false);
  }

  Future<void> _loadHistory() async {
    try {
      final raw = await NativeApi.call('getAiHistory');
      final list = raw['messages'];
      if (!mounted || list is! List) return;
      setState(() {
        _messages = [
          for (final item in list.whereType<Map>())
            AiChatMessage.fromJson(Map<String, dynamic>.from(item)),
        ];
      });
      _scrollToBottom(jump: true);
    } catch (_) {}
  }

  Future<void> _persistHistory() async {
    try {
      final encoded = [
        for (final msg in _messages)
          if (msg.content.trim().isNotEmpty || msg.tools.isNotEmpty)
            msg.toJson(),
      ];
      await NativeApi.call('saveAiHistory', {
        'messages': jsonEncode(encoded),
      });
    } catch (_) {}
  }

  Future<void> _openConfig() async {
    final updated = await showAiConfigSheet(
      context,
      initialConfig: _config,
    );
    if (updated != null && mounted) {
      setState(() => _config = updated);
    }
  }

  Future<void> _clearConversation() async {
    if (_sending) {
      _activeService?.cancel();
      _sending = false;
    }
    _toolRunner.clearSessionCache();
    setState(() {
      _messages = [];
      _expandedReasoningIds.clear();
    });
    try {
      await NativeApi.call('clearAiHistory');
    } catch (_) {}
  }

  Future<void> _sendMessage([String? presetText]) async {
    if (_sending) return;
    final text = (presetText ?? _inputCtrl.text).trim();
    if (text.isEmpty) return;

    if (!_config.isConfigured) {
      await _openConfig();
      if (!_config.isConfigured || !mounted) return;
    }

    if (presetText == null) {
      _inputCtrl.clear();
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();

    final now = DateTime.now().millisecondsSinceEpoch;
    final userMsg = AiChatMessage(
      id: 'u_$now',
      role: 'user',
      content: text,
      createdAt: now,
    );
    final assistantId = 'a_${now + 1}';
    final historyBefore = List<AiChatMessage>.from(_messages);

    setState(() {
      _sending = true;
      _messages.add(userMsg);
      _messages.add(
        AiChatMessage(
          id: assistantId,
          role: 'assistant',
          content: '',
          createdAt: now + 1,
        ),
      );
    });
    _scrollToBottom();

    await _runCompletion(
      assistantId: assistantId,
      historyBefore: historyBefore,
      userText: text,
    );
  }

  Future<void> _retryAssistant(int assistantIndex) async {
    if (_sending || assistantIndex <= 0) return;
    var userIdx = assistantIndex - 1;
    while (userIdx >= 0 && _messages[userIdx].role != 'user') {
      userIdx--;
    }
    if (userIdx < 0) return;
    final userText = _messages[userIdx].content;
    final historyBefore = _messages.sublist(0, userIdx);
    final assistantId = _messages[assistantIndex].id;

    setState(() {
      _sending = true;
      _messages[assistantIndex] = AiChatMessage(
        id: assistantId,
        role: 'assistant',
        content: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    });

    await _runCompletion(
      assistantId: assistantId,
      historyBefore: historyBefore,
      userText: userText,
    );
  }

  Future<void> _runCompletion({
    required String assistantId,
    required List<AiChatMessage> historyBefore,
    required String userText,
  }) async {
    final service = AiService();
    _activeService = service;

    try {
      await service.streamChat(
        config: _config,
        history: historyBefore,
        userMessage: userText,
        toolRunner: _toolRunner,
        onDelta: (content, reasoning) {
          if (!mounted) return;
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx < 0) return;
          setState(() {
            _messages[idx] = _messages[idx].copyWith(
              content: content,
              reasoning: reasoning,
            );
          });
          _scrollToBottom();
        },
        onToolUpdate: (traces) {
          if (!mounted) return;
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx < 0) return;
          setState(() {
            _messages[idx] = _messages[idx].copyWith(tools: traces);
          });
          _scrollToBottom();
        },
      );
      if (mounted) {
        final idx = _messages.indexWhere((m) => m.id == assistantId);
        if (idx >= 0 && _messages[idx].content.trim().isEmpty) {
          setState(() {
            _messages[idx] = _messages[idx].copyWith(
              content: _messages[idx].tools.isNotEmpty
                  ? '已完成信息查询（模型未返回正文）。'
                  : '已取消或未收到模型回复。',
            );
          });
        }
      }
    } catch (err) {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0) {
        final existing = _messages[idx].content.trim();
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            content: existing.isEmpty ? '请求失败：$err' : '$existing\n\n[中断：$err]',
            isError: true,
          );
        });
      }
    } finally {
      if (identical(_activeService, service)) {
        _activeService = null;
      }
      if (mounted) {
        setState(() => _sending = false);
      }
      await _persistHistory();
    }
  }

  void _stopStreaming() {
    _activeService?.cancel();
    setState(() => _sending = false);
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (jump) {
        _scrollCtrl.jumpTo(target);
      } else {
        _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final configured = _config.isConfigured;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
          child: Row(
            children: [
              Text(
                'AI 助手',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: GestureDetector(
                  onTap: _openConfig,
                  child: MiuixTag(
                    configured ? _config.model : '点击配置 API',
                    color: configured
                        ? palette.onPrimarySoft
                        : palette.warning,
                    backgroundColor: configured
                        ? palette.primarySoft
                        : palette.warningSoft,
                    icon: configured
                        ? Icons.auto_awesome_rounded
                        : Icons.tune_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (_messages.isNotEmpty)
                IconButton(
                  tooltip: '新对话',
                  onPressed: _clearConversation,
                  icon: const Icon(Icons.add_comment_outlined, size: 20),
                ),
              IconButton(
                tooltip: 'API 配置',
                onPressed: _openConfig,
                icon: const Icon(Icons.tune_rounded, size: 21),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingInit
              ? const Center(child: Loader())
              : _messages.isEmpty
              ? _buildEmptyState()
              : _buildMessageList(),
        ),
        _buildComposer(),
      ],
    );
  }

  Widget _buildEmptyState() {
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        MiuixHeroBanner(
          padding: const EdgeInsets.all(18),
          radius: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '智能校园问询',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _config.isConfigured
                              ? '已连接 ${_config.model}${_config.toolsEnabled ? ' · 支持校园数据工具' : ''}'
                              : '接入你自己的 OpenAI 兼容 API（DeepSeek / OpenAI / OneAPI 等）',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!_config.isConfigured) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: palette.primary,
                  ),
                  onPressed: _openConfig,
                  icon: const Icon(Icons.key_rounded, size: 17),
                  label: const Text('立即配置自定义 API'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '试试这样问',
          style: TextStyle(
            color: palette.inkSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in _quickPrompts)
              MiuixCard(
                radius: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                onTap: () => _sendMessage(item.prompt),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.icon, size: 16, color: palette.primary),
                    const SizedBox(width: 6),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      itemCount: _messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isLastAssistant =
            index == _messages.length - 1 && msg.role == 'assistant';
        if (msg.role == 'user') {
          return _buildUserBubble(msg);
        }
        return _buildAssistantBubble(
          msg,
          index: index,
          isStreamingHere: _sending && isLastAssistant,
        );
      },
    );
  }

  Widget _buildUserBubble(AiChatMessage msg) {
    final palette = context.palette;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: ShapeDecoration(
            color: palette.primary,
            shape: miuixShape(18),
          ),
          child: SelectableText(
            msg.content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(
    AiChatMessage msg, {
    required int index,
    required bool isStreamingHere,
  }) {
    final palette = context.palette;
    final hasReasoning = msg.reasoning.trim().isNotEmpty;
    final reasoningOpen = _expandedReasoningIds.contains(msg.id);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
        ),
        child: MiuixCard(
          radius: 18,
          padding: const EdgeInsets.all(14),
          borderColor: msg.isError
              ? palette.danger.withValues(alpha: 0.35)
              : palette.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.tools.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final trace in msg.tools) _buildToolChip(trace),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (hasReasoning) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() {
                    if (reasoningOpen) {
                      _expandedReasoningIds.remove(msg.id);
                    } else {
                      _expandedReasoningIds.add(msg.id);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: ShapeDecoration(
                      color: palette.cardSubtle,
                      shape: miuixShape(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology_alt_outlined,
                          size: 15,
                          color: palette.inkSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          reasoningOpen ? '收起思考过程' : '查看思考过程',
                          style: TextStyle(
                            color: palette.inkSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          reasoningOpen
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: palette.inkMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (reasoningOpen) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: ShapeDecoration(
                      color: palette.cardSubtle,
                      shape: miuixShape(12),
                    ),
                    child: SelectableText(
                      msg.reasoning.trim(),
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 12,
                        height: 1.48,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
              ],
              if (msg.content.isEmpty && isStreamingHere)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Loader(size: 15),
                    const SizedBox(width: 8),
                    Text(
                      msg.tools.any((t) => t.status == 'running')
                          ? '正在读取校园信息…'
                          : '正在思考回答…',
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              else
                _SimpleMarkdownBody(
                  text: msg.content,
                  isError: msg.isError,
                ),
              if (!isStreamingHere && msg.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(text: msg.content),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制回答内容')),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: palette.inkMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '复制',
                              style: TextStyle(
                                color: palette.inkMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (msg.isError) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _retryAssistant(index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh_rounded,
                                size: 14,
                                color: palette.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '重试',
                                style: TextStyle(
                                  color: palette.primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolChip(AiToolTrace trace) {
    final palette = context.palette;
    final isRunning = trace.status == 'running';
    final isError = trace.status == 'error';
    final fg = isError
        ? palette.danger
        : isRunning
        ? palette.onPrimarySoft
        : palette.success;
    final bg = isError
        ? palette.dangerSoft
        : isRunning
        ? palette.primarySoft
        : palette.successSoft;
    final text = isRunning
        ? '正在查询 ${trace.label}…'
        : isError
        ? '${trace.label} 查询失败'
        : '${trace.label}${trace.summary.isNotEmpty ? ' · ${trace.summary}' : ''}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRunning)
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: fg),
            )
          else
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              size: 13,
              color: fg,
            ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: MiuixCard(
        radius: 24,
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                style: TextStyle(color: palette.ink, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _config.isConfigured
                      ? '问问课表、成绩、电费，或任意问题…'
                      : '先点击上方「API 配置」或发送消息引导配置…',
                  hintStyle: TextStyle(color: palette.inkMuted, fontSize: 13),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: _sending ? palette.danger : palette.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _sending ? _stopStreaming : _sendMessage,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    _sending
                        ? Icons.stop_rounded
                        : Icons.arrow_upward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 轻量级 Markdown 正文渲染器（标题、加粗、行内代码、代码块与项目列表），零三方包依赖。
class _SimpleMarkdownBody extends StatelessWidget {
  const _SimpleMarkdownBody({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final baseStyle = TextStyle(
      color: isError ? palette.danger : palette.ink,
      fontSize: 14,
      height: 1.55,
    );

    final blocks = _splitCodeBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          if (blocks[i].isCode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: ShapeDecoration(
                color: palette.cardSubtle,
                shape: miuixShape(12),
              ),
              child: SelectableText(
                blocks[i].text,
                style: TextStyle(
                  color: palette.ink,
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            )
          else
            SelectableText.rich(
              TextSpan(
                style: baseStyle,
                children: _parseLines(blocks[i].text, palette, baseStyle),
              ),
            ),
        ],
      ],
    );
  }

  List<({bool isCode, String text})> _splitCodeBlocks(String input) {
    final lines = input.split('\n');
    final result = <({bool isCode, String text})>[];
    final buffer = StringBuffer();
    var inCode = false;

    for (final line in lines) {
      if (line.trimLeft().startsWith('```')) {
        if (buffer.isNotEmpty) {
          result.add((isCode: inCode, text: buffer.toString().trimRight()));
          buffer.clear();
        }
        inCode = !inCode;
        continue;
      }
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(line);
    }
    if (buffer.isNotEmpty) {
      result.add((isCode: inCode, text: buffer.toString().trimRight()));
    }
    if (result.isEmpty) {
      result.add((isCode: false, text: input));
    }
    return result;
  }

  List<InlineSpan> _parseLines(
    String input,
    AppPalette palette,
    TextStyle base,
  ) {
    final lines = input.split('\n');
    final spans = <InlineSpan>[];

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      TextStyle lineStyle = base;
      var prefix = '';

      if (line.startsWith('### ')) {
        line = line.substring(4);
        lineStyle = base.copyWith(fontSize: 15, fontWeight: FontWeight.w800);
      } else if (line.startsWith('## ')) {
        line = line.substring(3);
        lineStyle = base.copyWith(fontSize: 16, fontWeight: FontWeight.w800);
      } else if (line.startsWith('# ')) {
        line = line.substring(2);
        lineStyle = base.copyWith(fontSize: 17, fontWeight: FontWeight.w800);
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        line = line.substring(2);
        prefix = '• ';
      }

      if (prefix.isNotEmpty) {
        spans.add(
          TextSpan(
            text: prefix,
            style: lineStyle.copyWith(
              color: palette.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }
      spans.addAll(_parseInline(line, palette, lineStyle));
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return spans;
  }

  List<InlineSpan> _parseInline(
    String line,
    AppPalette palette,
    TextStyle base,
  ) {
    final spans = <InlineSpan>[];
    final tokenPattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
    var cursor = 0;
    for (final match in tokenPattern.allMatches(line)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: line.substring(cursor, match.start), style: base),
        );
      }
      final boldText = match.group(1);
      final codeText = match.group(2);
      if (boldText != null) {
        spans.add(
          TextSpan(
            text: boldText,
            style: base.copyWith(fontWeight: FontWeight.w800),
          ),
        );
      } else if (codeText != null) {
        spans.add(
          TextSpan(
            text: ' $codeText ',
            style: base.copyWith(
              fontFamily: 'monospace',
              fontSize: (base.fontSize ?? 14) - 1,
              color: palette.onPrimarySoft,
              backgroundColor: palette.primarySoft,
            ),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < line.length) {
      spans.add(TextSpan(text: line.substring(cursor), style: base));
    }
    return spans;
  }
}
