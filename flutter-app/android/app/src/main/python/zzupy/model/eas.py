from __future__ import annotations

import json
import re
import uuid
from typing import Any, ClassVar, List

from icalendar import Calendar
from icalendar.cal import Event
from pydantic import (
    AliasChoices,
    BaseModel,
    ConfigDict,
    Field,
    RootModel,
    field_validator,
    model_validator,
)
from pydantic.alias_generators import to_camel
from whenever import Date, Instant, Time, ZonedDateTime


class Campus(BaseModel):
    """校区信息"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    id: int
    name_zh: str
    """校区中文名"""
    name_en: None | str = None
    """校区英文名"""
    code: str
    """校区编号"""


class CultivateType(BaseModel):
    """培养类型，如主修、辅修等"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    id: int
    name_zh: str
    """培养类型中文名"""
    name_en: str | None = None
    """培养类型英文名"""
    code: str
    """培养类型编号"""


class PeriodInfo(BaseModel):
    """课时详情；各分类课时可能由服务器返回数值或空值。"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    total: int = 0
    weeks: int = 0
    theory: int | None = None
    theory_unit: str | None = None
    require_theory: int | None = None
    practice: int | None = None
    practice_unit: str | None = None
    require_practice: int | None = None
    focus_practice: int | None = None
    focus_practice_unit: str | None = None
    dispersed_practice: int | None = None
    test: int | None = None
    test_unit: str | None = None
    require_test: int | None = None
    experiment: int | None = None
    experiment_unit: str | None = None
    require_experiment: int | None = None
    machine: int | None = None
    machine_unit: str | None = None
    require_machine: int | None = None
    design: int | None = None
    design_unit: str | None = None
    require_design: int | None = None
    periods_per_week: float = 0
    """每周学时可能为小数，保留服务器精度，不按课次取整。"""
    extra: int | None = None
    extra_unit: str | None = None
    require_extra: int | None = None

class Course(BaseModel):
    """课程基本信息；只将课表展示所需字段设为必填。"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    id: int = 0
    code: str = ""
    """课程编号"""
    name_zh: str
    """课程中文名"""
    name_en: str | None = None
    """课程英文名"""
    credits: float = 0
    """学分"""
    period_info: PeriodInfo | None = None
    """课时详情；服务器可能省略。"""
    theory: bool = False
    experiment: bool = False
    practice: bool = False
    test: bool = False
    machine: bool = False
    design: bool = False
    extra: bool = False

class OpenDepartment(BaseModel):
    """开课院系"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    id: int
    name_zh: str
    """院系中文名"""
    name_en: None | str = None
    """院系英文名"""
    code: str
    """院系编号"""


class CourseType(BaseModel):
    """课程类型，如必修课、选修课等"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    id: int
    name_zh: str
    """课程类型中文名"""
    name_en: None | str = None
    """课程类型英文名"""
    code: str
    """课程类型编号"""


class DateTimeText(BaseModel):
    """上课时间的文字描述；文字字段可能为空。"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    text_zh: str | None = None
    text_en: str | None = None
    text: str | None = None


class DateTimePlaceText(BaseModel):
    """上课时间与地点的文字描述；文字字段可能为空。"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    text_zh: str | None = None
    text_en: str | None = None
    text: str | None = None


class DateTimePlacePersonText(BaseModel):
    """上课时间、地点与教师的文字描述；文字字段可能为空。"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    text_zh: str | None = None
    text_en: str | None = None
    text: str | None = None


class ScheduleText(BaseModel):
    """教学班排课的综合文字描述。"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    date_time_text: DateTimeText | None = None
    date_time_place_text: DateTimePlaceText | None = None
    date_time_place_person_text: DateTimePlacePersonText | None = None

