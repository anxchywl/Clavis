from __future__ import annotations

import re
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHttpException
from starlette.responses import Response

from app.api.errors import (
    error_response,
    handle_app_error,
    handle_http_error,
    handle_unexpected_error,
    handle_validation_error,
)
from app.api.router import router
from app.config import AppEnvironment, Settings, get_settings
from app.domain.errors import AppError
from app.infrastructure.auth import create_principal_resolver
from app.infrastructure.services import create_booking_service

REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
BODY_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


def create_app(settings: Settings | None = None) -> FastAPI:
    active_settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(application: FastAPI) -> AsyncIterator[None]:
        application.state.principal_resolver = create_principal_resolver(
            active_settings
        )
        service, close = create_booking_service(active_settings)
        application.state.booking_service = service
        yield
        close()

    application = FastAPI(
        title="Clavis API",
        version="0.1.0",
        docs_url="/documentation" if active_settings.api_docs_enabled else None,
        redoc_url=None,
        openapi_url="/openapi.json" if active_settings.api_docs_enabled else None,
        lifespan=lifespan,
    )
    application.state.settings = active_settings
    application.add_middleware(
        CORSMiddleware,
        allow_origins=active_settings.cors_allowed_origins,
        # bearer tokens, so no cookie ever needs to cross an origin
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=[
            "Authorization",
            "Content-Type",
            "Idempotency-Key",
            "X-Request-ID",
        ],
        expose_headers=["Idempotent-Replayed", "X-Request-ID"],
    )

    @application.middleware("http")
    async def request_context(
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        supplied = request.headers.get("X-Request-ID", "")
        request_id = (
            supplied if REQUEST_ID_PATTERN.fullmatch(supplied) else str(uuid4())
        )
        request.state.request_id = request_id

        if request.method in BODY_METHODS:
            limit = active_settings.request_body_max_bytes
            content_length = request.headers.get("Content-Length")
            if (
                content_length is not None
                and content_length.isdigit()
                and int(content_length) > limit
            ):
                return error_response(
                    request,
                    status_code=413,
                    code="request_body_too_large",
                    message="The request body is too large.",
                )
            # a declared Content-Length can lie, so count what actually arrives
            chunks: list[bytes] = []
            received = 0
            async for chunk in request.stream():
                received += len(chunk)
                if received > limit:
                    return error_response(
                        request,
                        status_code=413,
                        code="request_body_too_large",
                        message="The request body is too large.",
                    )
                chunks.append(chunk)
            request._body = b"".join(chunks)  # noqa: SLF001

        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        if request.url.path.startswith("/api/"):
            response.headers["Cache-Control"] = "private, no-store"
        if active_settings.environment == AppEnvironment.production:
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains"
            )
        return response

    application.add_exception_handler(AppError, handle_app_error)  # type: ignore[arg-type]
    application.add_exception_handler(
        RequestValidationError,
        handle_validation_error,  # type: ignore[arg-type]
    )
    application.add_exception_handler(
        StarletteHttpException,
        handle_http_error,  # type: ignore[arg-type]
    )
    application.add_exception_handler(Exception, handle_unexpected_error)
    application.include_router(router)
    return application
