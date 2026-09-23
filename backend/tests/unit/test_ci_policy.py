from __future__ import annotations

import re
from pathlib import Path

WORKFLOWS = Path(__file__).parents[3] / ".github" / "workflows"
ACTION_REFERENCE = re.compile(r"uses:\s+([^\s]+)@([^\s#]+)")
COMMIT_SHA = re.compile(r"^[0-9a-f]{40}$")

CREDENTIAL_DEFINE = re.compile(r"--dart-define=\w*(TOKEN|SECRET|PASSWORD)\w*=")


def _workflows() -> list[Path]:
    return sorted(WORKFLOWS.glob("*.yml"))


def test_workflows_exist() -> None:
    assert _workflows()


def test_every_action_is_pinned_to_a_commit() -> None:
    for workflow in _workflows():
        references = ACTION_REFERENCE.findall(workflow.read_text())
        assert references, f"{workflow.name} references no action"
        for name, reference in references:
            assert COMMIT_SHA.fullmatch(reference), (
                f"{workflow.name} pins {name} to {reference}; use a commit SHA "
                "so a retagged upstream action cannot change what runs"
            )


def test_workflows_declare_least_privilege_permissions() -> None:
    for workflow in _workflows():
        assert "permissions:" in workflow.read_text(), (
            f"{workflow.name} inherits the default token scope"
        )


def test_scanner_downloads_are_checksum_verified() -> None:
    ci = (WORKFLOWS / "ci.yml").read_text()
    assert ci.count("sha256sum --check") >= 2


def test_secret_and_dependency_scanning_run() -> None:
    ci = (WORKFLOWS / "ci.yml").read_text()
    assert "gitleaks detect" in ci
    assert "fetch-depth: 0" in ci
    assert "osv-scanner" in ci


def test_no_workflow_bakes_a_credential_into_a_build() -> None:
    # a --dart-define is recoverable from the binary, a predecessor shipped a token
    for workflow in _workflows():
        found = CREDENTIAL_DEFINE.findall(workflow.read_text())
        assert not found, (
            f"{workflow.name} passes a credential as a build define: {found}"
        )


def test_no_workflow_enables_standalone_release_access() -> None:
    for workflow in _workflows():
        text = workflow.read_text()
        assert "ENABLE_DEV_ACCESS=true" not in text, workflow.name
        assert "PIANO_BACKEND=remote" not in text, workflow.name


def _deployment_workflows() -> list[Path]:
    # a workflow that names a github environment is one that ships something.
    # matching on the word "deploy" also caught the job that only validates
    # deployment configuration, which ships nothing and pins no revision
    return [w for w in _workflows() if "environment:" in w.read_text()]


def test_deployment_uses_the_tested_revision() -> None:
    for workflow in _deployment_workflows():
        text = workflow.read_text()
        assert "github.sha" in text, (
            f"{workflow.name} must pin the revision CI actually tested"
        )


def test_deployment_refuses_a_revision_ci_has_not_passed() -> None:
    # a pinned revision that nobody tested is still an untested deployment
    for workflow in _deployment_workflows():
        if "ssh" not in workflow.read_text():
            continue
        assert "conclusion" in workflow.read_text(), (
            f"{workflow.name} must check the ci conclusion before shipping"
        )


def test_deployment_verifies_the_host_it_connects_to() -> None:
    # an unverified host key is the ssh equivalent of skipping certificate
    # checks, and this project refuses that in every other place
    for workflow in _deployment_workflows():
        text = workflow.read_text()
        if "ssh" not in text:
            continue
        assert "StrictHostKeyChecking=no" not in text, workflow.name
        assert "UserKnownHostsFile=/dev/null" not in text, workflow.name
        assert "known_hosts" in text, (
            f"{workflow.name} must pin the host keys it will accept"
        )