class ScheduleGroup(BaseModel):
    """排课组，将一个教学班的多次课归入同一组"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    id: int
    """排课组 ID"""
    lesson_id: int
    """所属教学班 ID"""
    no: int
    """排课组序号"""


class Building(BaseModel):
    """楼栋信息"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    id: int
    name_zh: str
    """楼栋中文名"""
    name_en: None | str = None
    """楼栋英文名"""
    code: str
    """楼栋编号"""


class Room(BaseModel):
    """教室信息"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    id: int
    name_zh: str
    """教室中文名"""
    name_en: None | str = None
    """教室英文名"""
    building: Building
    """所在楼栋"""
    campus: Campus
    """所在校区"""
    seat_number: int | None = None
    """座位数"""


class Schedule(BaseModel):
    """单次课程的具体排课记录"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    schedule_group_id: int = 0
    """所属排课组 ID，关联 ScheduleGroup.id"""
    date: Date
    """上课日期，格式 "YYYY-MM-DD" """
    original_date: None | str = None
    """原始日期"""
    weekday: int
    """星期几，1=周一，4=周四，7=周日"""
    start_time: ZonedDateTime
    """开始时间，格式 HHMM，如 1010 表示 10:10"""
    end_time: ZonedDateTime
    """结束时间，格式 HHMM，如 1150 表示 11:50"""
    teacher_name: str = ""
    """授课教师中文姓名"""
    teacher_name_en: str | None = None
    """授课教师英文姓名"""
    teacher_id: None | str = None
    person_id: None | str = None
    custom_place: None | str = None
    """自定义上课地点"""
    room: Room | None = None
    """教室信息"""
    start_unit: int
    """开始节次，如 3（第3节）"""
    end_unit: int
    """结束节次，如 4（第4节）"""
    start_unit_name_zh: None | str = None
    end_unit_name_zh: None | str = None
    start_unit_name_en: None | str = None
    end_unit_name_en: None | str = None
    state: str = ""
    """课程状态"""
    week_index: int
    """本次课所在教学周，如 1 表示第1周"""
    lesson_type: str = ""
    """课时类型，如 "THEORY"（理论课）"""
    periods: int = 0
    """本次课课时数，如 2"""
    real_start_time: ZonedDateTime | None = None
    """实际开始时间，格式同 startTime"""
    real_end_time: ZonedDateTime | None = None
    """实际结束时间，格式同 endTime"""

    @model_validator(mode="before")
    @classmethod
    def assemble_whenever_datetime(cls, data: dict) -> dict:
        if not isinstance(data, dict):
            return data

        date_str = data.get("date")
        if not date_str:
            return data

        try:
            schedule_date = Date.parse_iso(str(date_str))
        except ValueError as exc:
            raise ValueError(f"无法解析课程日期 date={date_str!r}") from exc

        time_keys = [
            "startTime",
            "endTime",
            "realStartTime",
            "realEndTime",
        ]

        for key in time_keys:
            time_val = data.get(key)
            if time_val:
                if isinstance(time_val, ZonedDateTime):
                    continue

                time_str = str(time_val).strip()
                if "T" in time_str:
                    continue
                if ":" in time_str:
                    parts = time_str.split(":")
                    time_str = parts[0].zfill(2) + parts[1].zfill(2)
                else:
                    time_str = time_str.zfill(4)
                try:
                    schedule_time = Time.parse(time_str, format="hhmm")
                    data[key] = schedule_date.at(schedule_time).assume_tz(
                        "Asia/Shanghai"
                    )
                except ValueError as exc:
                    raise ValueError(
                        f"无法解析课程时间字段 {key}={time_val!r}"
                    ) from exc

        return data


