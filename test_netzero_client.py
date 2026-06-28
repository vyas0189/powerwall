"""Unit tests for the shared NetZero client logic.

boto3/requests are mocked so the tests run offline with no AWS or network access.
"""

import json
import sys
import types
from unittest import mock

import pytest

# Stub boto3 before importing the module under test so that the module-level
# `boto3.client("ssm")` call doesn't require real AWS credentials/config.
_fake_boto3 = types.ModuleType("boto3")
_fake_boto3.client = mock.MagicMock()
sys.modules.setdefault("boto3", _fake_boto3)

import netzero_client  # noqa: E402

SAMPLE_CONFIG = {"backup_reserve_percent": 20, "operational_mode": "autonomous"}


@pytest.fixture(autouse=True)
def _reset_cache():
    """Each test starts with a fresh API-key cache."""
    netzero_client._api_key_cache = None
    yield
    netzero_client._api_key_cache = None


def test_missing_site_id_returns_400(monkeypatch):
    monkeypatch.delenv("SITE_ID", raising=False)
    result = netzero_client.run(SAMPLE_CONFIG, "morning")
    assert result["statusCode"] == 400
    assert "Missing SITE_ID" in json.loads(result["body"])["error"]


@pytest.mark.parametrize("bad_site_id", ["../admin", "site id", "a/b", "${x}", "a.b"])
def test_invalid_site_id_returns_400(monkeypatch, bad_site_id):
    monkeypatch.setenv("SITE_ID", bad_site_id)
    result = netzero_client.run(SAMPLE_CONFIG, "morning")
    assert result["statusCode"] == 400
    assert "Invalid SITE_ID" in json.loads(result["body"])["error"]


def test_valid_site_id_posts_and_returns_200(monkeypatch):
    monkeypatch.setenv("SITE_ID", "site-123ABC")
    monkeypatch.setattr(netzero_client, "get_api_key", lambda: "test-key")

    fake_response = mock.MagicMock()
    fake_response.raise_for_status.return_value = None

    with mock.patch.object(
        netzero_client.requests, "post", return_value=fake_response
    ) as post:
        result = netzero_client.run(SAMPLE_CONFIG, "evening")

    assert result["statusCode"] == 200
    post.assert_called_once()
    args, kwargs = post.call_args
    assert args[0] == "https://api.netzero.energy/api/v1/site-123ABC/config"
    assert kwargs["headers"]["Authorization"] == "Bearer test-key"
    assert kwargs["json"] == SAMPLE_CONFIG


def test_post_with_retry_succeeds_after_transient_failure(monkeypatch):
    monkeypatch.setattr(netzero_client.time, "sleep", lambda _s: None)

    failing = mock.MagicMock()
    failing.raise_for_status.side_effect = (
        netzero_client.requests.exceptions.RequestException("boom")
    )
    ok = mock.MagicMock()
    ok.raise_for_status.return_value = None

    with mock.patch.object(
        netzero_client.requests, "post", side_effect=[failing, ok]
    ) as post:
        result = netzero_client.post_with_retry("http://x", {}, {})

    assert result is ok
    assert post.call_count == 2


def test_post_with_retry_raises_after_exhausting_attempts(monkeypatch):
    monkeypatch.setattr(netzero_client.time, "sleep", lambda _s: None)

    failing = mock.MagicMock()
    failing.raise_for_status.side_effect = (
        netzero_client.requests.exceptions.RequestException("boom")
    )

    with mock.patch.object(
        netzero_client.requests, "post", return_value=failing
    ) as post:
        with pytest.raises(netzero_client.requests.exceptions.RequestException):
            netzero_client.post_with_retry("http://x", {}, {})

    assert post.call_count == netzero_client.MAX_RETRIES


def test_get_api_key_caches(monkeypatch):
    fake_ssm = mock.MagicMock()
    fake_ssm.get_parameter.return_value = {"Parameter": {"Value": "secret-key"}}
    monkeypatch.setattr(netzero_client, "_ssm_client", fake_ssm)

    assert netzero_client.get_api_key() == "secret-key"
    assert netzero_client.get_api_key() == "secret-key"
    fake_ssm.get_parameter.assert_called_once()


def test_get_api_key_logs_and_reraises_on_ssm_error(monkeypatch):
    fake_ssm = mock.MagicMock()
    fake_ssm.get_parameter.side_effect = RuntimeError("denied")
    monkeypatch.setattr(netzero_client, "_ssm_client", fake_ssm)

    with pytest.raises(RuntimeError):
        netzero_client.get_api_key()
