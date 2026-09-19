from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHttpException

from app.domain.errors import AppError


def request_id_of(request: Request) -> str:
    value = getattr(request.state, "request_id", None)
    return value if isinstance(value, str) else "unknown"


def error_response(
    request: Request,
    *,
    status_code: int,
    code: str,
    message: str,
    details: dict[str, Any] | list[Any] | None = None,
    extra_headers: dict[str, str] | None = None,
) -> JSONResponse:
    error: dict[str, Any] = {
        "code": code,
        "message": message,
        "request_id": request_id_of(request),
    }
    if details is not None:
        error["details"] = details
    headers = {
        "X-Request-ID": request_id_of(request),
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
    }
    if request.url.path.startswith("/api/"):
        headers["Cache-Control"] = "private, no-store"
    if extra_headers:
        headers.update(extra_headers)
    return JSONResponse(
        status_code=status_code,
        content={"error": error},
        headers=headers,
    )


async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
    return error_response(
        request,
        status_code=exc.status_code,
        code=exc.code,
        message=exc.message,
        details=exc.details,
        extra_headers=exc.headers,
    )


async def handle_validation_error(
    request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    # locations and types only, echoing values would put user input into logs
    details = [
        {"location": [str(part) for part in error["loc"]], "type": error["type"]}
        for error in exc.errors()
    ]
    return error_response(
        request,
        status_code=422,
        code="request_validation_failed",
        message="The request is not valid.",
        details=details,
    )


async def handle_http_error(
    request: Request,
    exc: StarletteHttpException,
) -> JSONResponse:
    return error_response(
        request,
        status_code=exc.status_code,
        code="http_error",
        message=str(exc.detail),
    )


async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
    # a stack trace, a SQL fragment or an upstream message must never reach a client
    return error_response(
        request,
        status_code=500,
        code="internal_error",
        message="The request could not be completed.",
    )