class Datum(BaseModel):
    """教学班信息；兼容服务器省略与课表无关的展示字段。"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    id: int = 0
    biz_type_id: int = 0
    campus: Campus | None = None
    cultivate_type: CultivateType | None = None
    code: str = ""
    course: Course
    remark: str | None = None
    schedule_state: str = ""
    std_count: int = 0
    open_department: OpenDepartment | None = None
    course_type: CourseType | None = None
    teacher_assignment_list: list[str] = Field(default_factory=list)
    teacher_assignment_en_list: list[str | None] = Field(default_factory=list)
    schedule_text: ScheduleText | None = None
    schedule_groups: list[ScheduleGroup] = Field(default_factory=list)
    schedules: list[Schedule] = Field(default_factory=list)
    students: list[Any] = Field(default_factory=list)
    time_table_layout_assoc: int | None = None
    suggest_schedule_weeks_info: Any | None = None

class LessonModel(BaseModel):
    """课程表查询 API 响应根模型，兼容常见分页外壳。"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    result: int = 0
    message: str | None = None
    data: list[Datum]

    @model_validator(mode="before")
    @classmethod
    def normalize_response(cls, data: Any) -> Any:
        def find_records(value: Any, depth: int = 0) -> list[Any] | None:
            if depth > 5:
                return None
            if isinstance(value, list):
                return value
            if not isinstance(value, dict):
                return None
            for key in ("data", "records", "rows", "content", "list", "items"):
                if key in value:
                    records = find_records(value[key], depth + 1)
                    if records is not None:
                        return records
            return None

        if isinstance(data, list):
            return {"result": 0, "data": data}
        if not isinstance(data, dict):
            return data
        normalized = dict(data)
        records = find_records(data.get("data"))
        if records is not None:
            normalized["data"] = records
        normalized.setdefault("result", data.get("code", 0))
        normalized.setdefault("message", data.get("msg"))
        return normalized

