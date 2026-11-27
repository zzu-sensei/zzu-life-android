import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';

/// 空闲教室查询页面：支持校区/教学楼/日期/节次/教室类型筛选，并按教学楼分组展示。
class FreeRoomPage extends StatefulWidget {
  const FreeRoomPage({super.key});

  @override
  State<FreeRoomPage> createState() => _FreeRoomPageState();
}

class _FreeRoomPageState extends State<FreeRoomPage> {
  static const List<String> _dayNames = ['', '一', '二', '三', '四', '五', '六', '日'];

  final Map<int, ({List<Map> buildings, List<Map> units})> _campusMetaCache = {};
  final TextEditingController _filterCtrl = TextEditingController();

  bool _loadingMeta = true;
  bool _switchingCampus = false;
  bool _querying = false;
  String? _metaError;
  String? _queryError;

  List<Map> _campuses = const [];
  List<Map> _buildings = const [];
  List<Map> _units = const [];
  List<Map> _roomTypes = const [];

  int _selectedCampusId = 2;
  String _selectedBuildingId = '';
  int _selectedRoomTypeId = 0;
  DateTime _selectedDate = _initialDate();
  final Set<int> _selectedUnits = {};

  bool _hasSearched = false;
  List<Map> _rooms = const [];
  String _keyword = '';

