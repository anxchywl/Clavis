from __future__ import annotations

import re

from app.domain.errors import ValidationError

IDEMPOTENCY_KEY_PATTERN = re.compile(r"^[A-Za-z0-9._:-]{16,128}$")


def require_idempotency_key(value: str | None) -> str:
    if value is None or IDEMPOTENCY_KEY_PATTERN.fullmatch(value) is None:
        raise ValidationError(
            "idempotency_key_invalid",
            "A valid Idempotency-Key header is required.",
        )
    return value