class Lesson(BaseModel):
    """课表中的一节课"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    course: Course
    """对应课程"""
    schedule: Schedule
    """对应时间"""


class TeachingWeek(BaseModel):
    """教学周课表，7 天 × 10 节的网格"""

    model_config = ConfigDict(frozen=False)

    DAYS: ClassVar[int] = 7
    UNITS: ClassVar[int] = 10

    lessons: dict[tuple[int, int], Lesson] = Field(default_factory=dict)
    """内部存储：仅存储非空课程，key 为 (weekday, unit)，value 为 Lesson"""

    def _validate_index(self, weekday: int, unit: int) -> None:
        if not (1 <= weekday <= self.DAYS):
            raise IndexError(f"星期 {weekday} 超出范围 (1-{self.DAYS})")
        if not (1 <= unit <= self.UNITS):
            raise IndexError(f"节次 {unit} 超出范围 (1-{self.UNITS})")

    def set(self, weekday: int, unit: int, lesson: Lesson) -> None:
        """设置某天某节的课程

        Args:
            weekday: 第几天
            unit: 第几节
            lesson: 课程

        Raises:
            IndexError: 如果 {weekday} 或 {unit} 超出范围
        """
        self._validate_index(weekday, unit)
        self.lessons[(weekday, unit)] = lesson

    def get(self, weekday: int, unit: int) -> Lesson | None:
        """获取某天某节的课程

        Args:
            weekday: 第几天
            unit: 第几节

        Returns:
            Lesson | None: 对应课程或 None

        Raises:
            IndexError: 如果 {weekday} 或 {unit} 超出范围
        """
        self._validate_index(weekday, unit)
        return self.lessons.get((weekday, unit))

    def get_day(self, weekday: int) -> list[Lesson | None]:
        """获取某天的全部课程

        Args:
            weekday: 第几天

        Returns:
            list[Lesson | None]: 由第 {weekday} 天中的第 {unit} 节课组成的列表

        Raises:
            IndexError: 如果 {weekday} 超出范围
        """
        self._validate_index(weekday, 1)
        return [self.lessons.get((weekday, unit)) for unit in range(1, self.UNITS + 1)]

    def get_unit(self, unit: int) -> list[Lesson | None]:
        """获取某节 7 天的课程

        Args:
            unit: 第几节课

        Returns:
            list[Lesson | None]: 由 7 天中的第 {unit} 节课组成的列表

        Raises:
            IndexError: 如果 {unit} 超出范围
        """
        self._validate_index(1, unit)
        return [self.lessons.get((day, unit)) for day in range(1, self.DAYS + 1)]

    @property
    def grid(self) -> list[list[Lesson | None]]:
        """网格形式的课表，仅在访问时动态生成"""
        return [
            [self.lessons.get((day, unit)) for unit in range(1, self.UNITS + 1)]
            for day in range(1, self.DAYS + 1)
        ]

    def to_calendar(
        self, prodid: str = "-//ZZU.Py//Teaching Schedule Calendar//CN"
    ) -> Calendar:
        """
        将教学周的课表转换为符合 RFC 5545 的 Calendar 对象。
        可以使用以下代码将其写入 .ics 或对它做你想做的任何事
        ```python
        with open('my_schedule.ics', 'wb') as f:
            f.write(aTeachingWeek.to_calendar().to_ical())
        ```

        Args:
            prodid: Calendar 的 prodid 参数。

        Returns:
            Calendar 对象。
        """
        cal = Calendar()
        cal.add("prodid", prodid)
        cal.add("version", "2.0")

        processed_schedule_ids = set()

        for lesson in self.lessons.values():
            if not lesson:
                continue

            schedule = lesson.schedule
            course = lesson.course

            # 去重
            if schedule in processed_schedule_ids:
                continue
            processed_schedule_ids.add(schedule)

            event = Event()

            # 课程中文名
            event.add("summary", course.name_zh)

            # 起始时间
            start_time = (
                (schedule.real_start_time or schedule.start_time).to_stdlib()
            )
            end_time = (
                (schedule.real_end_time or schedule.end_time).to_stdlib()
            )
            event.add("dtstart", start_time)
            event.add("dtend", end_time)

            # 事件生成时间
            event.add("dtstamp", Instant.now().to_stdlib())

            # 事件 UID
            event.add("uid", f"{uuid.uuid4()}@schedule")

            # 上课地点
            location = ""
            if schedule.room:
                location = (
                    f"{schedule.room.campus.name_zh} "
                    f"{schedule.room.building.name_zh} "
                    f"{schedule.room.name_zh}"
                )
            elif schedule.custom_place:
                location = schedule.custom_place

            if location:
                event.add("location", location)

            # 描述
            description_lines = [
                f"授课教师: {schedule.teacher_name or '未知'}",
                f"课程代码: {course.code}",
                f"学分: {course.credits}",
                f"节次: 第 {schedule.start_unit} - {schedule.end_unit} 节",
                f"教学周: 第 {schedule.week_index} 周",
                f"类型: {schedule.lesson_type}",
            ]
            event.add("description", "\n".join(description_lines))

            cal.add_component(event)
        return cal


class TeachingWeeks(RootModel):
    root: list[TeachingWeek] = Field(default_factory=list)

    def __iter__(self):
        return iter(self.root)

    def __getitem__(self, item):
        return self.root[item]

    def __len__(self):
        return len(self.root)

    def to_calendar(
        self, prodid: str = "-//ZZU.Py//Teaching Schedule Calendar//CN"
    ) -> Calendar:
        """
        将教学周的课表转换为符合 RFC 5545 的 Calendar 对象。
        可以使用以下代码将其写入 .ics 或对它做你想做的任何事
        ```python
        with open('my_schedule.ics', 'wb') as f:
            f.write(aTeachingWeek.to_calendar().to_ical())
        ```

        Args:
            prodid: Calendar 的 prodid 参数。

        Returns:
            Calendar 对象。
        """
        cal = Calendar()
        cal.add("prodid", prodid)
        cal.add("version", "2.0")

        processed_schedule_ids = set()
        for teaching_week in self.root:
            for lesson in teaching_week.lessons.values():
                if not lesson:
                    continue

                schedule = lesson.schedule
                course = lesson.course

                # 去重
                if schedule in processed_schedule_ids:
                    continue
                processed_schedule_ids.add(schedule)

                event = Event()

                # 课程中文名
                event.add("summary", course.name_zh)

                # 起始时间
                start_time = (
                    (schedule.real_start_time or schedule.start_time).to_stdlib()
                )
                end_time = (
                    (schedule.real_end_time or schedule.end_time).to_stdlib()
                )
                event.add("dtstart", start_time)
                event.add("dtend", end_time)

                # 事件生成时间
                event.add("dtstamp", Instant.now().to_stdlib())

                # 事件 UID
                event.add("uid", f"{uuid.uuid4()}@schedule")

                # 上课地点
                location = ""
                if schedule.room:
                    location = (
                    f"{schedule.room.campus.name_zh} "
                    f"{schedule.room.building.name_zh} "
                    f"{schedule.room.name_zh}"
                )
                elif schedule.custom_place:
                    location = schedule.custom_place

                if location:
                    event.add("location", location)

                # 描述
                description_lines = [
                    f"授课教师: {schedule.teacher_name or '未知'}",
                    f"课程代码: {course.code}",
                    f"学分: {course.credits}",
                    f"节次: 第 {schedule.start_unit} - {schedule.end_unit} 节",
                    f"教学周: 第 {schedule.week_index} 周",
                    f"类型: {schedule.lesson_type}",
                ]
                event.add("description", "\n".join(description_lines))

                cal.add_component(event)

        return cal


class GradeSemester(BaseModel):
    """成绩所属学期的简要信息。"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    name_zh: str = "未知学期"
    """学期中文名称。"""

    @model_validator(mode="before")
    @classmethod
    def normalize_semester(cls, data: Any) -> Any:
        if isinstance(data, (str, int, float)):
            return {"nameZh": str(data)}
        if isinstance(data, dict):
            normalized = dict(data)
            if not normalized.get("nameZh"):
                for key in ("name", "semesterName", "termName", "label"):
                    if normalized.get(key) not in (None, ""):
                        normalized["nameZh"] = str(normalized[key])
                        break
            return normalized
        return {"nameZh": "未知学期"}


