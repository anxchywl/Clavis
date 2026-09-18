from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol


class AccountStatus(StrEnum):
    active = "active"
    suspended = "suspended"


@dataclass(frozen=True, slots=True)
class ExternalIdentity:
    # nothing here is ever read from a request body, role included
    external_issuer: str
    external_subject: str
    account_status: AccountStatus
    display_name: str | None = None
    is_operator: bool = False


class TokenIdentityResolver(Protocol):
    async def resolve(self, token: str) -> ExternalIdentity: ...