  static DateTime _initialDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _selectDefaultUnits();
    _loadMeta();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  void _selectDefaultUnits() {
    final now = DateTime.now();
    final mins = now.hour * 60 + now.minute;
    _selectedUnits.clear();
    if (mins < 9 * 60 + 40) {
      _selectedUnits.addAll([1, 2]);
    } else if (mins < 11 * 60 + 50) {
      _selectedUnits.addAll([3, 4]);
    } else if (mins < 15 * 60 + 40) {
      _selectedUnits.addAll([5, 6]);
    } else if (mins < 17 * 60 + 40) {
      _selectedUnits.addAll([7, 8]);
    } else if (mins < 20 * 60 + 40) {
      _selectedUnits.addAll([9, 10]);
    } else {
      _selectedUnits.addAll([1, 2]);
      _selectedDate = _initialDate().add(const Duration(days: 1));
    }
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  String _dateLabel(DateTime dt) {
    final today = _initialDate();
    final diff = dt.difference(today).inDays;
    final tag = diff == 0
        ? '今天'
        : diff == 1
        ? '明天'
        : diff == 2
        ? '后天'
        : '周${_dayNames[dt.weekday]}';
    return '${_formatDate(dt)} ($tag)';
  }

  Future<void> _loadMeta([int campusId = 0]) async {
    setState(() {
      if (campusId == 0) {
        _loadingMeta = true;
        _metaError = null;
      } else {
        _switchingCampus = true;
      }
    });
    try {
      final result = await NativeApi.call('getFreeRoomMeta', {
        'campus_id': campusId,
      });
      if (!mounted) return;
      final campuses = ((result['campuses'] as List?) ?? const [])
          .whereType<Map>()
          .toList();
      final roomTypes = ((result['room_types'] as List?) ?? const [])
          .whereType<Map>()
          .toList();
      final buildings = ((result['buildings'] as List?) ?? const [])
          .whereType<Map>()
          .toList();
      final units = ((result['units'] as List?) ?? const [])
          .whereType<Map>()
          .toList();
      final resolvedCampus =
          (result['selected_campus_id'] as num?)?.toInt() ??
          (campuses.isNotEmpty ? (campuses.first['id'] as num?)?.toInt() ?? 2 : 2);

      _campusMetaCache[resolvedCampus] = (buildings: buildings, units: units);
      setState(() {
        _campuses = campuses;
        _roomTypes = roomTypes;
        _buildings = buildings;
        _units = units;
        _selectedCampusId = resolvedCampus;
        _selectedBuildingId = '';
        _metaError = null;
      });
    } catch (caught) {
      if (mounted) setState(() => _metaError = caught.toString());
    }
    if (mounted) {
      setState(() {
        _loadingMeta = false;
        _switchingCampus = false;
      });
    }
  }

  Future<void> _onCampusChanged(int nextId) async {
    if (nextId == _selectedCampusId) return;
    final cached = _campusMetaCache[nextId];
    if (cached != null) {
      setState(() {
        _selectedCampusId = nextId;
        _selectedBuildingId = '';
        _buildings = cached.buildings;
        _units = cached.units;
      });
      return;
    }
    await _loadMeta(nextId);
  }

  Future<void> _query() async {
    if (_querying) return;
    if (_selectedUnits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个节次')),
      );
      return;
    }
    HapticFeedback.lightImpact();
    final sortedUnits = _selectedUnits.toList()..sort();
    setState(() {
      _querying = true;
      _queryError = null;
      _hasSearched = true;
    });
    try {
      final result = await NativeApi.call('getFreeRooms', {
        'campus_id': _selectedCampusId,
        'building_id': _selectedBuildingId,
        'date': _formatDate(_selectedDate),
        'units': sortedUnits.join(','),
        'room_type': _selectedRoomTypeId,
        'min_seats': 0,
      });
      if (!mounted) return;
      setState(() {
        _rooms = ((result['rooms'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
      });
    } catch (caught) {
      if (mounted) setState(() => _queryError = caught.toString());
    }
    if (mounted) setState(() => _querying = false);
  }

  String _selectedCampusName() {
    for (final c in _campuses) {
      if ((c['id'] as num?)?.toInt() == _selectedCampusId) {
        return (c['name'] ?? '主校区').toString();
      }
    }
    return '主校区';
  }

  String _selectedBuildingName() {
    if (_selectedBuildingId.isEmpty) return '全部教学楼';
    for (final b in _buildings) {
      if (b['id']?.toString() == _selectedBuildingId) {
        return (b['name'] ?? '全部教学楼').toString();
      }
    }
    return '全部教学楼';
  }

  Future<void> _pickCampus() async {
    if (_campuses.isEmpty) return;
    final picked = await showMiuixSheet<int>(
      context,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MiuixSheetHeader(title: '选择校区'),
            const SizedBox(height: 12),
            MiuixGroupedCard(
              dividerIndent: 16,
              children: [
                for (final campus in _campuses)
                  ListTile(
                    title: Text(
                      (campus['name'] ?? '').toString(),
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: (campus['id'] as num?)?.toInt() ==
                                _selectedCampusId
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing:
                        (campus['id'] as num?)?.toInt() == _selectedCampusId
                        ? Icon(Icons.check_rounded, color: palette.primary)
                        : null,
                    onTap: () => Navigator.pop(
                      sheetContext,
                      (campus['id'] as num?)?.toInt(),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (picked != null) await _onCampusChanged(picked);
  }

  Future<void> _pickBuilding() async {
    final picked = await showMiuixSheet<String>(
      context,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        var search = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = search.trim().isEmpty
                ? _buildings
                : _buildings
                      .where(
                        (b) => (b['name'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(search.trim().toLowerCase()),
                      )
                      .toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MiuixSheetHeader(
                  title: '选择教学楼',
                  subtitle: '${_selectedCampusName()} · 共 ${_buildings.length} 栋',
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 19),
                    hintText: '搜索教学楼，如 北1、南2…',
                    isDense: true,
                  ),
                  onChanged: (v) => setSheetState(() => search = v),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(
                          '全部教学楼',
                          style: TextStyle(
                            color: _selectedBuildingId.isEmpty
                                ? palette.primary
                                : palette.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: _selectedBuildingId.isEmpty
                            ? Icon(Icons.check_rounded, color: palette.primary)
                            : null,
                        onTap: () => Navigator.pop(sheetContext, ''),
                      ),
                      Divider(height: 1, color: palette.divider),
                      for (final b in filtered) ...[
                        ListTile(
                          dense: true,
                          title: Text(
                            (b['name'] ?? '').toString(),
                            style: TextStyle(
                              color: b['id']?.toString() == _selectedBuildingId
                                  ? palette.primary
                                  : palette.ink,
                              fontWeight:
                                  b['id']?.toString() == _selectedBuildingId
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          trailing: b['id']?.toString() == _selectedBuildingId
                              ? Icon(
                                  Icons.check_rounded,
                                  color: palette.primary,
                                  size: 18,
                                )
                              : null,
                          onTap: () => Navigator.pop(
                            sheetContext,
                            b['id']?.toString() ?? '',
                          ),
                        ),
                        Divider(height: 1, color: palette.divider),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (picked != null && picked != _selectedBuildingId) {
      setState(() => _selectedBuildingId = picked);
    }
  }

  Future<void> _pickCustomDate() async {
    final today = _initialDate();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: today.subtract(const Duration(days: 7)),
      lastDate: today.add(const Duration(days: 120)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  void _applyUnitPreset(List<int> units) {
    HapticFeedback.selectionClick();
    setState(() {
      final available = _units
          .map((u) => (u['value'] as num?)?.toInt() ?? 0)
          .where((v) => v > 0)
          .toSet();
      final filtered = available.isEmpty
          ? units
          : units.where(available.contains).toList();
      _selectedUnits
        ..clear()
        ..addAll(filtered);
    });
  }

  List<Map> _roomTypeOptions() {
    const preferredOrder = [2, 1, 5];
    final byId = {
      for (final rt in _roomTypes) (rt['id'] as num?)?.toInt() ?? 0: rt,
    };
    final ordered = <Map>[];
    for (final id in preferredOrder) {
      if (byId.containsKey(id)) ordered.add(byId[id]!);
    }
    for (final rt in _roomTypes) {
      final id = (rt['id'] as num?)?.toInt() ?? 0;
      if (!preferredOrder.contains(id) && id > 0) ordered.add(rt);
    }
    return ordered.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (_loadingMeta) {
      return const Center(child: Loader());
    }
    if (_metaError != null && _campuses.isEmpty) {
      return ErrorState(message: _metaError!, retry: _loadMeta);
    }

    final queryLower = _keyword.trim().toLowerCase();
    final visibleRooms = queryLower.isEmpty
        ? _rooms
        : _rooms.where((r) {
            final name = (r['name'] ?? '').toString().toLowerCase();
            final building = (r['building'] ?? '').toString().toLowerCase();
            final type = (r['room_type'] ?? '').toString().toLowerCase();
            return name.contains(queryLower) ||
                building.contains(queryLower) ||
                type.contains(queryLower);
          }).toList();

    final grouped = <String, List<Map>>{};
    for (final room in visibleRooms) {
      final bName = (room['building'] ?? '其他教学楼').toString();
      grouped.putIfAbsent(bName, () => []).add(room);
    }

    final today = _initialDate();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        MiuixCard(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SelectorBox(
                      label: '校区',
                      value: _selectedCampusName(),
                      icon: Icons.location_city_rounded,
                      loading: _switchingCampus,
                      onTap: _pickCampus,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SelectorBox(
                      label: '教学楼',
                      value: _selectedBuildingName(),
                      icon: Icons.apartment_rounded,
                      onTap: _pickBuilding,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '日期',
                    style: TextStyle(
                      color: palette.inkSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _dateLabel(_selectedDate),
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _pickCustomDate,
                    child: const Text('选日期', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in const [
                    (offset: 0, label: '今天'),
                    (offset: 1, label: '明天'),
                    (offset: 2, label: '后天'),
                  ])
                    ChoiceChip(
                      label: Text(
                        item.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      selected:
                          _selectedDate == today.add(Duration(days: item.offset)),
                      onSelected: (_) => setState(
                        () => _selectedDate = today.add(
                          Duration(days: item.offset),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '节次（可多选）',
                style: TextStyle(
                  color: palette.inkSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in const [
                    (label: '1–2节', units: [1, 2]),
                    (label: '3–4节', units: [3, 4]),
                    (label: '5–6节', units: [5, 6]),
                    (label: '7–8节', units: [7, 8]),
                    (label: '9–10节', units: [9, 10]),
                    (label: '上午', units: [1, 2, 3, 4]),
                    (label: '下午', units: [5, 6, 7, 8]),
                  ])
                    ActionChip(
                      label: Text(
                        preset.label,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: () => _applyUnitPreset(preset.units),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final u in _units)
                    if ((u['value'] as num?)?.toInt() != null)
                      FilterChip(
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(
                          '第${u['name'] ?? u['value']}节',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        selected: _selectedUnits.contains(
                          (u['value'] as num).toInt(),
                        ),
                        onSelected: (selected) {
                          final val = (u['value'] as num).toInt();
                          setState(() {
                            if (selected) {
                              _selectedUnits.add(val);
                            } else {
                              _selectedUnits.remove(val);
                            }
                          });
                        },
                      ),
                ],
              ),
              if (_roomTypeOptions().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '教室类型',
                  style: TextStyle(
                    color: palette.inkSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('全部', style: TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      selected: _selectedRoomTypeId == 0,
                      onSelected: (_) => setState(() => _selectedRoomTypeId = 0),
                    ),
                    for (final rt in _roomTypeOptions())
                      ChoiceChip(
                        label: Text(
                          (rt['name'] ?? '').toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected:
                            (rt['id'] as num?)?.toInt() == _selectedRoomTypeId,
                        onSelected: (_) => setState(
                          () => _selectedRoomTypeId =
                              (rt['id'] as num?)?.toInt() ?? 0,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: _querying ? null : _query,
                  icon: _querying
                      ? const Loader(size: 16)
                      : const Icon(Icons.search_rounded, size: 19),
                  label: Text(_querying ? '正在查询…' : '查询空闲教室'),
                ),
              ),
            ],
          ),
        ),
        if (_queryError != null) ...[
          const SizedBox(height: 12),
          ErrorState(message: _queryError!, retry: _query),
        ] else if (_hasSearched && !_querying) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '查询结果 · 共 ${visibleRooms.length} 间',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (_rooms.length != visibleRooms.length)
                Text(
                  '总计 ${_rooms.length} 间',
                  style: TextStyle(color: palette.inkMuted, fontSize: 12),
                ),
            ],
          ),
          if (_rooms.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _filterCtrl,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.filter_list_rounded, size: 18),
                hintText: '在结果中筛选教室号或教学楼…',
                isDense: true,
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17),
                        onPressed: () {
                          _filterCtrl.clear();
                          setState(() => _keyword = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _keyword = v),
            ),
          ],
          const SizedBox(height: 10),
          if (visibleRooms.isEmpty)
            const EmptyState(
              Icons.meeting_room_outlined,
              '该时段暂无符合条件的空闲教室',
            )
          else
            for (final entry in grouped.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                child: Row(
                  children: [
                    Text(
                      entry.key,
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    MiuixTag('${entry.value.length} 间'),
                  ],
                ),
              ),
              MiuixGroupedCard(
                dividerIndent: 16,
                children: [
                  for (final room in entry.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (room['name'] ?? '未知教室').toString(),
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    if ((room['floor'] as num?) != null &&
                                        (room['floor'] as num) != 0)
                                      '${room['floor']}楼',
                                    if ((room['room_type'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      room['room_type'].toString(),
                                  ].join(' · '),
                                  style: TextStyle(
                                    color: palette.inkSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (((room['seats'] as num?)?.toInt() ?? 0) > 0)
                            MiuixTag(
                              '${room['seats']} 座',
                              color: palette.onPrimarySoft,
                              backgroundColor: palette.primarySoft,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
        ],
      ],
    );
  }
}

class _SelectorBox extends StatelessWidget {
  const _SelectorBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.cardSubtle,
      shape: miuixShape(14, side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 17, color: palette.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: palette.inkMuted, fontSize: 10.5),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              loading
                  ? const Loader(size: 14)
                  : Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: palette.inkMuted,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