_GRADE_COMPONENT_ALIASES = {
    "grade_level": {
        "gradelevel", "gradelevelname", "level", "graderank", "gradeclass",
        "scorelevel", "gradingmode", "grademode", "gradetype",
        "成绩等级", "等级", "层级", "成绩制",
    },
    "usual_grade": {
        "usualgrade", "usualscore", "normalgrade", "normalscore",
        "regulargrade", "regularscore", "dailygrade", "平时成绩", "平时",
    },
    "paper_grade": {
        "papergrade", "paperscore", "examgrade", "examscore",
        "finalexamgrade", "finalexamscore", "卷面成绩", "卷面",
        "考试成绩", "期末成绩",
    },
    "experiment_grade": {
        "experimentgrade", "experimentscore", "labgrade", "labscore",
        "practicegrade", "practicescore", "实验成绩", "实验",
    },
}


def _grade_detail_components(value: Any) -> dict[str, str]:
    """Extract common grade components from JSON, list, or display text."""
    result: dict[str, str] = {}

    def normalized_key(raw: Any) -> str:
        return re.sub(r"[\s_.:\-：]", "", str(raw)).lower()

    def store(label: Any, score: Any) -> None:
        if score in (None, ""):
            return
        key = normalized_key(label)
        for field, aliases in _GRADE_COMPONENT_ALIASES.items():
            if key in aliases:
                result.setdefault(field, str(score))

    def visit(node: Any) -> None:
        if isinstance(node, dict):
            label = next(
                (
                    node.get(key)
                    for key in (
                        "name", "label", "itemName", "typeName", "gradeTypeName"
                    )
                    if node.get(key) not in (None, "")
                ),
                None,
            )
            score = next(
                (
                    node.get(key)
                    for key in ("score", "grade", "value", "result")
                    if node.get(key) not in (None, "")
                ),
                None,
            )
            if label is not None:
                store(label, score)
            for key, item in node.items():
                store(key, item)
                if isinstance(item, (dict, list)):
                    visit(item)
        elif isinstance(node, list):
            for item in node:
                visit(item)

    parsed = value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except (TypeError, ValueError):
            for label, score in re.findall(
                r"(成绩等级|等级|层级|平时成绩|平时|卷面成绩|卷面|考试成绩|期末成绩|实验成绩|实验)\s*[：:=]\s*([^,，;；\s]+)",
                value,
            ):
                store(label, score)
            return result
    visit(parsed)
    return result

