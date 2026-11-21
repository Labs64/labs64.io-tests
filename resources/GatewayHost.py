"""Reach a gateway by address while the routes match its name.

An environment's HTTPRoutes match only their public host (for example ``gateway.example.com``). A run that reaches the
gateway through a ``kubectl port-forward`` (``GATEWAY_BASE_URL=http://localhost:8000``) sends ``Host: localhost:8000``,
and Traefik answers ``404 page not found`` to every call.

Set ``GATEWAY_HOST_HEADER`` to the route host and every request to ``GATEWAY_BASE_URL`` carries it as ``Host``.
Requests to any other address (Keycloak, the PSP stub) and requests that set their own ``Host`` (the Keycloak token call
with ``KEYCLOAK_ROUTE_HOST``) are left alone. Unset, nothing changes.

The header is added where every request passes, ``requests.Session.request``, because the suites create sessions in many
places (the shared keywords, and a few cases that build their own, in several repositories).
"""

import os
from urllib.parse import urlsplit

import requests

_DEFAULT_BASE_URL = "http://gateway.localhost"
_original_request = requests.Session.request


def gateway_host_header() -> str:
    """The Host header sent to the gateway, empty when not overridden."""
    return os.environ.get("GATEWAY_HOST_HEADER", "").strip()


def _to_gateway(url) -> bool:
    base = os.environ.get("GATEWAY_BASE_URL", _DEFAULT_BASE_URL)
    return urlsplit(str(url)).netloc == urlsplit(base).netloc


def _request(self, method, url, **kwargs):
    host = gateway_host_header()
    if host and _to_gateway(url):
        headers = dict(kwargs.get("headers") or {})
        if not any(name.lower() == "host" for name in headers):
            headers["Host"] = host
        kwargs["headers"] = headers
    return _original_request(self, method, url, **kwargs)


if requests.Session.request is _original_request:
    requests.Session.request = _request
