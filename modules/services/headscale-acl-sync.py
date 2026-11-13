#!/usr/bin/env python3
import json
import logging
import os
import signal
import socket
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


LOG = logging.getLogger("headscale-acl-sync")


class SyncError(Exception):
    pass


def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError) as error:
        raise SyncError(f"unable to read JSON file {path}: {error}") from error


def http_json(url, headers, unix_socket=None, timeout=15):
    if unix_socket is None:
        request = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.load(response)
        except (OSError, urllib.error.HTTPError, ValueError) as error:
            raise SyncError(f"request to {url} failed: {error}") from error

    parsed = urllib.parse.urlsplit(url)
    path = parsed.path or "/"
    if parsed.query:
        path += f"?{parsed.query}"
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {parsed.hostname or 'localhost'}\r\n"
        + "".join(f"{key}: {value}\r\n" for key, value in headers.items())
        + "Connection: close\r\n\r\n"
    ).encode()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(timeout)
            connection.connect(unix_socket)
            connection.sendall(request)
            response = b""
            while True:
                chunk = connection.recv(65536)
                if not chunk:
                    break
                response += chunk
    except OSError as error:
        raise SyncError(f"request to {url} failed: {error}") from error

    try:
        header, body = response.split(b"\r\n\r\n", 1)
        status = int(header.splitlines()[0].split()[1])
        if status < 200 or status >= 300:
            raise SyncError(f"request to {url} returned HTTP {status}")
        return json.loads(body)
    except (ValueError, json.JSONDecodeError) as error:
        raise SyncError(f"invalid JSON response from {url}: {error}") from error


def read_token(path):
    try:
        token = Path(path).read_text().strip()
    except OSError as error:
        raise SyncError(f"unable to read Authentik token: {error}") from error
    if not token:
        raise SyncError("Authentik token is empty")
    return token


def get_authentik_members(config, token):
    url = (
        f"{config['authentik_url'].rstrip('/')}/api/v3/core/groups/"
        f"{config['group_uuid']}/?include_users=true"
    )
    group = http_json(url, {"Authorization": f"Bearer {token}"})
    members = group.get("users_obj")
    if not isinstance(members, list):
        raise SyncError("Authentik group response did not contain users_obj")
    active = []
    for member in members:
        if not member.get("is_active", False):
            LOG.warning("Skipping disabled Authentik administrator %s", member.get("pk", "<unknown>"))
            continue
        uuid = member.get("uid") or member.get("uuid")
        if not uuid:
            raise SyncError("Authentik administrator has no stable UUID")
        active.append(str(uuid))
    if len(active) != len(set(active)):
        raise SyncError("Authentik group contains duplicate administrator identities")
    return active


def get_headscale_users(config):
    response = http_json(
        "http://localhost/api/v1/user",
        {},
        unix_socket=config["headscale_socket"],
    )
    users = response.get("users")
    if not isinstance(users, list):
        raise SyncError("Headscale response did not contain users")
    return users


def resolve_users(config, authentik_ids, headscale_users):
    prefix = config["oidc_issuer"].rstrip("/") + "/"
    by_identifier = {}
    for user in headscale_users:
        identifier = (user.get("providerId") or user.get("providerIdentifier") or user.get("provider_identifier"))
        if identifier:
            if identifier in by_identifier:
                raise SyncError(f"duplicate Headscale provider identifier {identifier}")
            by_identifier[identifier] = user

    resolved = []
    for authentik_id in authentik_ids:
        identifier = prefix + authentik_id
        user = by_identifier.get(identifier)
        if user is None:
            raise SyncError(f"no Headscale user mapping for Authentik user {authentik_id}")
        login_name = user.get("loginName") or user.get("name")
        if not login_name:
            raise SyncError(f"Headscale mapping for Authentik user {authentik_id} has no name")
        resolved.append(login_name + "@")
    if len(resolved) != len(set(resolved)):
        raise SyncError("multiple Authentik administrators map to one Headscale identity")
    return sorted(resolved)


def render_policy(static_policy, administrators):
    policy = json.loads(json.dumps(static_policy))
    groups = policy.setdefault("groups", {})
    groups["group:tailscale_admins"] = administrators
    return json.dumps(policy, indent=2, sort_keys=True) + "\n"


def atomic_install(path, content):
    destination = Path(path)
    destination.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    old = destination.read_bytes() if destination.exists() else None
    if old == content.encode():
        return old
    fd, temporary = tempfile.mkstemp(prefix=".policy.", dir=destination.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o640)
        os.replace(temporary, destination)
    except OSError as error:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise SyncError(f"installing policy failed: {error}") from error
    return old


def validate_policy(config, path):
    try:
        subprocess.run(
            config["validation_command"] + [path],
            check=True,
            timeout=30,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    except (OSError, subprocess.SubprocessError) as error:
        detail = getattr(error, "stderr", None)
        suffix = f": {detail.strip()}" if detail else ""
        raise SyncError(f"generated policy failed validation{suffix}") from error


def reload_headscale(config):
    try:
        result = subprocess.run(
            config["headscale_pid_command"],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        pid = int(result.stdout.strip())
        if pid <= 1:
            raise SyncError(f"invalid Headscale PID {pid}")
        os.kill(pid, signal.SIGHUP)
    except (OSError, ValueError, subprocess.SubprocessError, SyncError) as error:
        raise SyncError(f"Headscale policy reload failed: {error}") from error


def restore_policy(path, old):
    if old is None:
        try:
            Path(path).unlink()
        except OSError as error:
            raise SyncError(f"unable to remove failed initial policy: {error}") from error
        return
    atomic_install(path, old.decode())


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    config = read_json(os.environ["HEADSCALE_ACL_SYNC_CONFIG"])
    token = read_token(os.environ["AUTHENTIK_TOKEN_FILE"])
    LOG.info("Starting Authentik -> Headscale ACL synchronization")
    administrator_ids = get_authentik_members(config, token)
    LOG.info("Retrieved %d active members from tailscale_admins", len(administrator_ids))
    users = get_headscale_users(config)
    administrators = resolve_users(config, administrator_ids, users)
    LOG.info("Resolved %d Authentik identities to Headscale users", len(administrators))
    policy = render_policy(read_json(config["static_policy"]), administrators)
    temporary_directory = str(Path(config["policy_path"]).parent)
    fd, temporary = tempfile.mkstemp(prefix=".validated-policy.", dir=temporary_directory)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(policy)
            output.flush()
            os.fsync(output.fileno())
        validate_policy(config, temporary)
        old = atomic_install(config["policy_path"], policy)
    finally:
        try:
            os.unlink(temporary)
        except OSError:
            pass
    if old is None and not Path(config["policy_path"]).exists():
        raise SyncError("policy installation did not produce a policy file")
    if old is not None and old.decode() == policy:
        LOG.info("Policy unchanged; skipping reload")
        return
    if old is None and policy.encode() == Path(config["policy_path"]).read_bytes():
        changed = True
    else:
        changed = old is None or old.decode() != policy
    if not changed:
        LOG.info("Policy unchanged; skipping reload")
        return
    LOG.info("Generated policy successfully; reloading Headscale")
    try:
        reload_headscale(config)
    except SyncError:
        LOG.error("Headscale reload failed; restoring the last known-good policy")
        restore_policy(config["policy_path"], old)
        raise


if __name__ == "__main__":
    try:
        main()
    except (KeyError, SyncError) as error:
        LOG.error("%s", error)
        raise SystemExit(1)