class Grade(BaseModel):
    """单门课程的成绩记录，兼容常见 EAMS 字段变体。"""

    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, frozen=True
    )

    course_name_zh: str = Field(
        default="未知课程",
        validation_alias=AliasChoices("courseNameZh", "courseName", "nameZh"),
    )
    """课程中文名称。"""
    lesson_code: str = Field(
        default="",
        validation_alias=AliasChoices("lessonCode", "courseCode", "code"),
    )
    """教学班代码。"""
    semester: GradeSemester = Field(
        default_factory=GradeSemester,
        validation_alias=AliasChoices(
            "semester", "semesterName", "term", "termName"
        ),
    )
    """成绩所属学期。"""
    passed: bool | None = Field(
        default=None,
        validation_alias=AliasChoices("passed", "isPassed"),
    )
    """是否通过；服务端未给出时为 None。"""
    final_grade: str | None = Field(
        default=None,
        validation_alias=AliasChoices("finalGrade", "score", "grade"),
    )
    """最终成绩；尚未发布时可能为空。"""
    grade_detail: str = Field(
        default="",
        validation_alias=AliasChoices("gradeDetail", "detail", "scoreDetail"),
    )
    """平时、考试等分项成绩的服务端文本。"""
    grade_level: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "gradeLevel", "gradeLevelName", "level", "gradeRank", "gradeClass",
            "scoreLevel", "gradingMode", "gradeMode", "gradeType",
            "成绩等级", "等级", "层级", "成绩制",
        ),
    )
    usual_grade: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "usualGrade", "usualScore", "normalGrade", "normalScore",
            "regularGrade", "regularScore", "dailyGrade", "平时成绩",
        ),
    )
    paper_grade: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "paperGrade", "paperScore", "examGrade", "examScore",
            "finalExamGrade", "finalExamScore", "卷面成绩", "考试成绩",
            "期末成绩",
        ),
    )
    experiment_grade: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "experimentGrade", "experimentScore", "labGrade", "labScore",
            "practiceGrade", "practiceScore", "实验成绩",
        ),
    )
    credits: float = Field(
        default=0,
        validation_alias=AliasChoices("credits", "credit"),
    )
    """课程学分。"""
    gp: float | None = Field(
        default=None,
        validation_alias=AliasChoices("gp", "gpa", "gradePoint"),
    )
    """课程绩点；尚未核算时可能为空。"""

    @model_validator(mode="before")
    @classmethod
    def normalize_nested_fields(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        normalized = dict(data)
        course = normalized.get("course")
        if isinstance(course, dict):
            course_name = (
                course.get("nameZh")
                or course.get("name")
                or course.get("courseName")
            )
            course_code = course.get("code") or course.get("courseCode")
            if course_name not in (None, ""):
                normalized.setdefault("courseNameZh", course_name)
            if course_code not in (None, ""):
                normalized.setdefault("courseCode", course_code)
        detail = next(
            (
                normalized.get(key)
                for key in ("gradeDetail", "detail", "scoreDetail")
                if normalized.get(key) not in (None, "")
            ),
            None,
        )
        for field, value in _grade_detail_components(detail).items():
            normalized.setdefault(field, value)
        return normalized

    @field_validator("course_name_zh", mode="before")
    @classmethod
    def stringify_course_name(cls, value: Any) -> str:
        return "未知课程" if value in (None, "") else str(value)

    @field_validator("lesson_code", mode="before")
    @classmethod
    def stringify_lesson_code(cls, value: Any) -> str:
        return "" if value is None else str(value)

    @field_validator("final_grade", mode="before")
    @classmethod
    def stringify_final_grade(cls, value: Any) -> str | None:
        return None if value in (None, "") else str(value)

    @field_validator(
        "grade_level", "usual_grade", "paper_grade", "experiment_grade",
        mode="before",
    )
    @classmethod
    def stringify_grade_component(cls, value: Any) -> str | None:
        if value in (None, ""):
            return None
        if isinstance(value, dict):
            for key in ("nameZh", "name", "label", "value", "score"):
                if value.get(key) not in (None, ""):
                    return str(value[key])
        return str(value)
    @field_validator("credits", mode="before")
    @classmethod
    def normalize_credits(cls, value: Any) -> Any:
        return 0 if value in (None, "") else value

    @field_validator("gp", mode="before")
    @classmethod
    def normalize_gp(cls, value: Any) -> Any:
        return None if value in (None, "") else value

    @field_validator("passed", mode="before")
    @classmethod
    def normalize_passed(cls, value: Any) -> Any:
        if value in (None, ""):
            return None
        if isinstance(value, str):
            lowered = value.strip().lower()
            if lowered in {"是", "通过", "合格", "pass", "passed", "yes", "y"}:
                return True
            if lowered in {"否", "未通过", "不合格", "fail", "failed", "no", "n"}:
                return False
            return None
        return value

    @field_validator("grade_detail", mode="before")
    @classmethod
    def stringify_detail(cls, value: Any) -> str:
        if value is None:
            return ""
        if isinstance(value, str):
            return value
        if isinstance(value, (dict, list)):
            return json.dumps(value, ensure_ascii=False)
        return str(value)


class GradeModel(BaseModel):
    """成绩查询 API 响应模型，兼容列表和分页嵌套结构。"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    result: int = 0
    message: str | None = None
    data: list[Grade] = Field(default_factory=list)

    @model_validator(mode="before")
    @classmethod
    def normalize_response(cls, data: Any) -> Any:
        def find_records(value: Any, depth: int = 0) -> list[Any] | None:
            if depth > 5:
                return None
            if isinstance(value, list):
                return value
            if not isinstance(value, dict):
                return None
            for key in ("data", "records", "rows", "content", "list", "items"):
                if key in value:
                    records = find_records(value[key], depth + 1)
                    if records is not None:
                        return records
            return None

        if isinstance(data, list):
            return {"data": data}
        if not isinstance(data, dict):
            return data
        normalized = dict(data)
        normalized["data"] = find_records(data) or []
        normalized.setdefault("result", data.get("code", 0))
        normalized.setdefault("message", data.get("msg"))
        return normalized


class Semester(BaseModel):
    """单个学期。"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    id: int
    code: str = ""
    name_zh: str
    name_en: str | None = None
    school_year: str = ""
    start_date: Date
    end_date: Date
    week_start_on_sunday: bool = False
    count_in_term: bool = True
    season: str = ""
    week_indices: list[int] = Field(default_factory=list)
    biz_types: Any | None = None

class SemesterModel(BaseModel):
    """获取全部学期数据 API 响应根模型"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    result: int
    """响应结果码"""
    message: str | None = None
    """响应消息"""
    data: list[Semester]
    """学期数据列表"""


class CurrentSemesterModel(BaseModel):
    """获取当前学期数据 API 响应根模型"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    result: int
    """响应结果码"""
    message: str | None = None
    """响应消息"""
    data: Semester
    """学期数据列表"""


class WeekIndexModel(BaseModel):
    """获取某日期的教学周序数 API 响应根模型"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    class InnerData(BaseModel):
        model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

        class NestedData(BaseModel):
            model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)
            date: List[str]
            semester: str

        msg: str
        code: int
        data: NestedData
        success: bool

    code: int
    """响应结果码"""
    message: str | None
    """响应消息"""
    data: InnerData
    """学期数据列表"""
