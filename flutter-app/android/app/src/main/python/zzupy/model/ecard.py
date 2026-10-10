from typing import Any

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel


class ECardTemplate(BaseModel):
    """一卡通模板项"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    code: str
    name: str | None = None
    name_english: str | None = None
    show: bool | None = None
    unit: str | None = None
    unit_english: str | None = None
    value: str | int | float | None = None


class ECardAccountData(BaseModel):
    """一卡通账户数据"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    acc_status: str | None = None
    acc_status_name: str | None = None
    account_num: Any | None = None
    balance: str | int | float | None = None
    network_package_list: list[Any] | None = None
    support_details: bool | None = None
    template_list: list[ECardTemplate] = Field(default_factory=list)
    utility_account: str | None = None
    utility_status: str | None = None
    utility_status_name: str | None = None
    utility_username: str | None = None

    @property
    def remaining_energy(self) -> float | None:
        for template in self.template_list:
            if template.code == "quantity" and template.value is not None:
                return float(template.value)
        return None


class ECardAccountModel(BaseModel):
    """一卡通账户 API 响应根模型"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    code: str | int | None = None
    message: str | None = None
    result_data: ECardAccountData
    success: bool | None = None

    @property
    def remaining_energy(self) -> float | None:
        return self.result_data.remaining_energy
