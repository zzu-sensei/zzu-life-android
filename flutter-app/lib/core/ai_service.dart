import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'drain_estimator.dart';
import 'formatters.dart';
import 'native_api.dart';

/// 常见 OpenAI 兼容服务商预设（仅填充 Base URL 与推荐模型，密钥由用户自行填写）。
class AiProviderPreset {
  const AiProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    required this.hint,
  });

  final String name;
  final String baseUrl;
  final String defaultModel;
  final String hint;
}

const List<AiProviderPreset> aiProviderPresets = [
  AiProviderPreset(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    hint: 'DeepSeek V3 / R1 官方接口',
  ),
  AiProviderPreset(
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
    hint: 'OpenAI 官方或兼容代理地址',
  ),
  AiProviderPreset(
    name: '硅基流动',
    baseUrl: 'https://api.siliconflow.cn/v1',
    defaultModel: 'Qwen/Qwen2.5-7B-Instruct',
    hint: 'SiliconFlow 多模型聚合',
  ),
  AiProviderPreset(
    name: '阿里云百炼',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-plus',
    hint: '通义千问 OpenAI 兼容端点',
  ),
  AiProviderPreset(
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-4-flash',
    hint: '智谱开放平台 v4 接口',
  ),
  AiProviderPreset(
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: 'openai/gpt-4o-mini',
    hint: 'OpenRouter 聚合路由',
  ),
  AiProviderPreset(
    name: 'Gemini 兼容',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    defaultModel: 'gemini-2.5-flash',
    hint: 'Gemini OpenAI 兼容端点',
  ),
  AiProviderPreset(
    name: '自定义',
    baseUrl: '',
    defaultModel: '',
    hint: 'OneAPI / NewAPI / Ollama / 任意兼容地址',
  ),
];

/// 用户配置的自定义 AI 接口参数。
class AiConfig {
  const AiConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.systemPrompt = '',
    this.temperature = 0.7,
    this.toolsEnabled = true,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final double temperature;
  final bool toolsEnabled;

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  AiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    String? systemPrompt,
    double? temperature,
    bool? toolsEnabled,
  }) {
    return AiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      toolsEnabled: toolsEnabled ?? this.toolsEnabled,
    );
  }

  factory AiConfig.fromJson(Map<String, dynamic> map) {
    return AiConfig(
      baseUrl: (map['base_url'] ?? '').toString().trim(),
      apiKey: (map['api_key'] ?? '').toString().trim(),
      model: (map['model'] ?? '').toString().trim(),
      systemPrompt: (map['system_prompt'] ?? '').toString().trim(),
      temperature: ((map['temperature'] as num?)?.toDouble() ?? 0.7).clamp(
        0.0,
        2.0,
      ),
      toolsEnabled: map['tools_enabled'] != false,
    );
  }

  Map<String, Object?> toJson() => {
    'base_url': baseUrl.trim(),
    'api_key': apiKey.trim(),
    'model': model.trim(),
    'system_prompt': systemPrompt.trim(),
    'temperature': temperature,
    'tools_enabled': toolsEnabled,
  };
}

/// AI 工具调用轨迹卡片状态。
class AiToolTrace {
  const AiToolTrace({
    required this.name,
    required this.label,
    required this.status,
    this.summary = '',
  });

  final String name;
  final String label;
  final String status; // 'running' | 'done' | 'error'
  final String summary;

  AiToolTrace copyWith({String? status, String? summary}) {
    return AiToolTrace(
      name: name,
      label: label,
      status: status ?? this.status,
      summary: summary ?? this.summary,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'label': label,
    'status': status,
    'summary': summary,
  };

  factory AiToolTrace.fromJson(Map<String, dynamic> map) {
    return AiToolTrace(
      name: (map['name'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      status: (map['status'] ?? 'done').toString(),
      summary: (map['summary'] ?? '').toString(),
    );
  }
}

/// 聊天消息条目（支持思维链内容与工具查询痕迹）。
class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.reasoning = '',
    this.tools = const [],
    required this.createdAt,
    this.isError = false,
  });

  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final String reasoning;
  final List<AiToolTrace> tools;
  final int createdAt;
  final bool isError;

  AiChatMessage copyWith({
    String? content,
    String? reasoning,
    List<AiToolTrace>? tools,
    bool? isError,
  }) {
    return AiChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      tools: tools ?? this.tools,
      createdAt: createdAt,
      isError: isError ?? this.isError,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'reasoning': reasoning,
    'tools': [for (final t in tools) t.toJson()],
    'created_at': createdAt,
    'is_error': isError,
  };

  factory AiChatMessage.fromJson(Map<String, dynamic> map) {
    final rawTools = map['tools'];
    final parsedTools = <AiToolTrace>[
      if (rawTools is List)
        for (final item in rawTools.whereType<Map>())
          AiToolTrace.fromJson(Map<String, dynamic>.from(item)),
    ];
    return AiChatMessage(
      id: (map['id'] ?? '').toString(),
      role: (map['role'] ?? 'assistant').toString(),
      content: (map['content'] ?? '').toString(),
      reasoning: (map['reasoning'] ?? '').toString(),
      tools: parsedTools,
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      isError: map['is_error'] == true,
    );
  }
}

/// 按用户填写的 Base URL 智能补全 `/chat/completions` 端点。
Uri resolveChatCompletionsUri(String rawBaseUrl) {
  return _resolveEndpointUri(rawBaseUrl, 'chat/completions');
}

