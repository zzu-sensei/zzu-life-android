"""Pure-Python semester schedule grouping for offline caching.

Deliberately avoids importing ``mobile_zzupy`` or ``gmalg`` so offline test
scripts can verify grouping, deduplication, and week resolution without native
extensions.
"""

from __future__ import annotations

from datetime import date
from typing import Any


def _parse_iso_date(raw: Any) -> date | None:
    text = str(raw or "").strip()[:10]
    if not text:
        return None
    try:
        return date.fromisoformat(text)
    except ValueError:
        return None


def group_semester_lessons(
    lessons: list[dict[str, Any]],
    start_date: str,
    week_indices: list[Any] | None = None,
) -> dict[str, Any]:
    """Group flat semester lessons into sorted, deduplicated week buckets."""
    start_dt = _parse_iso_date(start_date)
    max_week = 0
    for item in week_indices or []:
        try:
            idx = int(str(item).strip())
        except (TypeError, ValueError):
            continue
        if idx >= 1 and idx > max_week:
            max_week = idx

    weeks_raw: dict[int, list[dict[str, Any]]] = {}
    seen_per_week: dict[int, set[tuple[Any, ...]]] = {}

    for lesson in lessons or []:
        if not isinstance(lesson, dict):
            continue
        raw_indexes = lesson.get("week_indexes") or []
        target_weeks: list[int] = []
        for val in raw_indexes:
            try:
                w = int(str(val).strip())
            except (TypeError, ValueError):
                continue
            if w >= 1:
                target_weeks.append(w)

        if not target_weeks and start_dt is not None:
            lesson_dt = _parse_iso_date(lesson.get("date"))
            if lesson_dt is not None:
                w = (lesson_dt - start_dt).days // 7 + 1
                if w >= 1:
                    target_weeks.append(w)

        if not target_weeks:
            continue

        dedupe_key = (
            str(lesson.get("code") or lesson.get("course") or ""),
            int(lesson.get("weekday") or 0),
            int(lesson.get("start_unit") or 0),
            int(lesson.get("end_unit") or 0),
            str(lesson.get("place") or ""),
            str(lesson.get("start_time") or ""),
        )

        for w in target_weeks:
            if w > max_week:
                max_week = w
            seen = seen_per_week.setdefault(w, set())
            if dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            weeks_raw.setdefault(w, []).append(dict(lesson))

    if max_week < 1:
        max_week = 1

    weeks: dict[str, list[dict[str, Any]]] = {}
    total_lessons = 0
    for w in sorted(weeks_raw):
        bucket = sorted(
            weeks_raw[w],
            key=lambda item: (
                int(item.get("weekday") or 0),
                int(item.get("start_unit") or 0),
                str(item.get("start_time") or ""),
                str(item.get("course") or ""),
            ),
        )
        weeks[str(w)] = bucket
        total_lessons += len(bucket)

    return {
        "weeks": weeks,
        "max_week": max_week,
        "total_lessons": total_lessons,
    }
