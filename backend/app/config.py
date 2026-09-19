from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from functools import lru_cache
from typing import Annotated
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class AppEnvironment(StrEnum):
    development = "development"
    test = "test"
    production = "production"


# "none" is never here, and neither is any algorithm the issuer has not agreed
HOST_ALGORITHMS = frozenset(
    {"RS256", "RS384", "RS512", "ES256", "ES384", "ES512", "HS256", "HS384", "HS512"}
)


class AuthAdapter(StrEnum):
    host = "host"
    development = "development"


class Settings(BaseSettings):
    # the environment is authoritative and defaults to strict, so it fails closed
    environment: AppEnvironment = Field(
        default=AppEnvironment.production,
        alias="APP_ENV",
    )
    auth_adapter: AuthAdapter = Field(default=AuthAdapter.host, alias="AUTH_ADAPTER")

    development_auth_token: SecretStr | None = Field(
        default=None,
        alias="DEVELOPMENT_AUTH_TOKEN",
    )
    development_auth_subject: str = Field(
        default="student-a",
        alias="DEVELOPMENT_AUTH_SUBJECT",
        min_length=1,
        max_length=255,
    )
    development_operator_auth_token: SecretStr | None = Field(
        default=None,
        alias="DEVELOPMENT_OPERATOR_AUTH_TOKEN",
    )
    development_operator_auth_subject: str = Field(
        default="operator-a",
        alias="DEVELOPMENT_OPERATOR_AUTH_SUBJECT",
        min_length=1,
        max_length=255,
    )
    # a frozen instant, so the one-hour sunday window can be tried on any day
    development_clock: datetime | None = Field(
        default=None,
        alias="DEVELOPMENT_CLOCK",
    )

    # the host issues the token, this service only verifies it. with no
    # issuer and no key the host resolver stays closed rather than open
    host_jwt_issuer: str | None = Field(default=None, alias="HOST_JWT_ISSUER")
    host_jwt_audience: str | None = Field(
        default=None,
        alias="HOST_JWT_AUDIENCE",
    )
    host_jwt_algorithm: str = Field(
        default="RS256",
        alias="HOST_JWT_ALGORITHM",
    )
    host_jwt_public_key: str | None = Field(
        default=None,
        alias="HOST_JWT_PUBLIC_KEY",
    )
    host_jwt_secret: SecretStr | None = Field(
        default=None,
        alias="HOST_JWT_SECRET",
    )
    host_subject_claim: str = Field(
        default="sub",
        alias="HOST_SUBJECT_CLAIM",
        min_length=1,
        max_length=64,
    )
    host_operator_claim: str | None = Field(
        default=None,
        alias="HOST_OPERATOR_CLAIM",
    )
    host_operator_value: str | None = Field(
        default=None,
        alias="HOST_OPERATOR_VALUE",
    )

    # one file on a mounted volume; ":memory:" keeps a test run off the disk
    database_path: str = Field(
        default="/data/clavis.sqlite3",
        alias="DATABASE_PATH",
        min_length=1,
    )

    # NoDecode keeps the settings source from json-parsing this before the
    # validator sees it: a list field arriving from the environment is decoded
    # as json by default, and an empty CORS_ALLOWED_ORIGINS= is not valid json
    cors_allowed_origins: Annotated[list[str], NoDecode] = Field(
        default_factory=list,
        alias="CORS_ALLOWED_ORIGINS",
    )
    api_docs_enabled: bool = Field(default=False, alias="API_DOCS_ENABLED")
    # a booking body is a slot id; nothing this service accepts is larger
    request_body_max_bytes: int = Field(
        default=16_384,
        alias="REQUEST_BODY_MAX_BYTES",
        ge=1_024,
        le=1_024 * 1_024,
    )

    @property
    def host_auth_configured(self) -> bool:
        has_key = bool(self.host_jwt_public_key) or (self.host_jwt_secret is not None)
        return bool(self.host_jwt_issuer) and has_key

    # an unset variable reaches here from a .env file as an empty string,
    # which means "the real clock" rather than "a time that failed to parse"
    @field_validator("development_clock", mode="before")
    @classmethod
    def _empty_clock_is_unset(cls, value: object) -> object:
        return None if value == "" else value

    @field_validator("development_clock")
    @classmethod
    def _clock_has_an_offset(cls, value: datetime | None) -> datetime | None:
        if value is not None and value.tzinfo is None:
            raise ValueError("DEVELOPMENT_CLOCK must include a UTC offset")
        return value

    @field_validator("cors_allowed_origins", mode="before")
    @classmethod
    def parse_origins(cls, value: object) -> list[str]:
        if value is None:
            return []
        if isinstance(value, list):
            return [str(origin).strip() for origin in value if str(origin).strip()]
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        raise ValueError("CORS_ALLOWED_ORIGINS must be a comma-separated list")

    @model_validator(mode="after")
    def guard_development_features(self) -> Settings:
        production = self.environment == AppEnvironment.production
        if self.auth_adapter == AuthAdapter.development:
            if production:
                raise ValueError("development authentication cannot run in production")
            if self.development_auth_token is None:
                raise ValueError(
                    "DEVELOPMENT_AUTH_TOKEN is required for development authentication"
                )
            if self.development_operator_auth_token is None:
                raise ValueError(
                    "DEVELOPMENT_OPERATOR_AUTH_TOKEN is required for "
                    "development authentication"
                )
            if (
                self.development_auth_token.get_secret_value()
                == self.development_operator_auth_token.get_secret_value()
            ):
                raise ValueError("development student and operator tokens must differ")
        if production and self.development_clock is not None:
            raise ValueError("DEVELOPMENT_CLOCK cannot be set in production")
        if production and self.api_docs_enabled:
            raise ValueError("API documentation cannot be enabled in production")
        if "*" in self.cors_allowed_origins:
            raise ValueError("wildcard CORS origins are not allowed")
        for origin in self.cors_allowed_origins:
            parsed = urlsplit(origin)
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.netloc
                or parsed.username is not None
                or parsed.password is not None
                or parsed.path
                or parsed.query
                or parsed.fragment
            ):
                raise ValueError("CORS origins must be HTTP origins without paths")
            if production and parsed.scheme != "https":
                raise ValueError("CORS origins must use HTTPS in production")
        if self.host_auth_configured:
            algorithm = self.host_jwt_algorithm.upper()
            if algorithm not in HOST_ALGORITHMS:
                raise ValueError("HOST_JWT_ALGORITHM is not an allowed algorithm")
            # an rsa public key handed to an hmac verifier is the classic
            # algorithm-confusion forgery, so the family must match the material
            if algorithm.startswith("HS"):
                if self.host_jwt_public_key:
                    raise ValueError(
                        "HOST_JWT_PUBLIC_KEY cannot be used with an HS algorithm"
                    )
                secret = self.host_jwt_secret
                if secret is None:
                    raise ValueError("HOST_JWT_SECRET is required for an HS algorithm")
                if len(secret.get_secret_value().encode()) < 32:
                    raise ValueError(
                        "HOST_JWT_SECRET must be at least 32 bytes for an HS algorithm"
                    )
            elif not self.host_jwt_public_key:
                raise ValueError(
                    "HOST_JWT_PUBLIC_KEY is required for an asymmetric algorithm"
                )
            if bool(self.host_operator_claim) != bool(self.host_operator_value):
                raise ValueError(
                    "HOST_OPERATOR_CLAIM and HOST_OPERATOR_VALUE are set "
                    "together or not at all"
                )
        return self

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        populate_by_name=True,
    )


@lru_cache
def get_settings() -> Settings:
    return Settings.model_validate({})