/// 按用户填写的 Base URL 智能补全 `/models` 端点。
Uri resolveModelsUri(String rawBaseUrl) {
  return _resolveEndpointUri(rawBaseUrl, 'models');
}

Uri _resolveEndpointUri(String rawBaseUrl, String endpoint) {
  var cleaned = rawBaseUrl.trim();
  while (cleaned.endsWith('/')) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  }
  final parsed = Uri.tryParse(cleaned);
  if (parsed == null ||
      !parsed.hasScheme ||
      (parsed.scheme != 'http' && parsed.scheme != 'https') ||
      parsed.host.isEmpty) {
    throw const ApiException('请填写以 http:// 或 https:// 开头的有效 API 地址');
  }

  var path = parsed.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  String nextPath;
  if (path.endsWith('/chat/completions')) {
    nextPath =
        '${path.substring(0, path.length - '/chat/completions'.length)}/$endpoint';
  } else if (path.endsWith('/models')) {
    nextPath = '${path.substring(0, path.length - '/models'.length)}/$endpoint';
  } else if (path.endsWith('/v1') ||
      path.endsWith('/v2') ||
      path.endsWith('/v3') ||
      path.endsWith('/v4') ||
      path.endsWith('/openai') ||
      path.endsWith('/compatible-mode/v1') ||
      path.contains('/v1/')) {
    nextPath = '$path/$endpoint';
  } else {
    nextPath = '$path/v1/$endpoint';
  }

  return parsed.replace(path: nextPath);
}

/// 郑大校园数据本地工具执行器（仅按需在本地调取教务/一卡通并脱敏汇总）。
class AiCampusToolRunner {
  static const Duration _cacheTtl = Duration(minutes: 5);

  final Map<String, ({DateTime fetchedAt, Map<String, dynamic> data})> _cache =
      {};

  void clearSessionCache() => _cache.clear();

  static String toolLabel(String name) {
    switch (name) {
      case 'get_schedule':
        return '课表';
      case 'get_grades':
        return '成绩与绩点';
      case 'get_exams':
        return '考试安排';
      case 'get_program_plan':
        return '培养方案';
      case 'get_energy':
        return '寝室电量';
      case 'get_free_rooms':
        return '空闲教室';
      case 'get_card_balance':
        return '一卡通余额';
      default:
        return name;
    }
  }

