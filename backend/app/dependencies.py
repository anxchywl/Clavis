from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Header, Request

from app.domain.auth import AccountStatus, ExternalIdentity, TokenIdentityResolver
from app.domain.errors import ForbiddenError, UnauthorizedError


async def require_identity(
    request: Request,
    authorization: Annotated[str | None, Header()] = None,
) -> ExternalIdentity:
    if not authorization or not authorization.startswith("Bearer "):
        raise UnauthorizedError("token_missing", "Authentication is required.")
    resolver: TokenIdentityResolver = request.app.state.principal_resolver
    identity = await resolver.resolve(authorization.removeprefix("Bearer ").strip())
    if identity.account_status is AccountStatus.suspended:
        raise ForbiddenError("account_suspended", "This account is suspended.")
    return identity


async def require_operator(
    identity: Annotated[ExternalIdentity, Depends(require_identity)],
) -> ExternalIdentity:
    # rechecked here rather than trusted from anything the client sent
    if not identity.is_operator:
        raise ForbiddenError("operator_required", "Operator access is required.")
    return identity


CurrentIdentity = Annotated[ExternalIdentity, Depends(require_identity)]
OperatorIdentity = Annotated[ExternalIdentity, Depends(require_operator)]
