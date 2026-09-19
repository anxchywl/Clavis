from __future__ import annotations

import ast
from pathlib import Path

APP = Path(__file__).parents[2] / "app"


def _imports_in(directory: Path) -> list[tuple[Path, str]]:
    found: list[tuple[Path, str]] = []
    for path in directory.rglob("*.py"):
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                found.extend((path, alias.name) for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                found.append((path, node.module))
    return found


def _assert_no_import(directory: Path, forbidden: str, *, because: str) -> None:
    offenders = [
        f"{path.relative_to(APP.parent)}: {module}"
        for path, module in _imports_in(directory)
        if module == forbidden or module.startswith(f"{forbidden}.")
    ]
    assert not offenders, f"{because}\n" + "\n".join(offenders)


def test_domain_is_pure() -> None:
    for package in ("fastapi", "starlette", "sqlite3", "pydantic_settings", "httpx"):
        _assert_no_import(
            APP / "domain",
            package,
            because=(
                "domain describes rules, not how they arrive or are stored, so "
                "it can be tested without a framework"
            ),
        )


def test_domain_does_not_depend_on_the_layers_above_it() -> None:
    for layer in ("app.api", "app.infrastructure", "app.application", "app.config"):
        _assert_no_import(APP / "domain", layer, because="dependencies point one way")


def test_application_does_not_import_the_web_layer() -> None:
    _assert_no_import(
        APP / "application",
        "app.api",
        because="use cases are callable without an HTTP request",
    )


def test_application_does_not_import_the_store() -> None:
    _assert_no_import(
        APP / "application",
        "app.infrastructure",
        because="use cases name the store by its protocol, not its engine",
    )


def test_api_does_not_reach_into_persistence() -> None:
    _assert_no_import(
        APP / "api",
        "app.infrastructure",
        because="a router that names the store has taken a persistence decision "
        "that belongs in the application layer",
    )