  static List<Map<String, dynamic>> get toolDefinitions => const [
    {
      'type': 'function',
      'function': {
        'name': 'get_schedule',
        'description':
            '查询用户的郑州大学课程表。优先读取整学期离线缓存，无缓存时实时查询。可用于查今天、明天、某天或指定教学周的课程时间与地点。',
        'parameters': {
          'type': 'object',
          'properties': {
            'week': {
              'type': 'integer',
              'description': '可选，指定教学周（1~30）。不填则默认查当前教学周。',
            },
            'day_offset': {
              'type': 'integer',
              'description': '可选，相对今天的日期偏移天数（0 表示今天，1 表示明天，-1 表示昨天）。',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_grades',
        'description': '查询用户已公布的课程成绩与按学分加权的平均绩点（GPA），支持按学期或课程名关键词过滤。',
        'parameters': {
          'type': 'object',
          'properties': {
            'semester': {
              'type': 'string',
              'description': '可选，按学期名称关键字过滤，例如 2025-2026。',
            },
            'keyword': {
              'type': 'string',
              'description': '可选，按课程名或课程代码过滤。',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_exams',
        'description': '查询当前或指定学期的期末/补考/期中考试时间、地点、考场与座位号。',
        'parameters': {
          'type': 'object',
          'properties': {
            'semester_id': {
              'type': 'string',
              'description': '可选，学期 ID。不填则自动选择有排考或当前学期。',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_program_plan',
        'description': '查询个人培养方案总学分要求、已修/在修/未通过学分与各模块完成进度。',
        'parameters': {
          'type': 'object',
          'properties': {
            'only_unfinished': {
              'type': 'boolean',
              'description': '为 true 时只重点返回未通过和在修课程。',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_energy',
        'description': '查询寝室房间号、照明与空调各电表当前剩余度数，以及结合历史采样拟合的日均耗电和预计可用天数。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_free_rooms',
        'description': '查询郑州大学各校区及教学楼在指定日期与节次的空闲教室列表。',
        'parameters': {
          'type': 'object',
          'properties': {
            'campus': {
              'type': 'string',
              'description': '可选，校区名称，如 主校区、南校区、北校区、东校区，默认主校区。',
            },
            'building': {
              'type': 'string',
              'description': '可选，教学楼名称关键词，如 北1、南2、中3。不填则查全校区。',
            },
            'date': {
              'type': 'string',
              'description': '可选，YYYY-MM-DD 日期。与 day_offset 二选一，默认今天。',
            },
            'day_offset': {
              'type': 'integer',
              'description': '可选，相对今天的偏移天数（0 今天，1 明天）。',
            },
            'units': {
              'type': 'array',
              'items': {'type': 'integer'},
              'description': '可选，要查询的节次列表，如 [3, 4] 或 [5, 6]。不填则按当前时间自动选择相邻大节。',
            },
            'room_type': {
              'type': 'string',
              'description': '可选，教室类型，如 多媒体教室、普通教室、实验室。',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_card_balance',
        'description': '查询校园一卡通当前余额（元）及校园邮箱未读邮件数。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
  ];

  Future<({String jsonResult, String summary})> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'get_schedule':
        return _runSchedule(args);
      case 'get_grades':
        return _runGrades(args);
      case 'get_exams':
        return _runExams(args);
      case 'get_program_plan':
        return _runPlan(args);
      case 'get_energy':
        return _runEnergy();
      case 'get_free_rooms':
        return _runFreeRooms(args);
      case 'get_card_balance':
        return _runCardBalance();
      default:
        throw ApiException('未知工具：$name');
    }
  }

  /// 为不支持 function calling `tools` 的中转/本地模型自动检索上下文。
  Future<String> buildFallbackContext(String question) async {
    final q = question.toLowerCase();
    final selected = <String>[];
    if (_matchesAny(q, ['空教室', '空闲教室', '自习', '没课的教室'])) {
      selected.add('get_free_rooms');
    } else if (_matchesAny(q, ['课', '课表', '上课', '教室', '老师', '今天', '明天', '周末', '周几', '节'])) {
      selected.add('get_schedule');
    }
    if (_matchesAny(q, ['成绩', '绩点', 'gpa', '挂科', '及格', '分数', '排名'])) {
      selected.add('get_grades');
    }
    if (_matchesAny(q, ['考试', '考场', '座位', '期末', '补考'])) {
      selected.add('get_exams');
    }
    if (_matchesAny(q, ['培养方案', '学分', '毕业', '选修', '必修', '在修'])) {
      selected.add('get_program_plan');
    }
    if (_matchesAny(q, ['电', '电费', '电量', '空调', '照明', '宿舍', '寝室', '续航'])) {
      selected.add('get_energy');
    }
    if (_matchesAny(q, ['校园卡', '一卡通', '饭卡', '卡余额', '余额'])) {
      selected.add('get_card_balance');
    }
    if (selected.isEmpty) return '';

    final buffer = StringBuffer();
    for (final tool in selected) {
      try {
        final res = await execute(tool, const {});
        buffer.writeln('[${toolLabel(tool)}] ${res.jsonResult}');
      } catch (e) {
        buffer.writeln('[${toolLabel(tool)} 查询失败] $e');
      }
    }
    return buffer.toString().trim();
  }

  static bool _matchesAny(String text, List<String> keywords) {
    for (final k in keywords) {
      if (text.contains(k)) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> _cachedCall(
    String cacheKey,
    Future<Map<String, dynamic>> Function() fetcher,
  ) async {
    final existing = _cache[cacheKey];
    if (existing != null &&
        DateTime.now().difference(existing.fetchedAt) < _cacheTtl) {
      return existing.data;
    }
    final fresh = await fetcher();
    _cache[cacheKey] = (fetchedAt: DateTime.now(), data: fresh);
    return fresh;
  }

  Future<({String jsonResult, String summary})> _runSchedule(
    Map<String, dynamic> args,
  ) async {
    final requestedWeek = (args['week'] as num?)?.toInt();
    final dayOffset = (args['day_offset'] as num?)?.toInt();
    final targetDate = dayOffset != null
        ? DateTime.now().add(Duration(days: dayOffset))
        : null;

    var resolvedWeek = requestedWeek;
    List<Map>? lessonsList;
    var source = '实时课表';

    final cached = await _cachedCall(
      'cached_schedule',
      () => NativeApi.call('getCachedSchedule'),
    );
    if (cached['cached'] == true && cached['data'] is Map) {
      final data = Map<String, dynamic>.from(cached['data'] as Map);
      final weeksMap = (data['weeks'] as Map?) ?? const {};
      final startStr = (data['start_date'] ?? '').toString();
      final parsedStart = startStr.length >= 10
          ? DateTime.tryParse(startStr.substring(0, 10))
          : null;
      if (resolvedWeek == null) {
        if (parsedStart != null) {
          final base = targetDate ?? DateTime.now();
          final d = DateTime(base.year, base.month, base.day);
          final s = DateTime(
            parsedStart.year,
            parsedStart.month,
            parsedStart.day,
          );
          resolvedWeek = (d.difference(s).inDays ~/ 7 + 1).clamp(1, 30);
        } else {
          resolvedWeek = (data['current_week'] as num?)?.toInt() ?? 1;
        }
      }
      final raw = weeksMap['$resolvedWeek'];
      lessonsList = raw is List ? raw.whereType<Map>().toList() : const [];
      source = '整学期离线缓存';
    } else {
      final targetWeekParam = resolvedWeek ?? 0;
      final res = await _cachedCall(
        'schedule_$targetWeekParam',
        () => NativeApi.call('getSchedule', {
          'week': targetWeekParam,
          'semester_id': 0,
        }),
      );
      resolvedWeek = (res['week'] as num?)?.toInt() ?? 1;
      lessonsList = ((res['lessons'] as List?) ?? const [])
          .whereType<Map>()
          .toList();
    }

    var filtered = lessonsList;
    int? targetWeekday;
    if (targetDate != null) {
      targetWeekday = targetDate.weekday;
      filtered = lessonsList
          .where((item) => (item['weekday'] as num?)?.toInt() == targetWeekday)
          .toList();
    }

    const dayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final compactLessons = [
      for (final l in filtered)
        {
          'course': l['course'],
          'weekday': dayNames[((l['weekday'] as num?)?.toInt() ?? 1).clamp(1, 7)],
          'units': '${l['start_unit']}-${l['end_unit']}',
          'time': '${l['start_time'] ?? ''}-${l['end_time'] ?? ''}',
          'place': l['place'],
          'teacher': l['teacher'],
          if (l['is_experiment'] == true) 'is_experiment': true,
        },
    ];

    final payload = {
      'source': source,
      'week': resolvedWeek,
      if (targetWeekday != null) 'target_weekday': dayNames[targetWeekday],
      'count': compactLessons.length,
      'lessons': compactLessons,
    };
    final desc = targetWeekday != null
        ? '第$resolvedWeek周 ${dayNames[targetWeekday]} ${compactLessons.length}节课'
        : '第$resolvedWeek周 共${compactLessons.length}节课';
    return (jsonResult: jsonEncode(payload), summary: desc);
  }

  Future<({String jsonResult, String summary})> _runGrades(
    Map<String, dynamic> args,
  ) async {
    final res = await _cachedCall(
      'grades',
      () => NativeApi.call('getGrades'),
    );
    final allGrades = ((res['grades'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final stats = computeWeightedGpaStats(allGrades);

    final semesterFilter = (args['semester'] ?? '').toString().trim();
    final keyword = (args['keyword'] ?? '').toString().trim().toLowerCase();
    final filtered = allGrades.where((g) {
      if (semesterFilter.isNotEmpty &&
          !(g['semester'] ?? '').toString().contains(semesterFilter)) {
        return false;
      }
      if (keyword.isNotEmpty) {
        final name = (g['course'] ?? '').toString().toLowerCase();
        final code = (g['code'] ?? '').toString().toLowerCase();
        if (!name.contains(keyword) && !code.contains(keyword)) return false;
      }
      return true;
    }).toList();

    final filteredStats = computeWeightedGpaStats(filtered);
    final truncated = filtered.length > 45;
    final items = filtered.take(45).map((g) => {
      'semester': g['semester'],
      'course': g['course'],
      'credits': g['credits'],
      'score': g['score'],
      'gp': g['gp'],
      'passed': g['passed'],
    }).toList();

    final payload = {
      'total_courses': allGrades.length,
      'overall_weighted_gpa': stats.gpa == null ? null : fixed4(stats.gpa),
      'overall_gpa_credits': number(stats.credits),
      'matched_count': filtered.length,
      if (semesterFilter.isNotEmpty || keyword.isNotEmpty)
        'matched_weighted_gpa': filteredStats.gpa == null
            ? null
            : fixed4(filteredStats.gpa),
      'truncated': truncated,
      'grades': items,
    };
    final gpaLabel = stats.gpa == null ? '--' : fixed4(stats.gpa);
    return (
      jsonResult: jsonEncode(payload),
      summary: '共${allGrades.length}门 · 加权GPA $gpaLabel',
    );
  }

  Future<({String jsonResult, String summary})> _runExams(
    Map<String, dynamic> args,
  ) async {
    final semId = (args['semester_id'] ?? '').toString().trim();
    final res = await _cachedCall(
      'exams_$semId',
      () => NativeApi.call('getExams', {'semester_id': semId}),
    );
    final exams = ((res['exams'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final sem = res['semester'] is Map ? res['semester'] as Map : const {};
    final semName = (sem['name'] ?? '当前学期').toString();

    final compact = [
      for (final e in exams)
        {
          'course': e['course'],
          'date': e['date'],
          'time': '${e['start_time'] ?? ''}-${e['end_time'] ?? ''}',
          'place': e['place'],
          'seat_no': e['seat_no'],
          'exam_type': e['exam_type'],
          'status': e['status_label'],
          'finished': e['finished'],
        },
    ];
    final payload = {
      'semester': semName,
      'count': compact.length,
      'exams': compact,
    };
    return (
      jsonResult: jsonEncode(payload),
      summary: '$semName ${compact.length}门考试',
    );
  }

  Future<({String jsonResult, String summary})> _runPlan(
    Map<String, dynamic> args,
  ) async {
    final res = await _cachedCall(
      'program_plan',
      () => NativeApi.call('getProgramPlan'),
    );
    final onlyUnfinished = args['only_unfinished'] == true;
    final modules = ((res['modules'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final failed = ((res['failed_courses'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final taking = ((res['taking_courses'] as List?) ?? const [])
        .whereType<Map>()
        .toList();

    final payload = {
      'required_credits': res['required_credits'],
      'passed_credits': res['passed_credits'],
      'taking_credits': res['taking_credits'],
      'failed_credits': res['failed_credits'],
      'missing_credits': res['missing'],
      if (!onlyUnfinished)
        'modules': [
          for (final m in modules.take(20))
            {
              'name': m['name'],
              'required': m['required_credits'],
              'passed': m['passed_credits'],
            },
        ],
      'failed_courses': [
        for (final c in failed.take(20))
          {'course': c['course'], 'credits': c['credits']},
      ],
      'taking_courses': [
        for (final c in taking.take(20))
          {'course': c['course'], 'credits': c['credits']},
      ],
    };
    return (
      jsonResult: jsonEncode(payload),
      summary:
          '已修 ${number(res['passed_credits'])}/${number(res['required_credits'])} 学分',
    );
  }

  Future<({String jsonResult, String summary})> _runEnergy() async {
    final energy = await _cachedCall(
      'energy',
      () => NativeApi.call('getEnergy'),
    );
    final samplesRes = await NativeApi.call('getEnergySamples');
    final samples = ((samplesRes['samples'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final estimates = estimateDrain(samples);
    final estimateById = {for (final e in estimates) e.meterId: e};

    final meters = ((energy['meter_list'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final meterSummary = <Map<String, dynamic>>[];
    final shortParts = <String>[];
    for (final m in meters) {
      if (m['error'] != null) continue;
      final id = (m['meter_id'] ?? '').toString();
      final label = (m['label'] ?? '电表').toString();
      final rem = m['remaining'];
      final est = estimateById[id];
      meterSummary.add({
        'label': label,
        'remaining_kwh': rem,
        if (est != null && est.ratePerDay > drainNegligibleRate)
          'daily_drain_kwh': est.ratePerDay.toStringAsFixed(2),
        if (est != null && est.daysLeft != null)
          'estimated_days_left': est.daysLeft!.toStringAsFixed(1),
        if (est != null && est.note.isNotEmpty) 'note': est.note,
      });
      shortParts.add('$label $rem度');
    }

    final payload = {
      'room': energy['room'],
      'meters': meterSummary,
    };
    return (
      jsonResult: jsonEncode(payload),
      summary: shortParts.isEmpty
          ? (energy['room'] ?? '查询完成').toString()
          : shortParts.join(' · '),
    );
  }

  Future<({String jsonResult, String summary})> _runFreeRooms(
    Map<String, dynamic> args,
  ) async {
    final campusQuery = (args['campus'] ?? '').toString().trim();
    final buildingQuery = (args['building'] ?? '').toString().trim();
    final typeQuery = (args['room_type'] ?? '').toString().trim();

    var meta = await _cachedCall(
      'room_meta_0',
      () => NativeApi.call('getFreeRoomMeta', {'campus_id': 0}),
    );

    final campuses = ((meta['campuses'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    var campusId = (meta['selected_campus_id'] as num?)?.toInt() ?? 2;
    var campusName = '主校区';
    for (final c in campuses) {
      final name = (c['name'] ?? '').toString();
      final id = (c['id'] as num?)?.toInt() ?? 0;
      if (campusQuery.isNotEmpty && name.contains(campusQuery) && id > 0) {
        campusId = id;
        campusName = name;
        break;
      }
      if (id == campusId && name.isNotEmpty) {
        campusName = name;
      }
    }

    if (campusId != (meta['selected_campus_id'] as num?)?.toInt()) {
      meta = await _cachedCall(
        'room_meta_$campusId',
        () => NativeApi.call('getFreeRoomMeta', {'campus_id': campusId}),
      );
    }

    var buildingId = '';
    var buildingName = '';
    if (buildingQuery.isNotEmpty) {
      final buildings = ((meta['buildings'] as List?) ?? const [])
          .whereType<Map>()
          .toList();
      for (final b in buildings) {
        final name = (b['name'] ?? '').toString();
        if (name == buildingQuery || name.contains(buildingQuery)) {
          buildingId = (b['id'] ?? '').toString();
          buildingName = name;
          break;
        }
      }
    }

    var roomTypeId = 0;
    if (typeQuery.isNotEmpty) {
      final types = ((meta['room_types'] as List?) ?? const [])
          .whereType<Map>()
          .toList();
      for (final rt in types) {
        final name = (rt['name'] ?? '').toString();
        if (name == typeQuery || name.contains(typeQuery)) {
          roomTypeId = (rt['id'] as num?)?.toInt() ?? 0;
          break;
        }
      }
    }

    String two(int n) => n.toString().padLeft(2, '0');
    final rawDate = (args['date'] ?? '').toString().trim();
    String targetDate;
    if (rawDate.length >= 10) {
      targetDate = rawDate.substring(0, 10);
    } else {
      final offset = (args['day_offset'] as num?)?.toInt() ?? 0;
      final dt = DateTime.now().add(Duration(days: offset));
      targetDate = '${dt.year}-${two(dt.month)}-${two(dt.day)}';
    }

    final parsedUnits = <int>[];
    final rawUnits = args['units'];
    if (rawUnits is List) {
      for (final u in rawUnits) {
        final val = (u as num?)?.toInt() ?? int.tryParse(u.toString()) ?? 0;
        if (val > 0) parsedUnits.add(val);
      }
    }
    if (parsedUnits.isEmpty) {
      final mins = DateTime.now().hour * 60 + DateTime.now().minute;
      if (mins < 9 * 60 + 40) {
        parsedUnits.addAll([1, 2]);
      } else if (mins < 11 * 60 + 50) {
        parsedUnits.addAll([3, 4]);
      } else if (mins < 15 * 60 + 40) {
        parsedUnits.addAll([5, 6]);
      } else if (mins < 17 * 60 + 40) {
        parsedUnits.addAll([7, 8]);
      } else {
        parsedUnits.addAll([9, 10]);
      }
    }
    parsedUnits.sort();

    final res = await NativeApi.call('getFreeRooms', {
      'campus_id': campusId,
      'building_id': buildingId,
      'date': targetDate,
      'units': parsedUnits.join(','),
      'room_type': roomTypeId,
      'min_seats': 0,
    });
    final allRooms = ((res['rooms'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final compact = [
      for (final r in allRooms.take(40))
        {
          'name': r['name'],
          'building': r['building'],
          'floor': r['floor'],
          'seats': r['seats'],
          'type': r['room_type'],
        },
    ];
    final payload = {
      'campus': campusName,
      if (buildingName.isNotEmpty) 'building': buildingName,
      'date': targetDate,
      'units': parsedUnits,
      'total_count': allRooms.length,
      'truncated': allRooms.length > 40,
      'rooms': compact,
    };
    return (
      jsonResult: jsonEncode(payload),
      summary: '$campusName${buildingName.isNotEmpty ? ' $buildingName' : ''} · ${allRooms.length}间',
    );
  }

  Future<({String jsonResult, String summary})> _runCardBalance() async {
    final res = await _cachedCall(
      'card_balance',
      () => NativeApi.call('getCardBalance'),
    );
    final bal = (res['balance'] as num?)?.toDouble();
    final unread = (res['email_unread'] as num?)?.toInt();
    final payload = {
      'balance_cny': bal,
      'unit': '元',
      if (unread != null) 'email_unread': unread,
    };
    return (
      jsonResult: jsonEncode(payload),
      summary: bal == null ? '查询完成' : '余额 ¥${bal.toStringAsFixed(2)}',
    );
  }
}

/// OpenAI 兼容流式对话客户端。
class AiService {
  HttpClient? _activeClient;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    try {
      _activeClient?.close(force: true);
    } catch (_) {}
    _activeClient = null;
  }

  /// 获取接口模型列表（GET /models）。
  static Future<List<String>> fetchModels(AiConfig config) async {
    final uri = resolveModelsUri(config.baseUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      _applyAuthHeaders(request.headers, config.apiKey);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(_extractHttpError(response.statusCode, body));
      }
      final decoded = jsonDecode(body);
      final rawList = decoded is Map ? decoded['data'] : decoded;
      final models = <String>{};
      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map && item['id'] != null) {
            final id = item['id'].toString().trim();
            if (id.isNotEmpty) models.add(id);
          } else if (item is String && item.trim().isNotEmpty) {
            models.add(item.trim());
          }
        }
      }
      final sorted = models.toList()..sort();
      if (sorted.isEmpty) {
        throw const ApiException('接口未返回模型列表，请直接手动填写模型名');
      }
      return sorted;
    } finally {
      client.close(force: true);
    }
  }

  /// 发送最小测试请求，确认连通性与鉴权。
  static Future<({int latencyMs, String reply})> testConnection(
    AiConfig config,
  ) async {
    if (!config.isConfigured) {
      throw const ApiException('请先填写 API 地址与模型名称');
    }
    final uri = resolveChatCompletionsUri(config.baseUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final sw = Stopwatch()..start();
    try {
      final request = await client.postUrl(uri);
      _applyAuthHeaders(request.headers, config.apiKey);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'model': config.model.trim(),
          'messages': [
            {'role': 'user', 'content': '请只回复 OK'},
          ],
          'max_tokens': 16,
          'stream': false,
        }),
      );
      final response = await request.close().timeout(const Duration(seconds: 25));
      final body = await utf8.decodeStream(response);
      sw.stop();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(_extractHttpError(response.statusCode, body));
      }
      final decoded = jsonDecode(body);
      var reply = '连接正常';
      if (decoded is Map) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final first = choices.first as Map;
          final msg = first['message'];
          if (msg is Map && msg['content'] != null) {
            reply = msg['content'].toString().trim();
          }
        }
      }
      if (reply.isEmpty) reply = '连接正常';
      return (latencyMs: sw.elapsedMilliseconds, reply: reply);
    } finally {
      client.close(force: true);
    }
  }

  /// 发起流式对话，支持多轮自动校园工具调用及不支持 tools 接口的自动回退。
  Future<void> streamChat({
    required AiConfig config,
    required List<AiChatMessage> history,
    required String userMessage,
    required AiCampusToolRunner toolRunner,
    required void Function(String content, String reasoning) onDelta,
    required void Function(List<AiToolTrace> traces) onToolUpdate,
  }) async {
    _cancelled = false;
    final uri = resolveChatCompletionsUri(config.baseUrl);
    final traces = <AiToolTrace>[];
    var contentAcc = '';
    var reasoningAcc = '';

    final recentHistory = history
        .where((m) => !m.isError && m.content.trim().isNotEmpty)
        .toList();
    final clippedHistory = recentHistory.length > 16
        ? recentHistory.sublist(recentHistory.length - 16)
        : recentHistory;

    final conversation = <Map<String, dynamic>>[
      {'role': 'system', 'content': _buildSystemPrompt(config, '')},
      for (final m in clippedHistory) {'role': m.role, 'content': m.content},
      {'role': 'user', 'content': userMessage},
    ];

    var useTools = config.toolsEnabled;
    const maxRounds = 4;

    for (var round = 0; round < maxRounds; round++) {
      if (_cancelled) return;
      _StreamResult result;
      try {
        result = await _sendCompletionRequest(
          uri: uri,
          config: config,
          messages: conversation,
          includeTools: useTools,
          onChunk: (c, r) {
            contentAcc += c;
            reasoningAcc += r;
            onDelta(contentAcc, reasoningAcc);
          },
        );
      } on _UnsupportedToolsException {
        if (!useTools || round > 0) rethrow;
        // 该自定义 API 或模型不支持 OpenAI function calling，自动改为本地检索后直接注入上下文。
        useTools = false;
        final trace = const AiToolTrace(
          name: 'fallback_context',
          label: '校园上下文检索',
          status: 'running',
        );
        traces.add(trace);
        onToolUpdate(List.unmodifiable(traces));
        final ctx = await toolRunner.buildFallbackContext(userMessage);
        traces[0] = trace.copyWith(
          status: 'done',
          summary: ctx.isEmpty ? '无需额外数据' : '已按关键词预取',
        );
        onToolUpdate(List.unmodifiable(traces));
        conversation[0] = {
          'role': 'system',
          'content': _buildSystemPrompt(config, ctx),
        };
        continue;
      }

      if (_cancelled) return;
      if (result.toolCalls.isEmpty) {
        return;
      }

      conversation.add({
        'role': 'assistant',
        if (result.content.isNotEmpty) 'content': result.content,
        'tool_calls': [
          for (final tc in result.toolCalls)
            {
              'id': tc.id,
              'type': 'function',
              'function': {'name': tc.name, 'arguments': tc.arguments},
            },
        ],
      });

      for (final tc in result.toolCalls) {
        if (_cancelled) return;
        final label = AiCampusToolRunner.toolLabel(tc.name);
        final traceIdx = traces.length;
        traces.add(
          AiToolTrace(name: tc.name, label: label, status: 'running'),
        );
        onToolUpdate(List.unmodifiable(traces));

        try {
          Map<String, dynamic> args = const {};
          if (tc.arguments.trim().isNotEmpty) {
            final decoded = jsonDecode(tc.arguments);
            if (decoded is Map) {
              args = Map<String, dynamic>.from(decoded);
            }
          }
          final execResult = await toolRunner.execute(tc.name, args);
          traces[traceIdx] = traces[traceIdx].copyWith(
            status: 'done',
            summary: execResult.summary,
          );
          onToolUpdate(List.unmodifiable(traces));
          conversation.add({
            'role': 'tool',
            'tool_call_id': tc.id,
            'content': execResult.jsonResult,
          });
        } catch (err) {
          final errText = err.toString();
          traces[traceIdx] = traces[traceIdx].copyWith(
            status: 'error',
            summary: errText,
          );
          onToolUpdate(List.unmodifiable(traces));
          conversation.add({
            'role': 'tool',
            'tool_call_id': tc.id,
            'content': jsonEncode({'error': errText}),
          });
        }
      }
      // 下一轮继续流式生成最终回答。
      if (contentAcc.isNotEmpty) {
        contentAcc += '\n';
      }
    }
  }

  Future<_StreamResult> _sendCompletionRequest({
    required Uri uri,
    required AiConfig config,
    required List<Map<String, dynamic>> messages,
    required bool includeTools,
    required void Function(String content, String reasoning) onChunk,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _activeClient = client;
    try {
      final request = await client.postUrl(uri);
      _applyAuthHeaders(request.headers, config.apiKey);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');

      final bodyMap = <String, dynamic>{
        'model': config.model.trim(),
        'messages': messages,
        'temperature': config.temperature,
        'stream': true,
        if (includeTools) 'tools': AiCampusToolRunner.toolDefinitions,
        if (includeTools) 'tool_choice': 'auto',
      };
      request.write(jsonEncode(bodyMap));

      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errBody = await utf8.decodeStream(response);
        if (includeTools &&
            (response.statusCode == 400 || response.statusCode == 422)) {
          throw const _UnsupportedToolsException();
        }
        throw ApiException(_extractHttpError(response.statusCode, errBody));
      }

      final contentType =
          response.headers.contentType?.mimeType.toLowerCase() ?? '';
      if (contentType.contains('application/json')) {
        final full = await utf8.decodeStream(response);
        return _parseSingleJsonResponse(full, onChunk);
      }

      final acc = _StreamAccumulator();
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (_cancelled) break;
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        if (!trimmed.startsWith('data:')) {
          // 兼容部分未加 data: 前缀直接返回 JSON 的服务
          if (trimmed.startsWith('{')) {
            return _parseSingleJsonResponse(trimmed, onChunk);
          }
          continue;
        }
        final dataStr = trimmed.substring(5).trim();
        if (dataStr == '[DONE]') break;

        Map<String, dynamic>? chunk;
        try {
          final parsed = jsonDecode(dataStr);
          if (parsed is Map<String, dynamic>) {
            chunk = parsed;
          } else if (parsed is Map) {
            chunk = Map<String, dynamic>.from(parsed);
          }
        } catch (_) {
          continue;
        }
        if (chunk == null) continue;
        if (chunk['error'] != null) {
          throw ApiException(_extractJsonErrorMap(chunk['error']));
        }
        final delta = acc.acceptChunk(chunk);
        if (delta.content.isNotEmpty || delta.reasoning.isNotEmpty) {
          onChunk(delta.content, delta.reasoning);
        }
      }
      return acc.buildResult();
    } finally {
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
      client.close(force: true);
    }
  }

  _StreamResult _parseSingleJsonResponse(
    String raw,
    void Function(String content, String reasoning) onChunk,
  ) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const ApiException('接口返回格式无法解析');
    }
    if (decoded['error'] != null) {
      throw ApiException(_extractJsonErrorMap(decoded['error']));
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return const _StreamResult(content: '', toolCalls: []);
    }
    final msg = (choices.first as Map)['message'];
    if (msg is! Map) {
      return const _StreamResult(content: '', toolCalls: []);
    }
    final content = (msg['content'] ?? '').toString();
    final reasoning =
        (msg['reasoning_content'] ?? msg['reasoning'] ?? '').toString();
    if (content.isNotEmpty || reasoning.isNotEmpty) {
      onChunk(content, reasoning);
    }
    final rawCalls = msg['tool_calls'];
    final parsedCalls = <_ToolCallData>[];
    if (rawCalls is List) {
      for (var i = 0; i < rawCalls.length; i++) {
        final item = rawCalls[i];
        if (item is! Map) continue;
        final fn = item['function'] is Map ? item['function'] as Map : const {};
        parsedCalls.add(
          _ToolCallData(
            id: (item['id'] ?? 'call_$i').toString(),
            name: (fn['name'] ?? '').toString(),
            arguments: fn['arguments'] is String
                ? fn['arguments'] as String
                : jsonEncode(fn['arguments'] ?? const {}),
          ),
        );
      }
    }
    return _StreamResult(content: content, toolCalls: parsedCalls);
  }

  static void _applyAuthHeaders(HttpHeaders headers, String apiKey) {
    final key = apiKey.trim();
    if (key.isNotEmpty) {
      headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
    }
  }

  static String _buildSystemPrompt(AiConfig config, String fallbackContext) {
    final now = DateTime.now();
    const weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    String two(int v) => v.toString().padLeft(2, '0');
    final dateStr =
        '${now.year}-${two(now.month)}-${two(now.day)} ${weekdays[now.weekday]} ${two(now.hour)}:${two(now.minute)}';

    final buffer = StringBuffer()
      ..writeln('你是「郑大生活助手」内置的 AI 校园助理，使用简洁清晰的简体中文回答用户问题。')
      ..writeln('当前本机时间：$dateStr。')
      ..writeln(
        '当用户询问个人课表、成绩、绩点、考试安排、培养方案、寝室电费、一卡通余额或校园空闲教室时，优先调用相应工具获取真实数据后作答；'
        '严禁编造不存在的课程、分数、时间、考场、教室或余额读数。',
      );
    if (config.systemPrompt.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('用户补充设定：')
        ..writeln(config.systemPrompt.trim());
    }
    if (fallbackContext.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('已自动为你检索到的本机校园数据：')
        ..writeln(fallbackContext);
    }
    return buffer.toString().trim();
  }

  static String _extractHttpError(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return 'HTTP $statusCode · ${_extractJsonErrorMap(decoded['error'])}';
      }
      if (decoded is Map && decoded['message'] != null) {
        return 'HTTP $statusCode · ${decoded['message']}';
      }
    } catch (_) {}
    final snippet = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (snippet.isEmpty) return '接口返回 HTTP $statusCode';
    return 'HTTP $statusCode · ${snippet.length > 140 ? '${snippet.substring(0, 140)}…' : snippet}';
  }

  static String _extractJsonErrorMap(Object? err) {
    if (err is Map && err['message'] != null) {
      return err['message'].toString();
    }
    return err?.toString() ?? '接口返回未知错误';
  }
}

class _UnsupportedToolsException implements Exception {
  const _UnsupportedToolsException();
}

class _ToolCallData {
  const _ToolCallData({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments;
}

class _MutableToolCall {
  String id = '';
  String name = '';
  final StringBuffer args = StringBuffer();
}

class _StreamResult {
  const _StreamResult({
    required this.content,
    required this.toolCalls,
  });

  final String content;
  final List<_ToolCallData> toolCalls;
}

class _StreamAccumulator {
  final StringBuffer _content = StringBuffer();
  final Map<int, _MutableToolCall> _toolCalls = {};

  ({String content, String reasoning}) acceptChunk(Map<String, dynamic> chunk) {
    final choices = chunk['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return const (content: '', reasoning: '');
    }
    final choice = choices.first as Map;
    final delta = choice['delta'];
    if (delta is! Map) {
      return const (content: '', reasoning: '');
    }

    final rawContent = delta['content'];
    var contentDelta = '';
    if (rawContent is String && rawContent.isNotEmpty) {
      contentDelta = rawContent;
      _content.write(rawContent);
    }

    final rawReasoning = delta['reasoning_content'] ?? delta['reasoning'];
    final reasoningDelta = rawReasoning is String ? rawReasoning : '';

    final rawToolCalls = delta['tool_calls'];
    if (rawToolCalls is List) {
      for (var i = 0; i < rawToolCalls.length; i++) {
        final item = rawToolCalls[i];
        if (item is! Map) continue;
        final idx = (item['index'] as num?)?.toInt() ?? i;
        final entry = _toolCalls.putIfAbsent(idx, _MutableToolCall.new);
        if (item['id'] != null && item['id'].toString().isNotEmpty) {
          entry.id = item['id'].toString();
        }
        final fn = item['function'];
        if (fn is Map) {
          if (fn['name'] != null && fn['name'].toString().isNotEmpty) {
            entry.name += fn['name'].toString();
          }
          if (fn['arguments'] != null) {
            entry.args.write(fn['arguments'].toString());
          }
        }
      }
    }
    return (content: contentDelta, reasoning: reasoningDelta);
  }

  _StreamResult buildResult() {
    final indices = _toolCalls.keys.toList()..sort();
    final calls = <_ToolCallData>[
      for (final idx in indices)
        if (_toolCalls[idx]!.name.isNotEmpty)
          _ToolCallData(
            id: _toolCalls[idx]!.id.isEmpty ? 'call_$idx' : _toolCalls[idx]!.id,
            name: _toolCalls[idx]!.name,
            arguments: _toolCalls[idx]!.args.toString(),
          ),
    ];
    return _StreamResult(content: _content.toString(), toolCalls: calls);
  }
}
