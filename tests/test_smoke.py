import subprocess
import time
import urllib.request
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGE_NAME = "openresty-smoke-test"
CONTAINER_NAME = "openresty-smoke-test"
NGINX_CONF_DIR = "/usr/local/openresty/nginx/conf"

CONFIG_MOUNTS = [
    "--volume", f"{REPO_ROOT / 'nginx.conf'}:{NGINX_CONF_DIR}/nginx.conf:ro",
    "--volume", f"{REPO_ROOT / 'http.js'}:{NGINX_CONF_DIR}/http.js:ro",
]


def docker(*args):
    command = ["docker", *args]
    result = subprocess.run(command, capture_output=True, text=True)
    # OpenResty prints `-V` and `-t` results to stderr, not stdout.
    output = result.stdout + result.stderr
    if result.returncode != 0:
        pytest.fail(f"Command failed: {' '.join(command)}\n{output}")
    return output


def run_in_image(*command):
    return docker("run", "--rm", *CONFIG_MOUNTS, IMAGE_NAME, *command)


def http_get(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        return response.read().decode()


def dockerfile_arg_default(name):
    prefix = f"ARG {name}="
    for line in (REPO_ROOT / "Dockerfile").read_text().splitlines():
        if line.startswith(prefix):
            return line[len(prefix):]
    raise ValueError(f"No default for ARG {name} in the Dockerfile")


@pytest.fixture(scope="session", autouse=True)
def image():
    docker("build", "--tag", IMAGE_NAME, str(REPO_ROOT))


@pytest.fixture(scope="session")
def server():
    docker("rm", "--force", CONTAINER_NAME)

    # "127.0.0.1::80" publishes port 80 on a random free host port.
    docker(
        "run", "--detach",
        "--name", CONTAINER_NAME,
        "--publish", "127.0.0.1::80",
        *CONFIG_MOUNTS,
        IMAGE_NAME,
    )

    host_and_port = docker("port", CONTAINER_NAME, "80/tcp").strip()
    base_url = f"http://{host_and_port}"

    wait_until_responding(base_url)
    yield base_url

    docker("rm", "--force", CONTAINER_NAME)


def wait_until_responding(url, timeout_seconds=10):
    deadline = time.time() + timeout_seconds
    while True:
        try:
            http_get(url)
            return
        except OSError:
            if time.time() > deadline:
                logs = docker("logs", CONTAINER_NAME)
                pytest.fail(f"OpenResty did not respond at {url}.\nContainer logs:\n{logs}")
            time.sleep(0.5)


def test_openresty_version_matches_dockerfile():
    expected_version = dockerfile_arg_default("OPENRESTY_VERSION")

    output = run_in_image("openresty", "-V")

    assert f"openresty/{expected_version}" in output


def test_static_modules_are_compiled_in():
    output = run_in_image("openresty", "-V")

    assert "ngx_lua" in output
    assert "nginx-module-vts" in output


def test_luajit_runs():
    output = run_in_image("/usr/local/openresty/luajit/bin/luajit", "-v")

    assert "LuaJIT" in output


def test_config_loads_all_dynamic_modules():
    # nginx.conf load_module's njs, OTel and XSLT, so this also catches a missing
    # .so file or a shared library missing from the runtime image.
    output = run_in_image("openresty", "-t")

    assert "test is successful" in output


def test_njs_handles_requests(server):
    assert http_get(server) == "Hello world!"


def test_vts_status_page(server):
    body = http_get(f"{server}/status")

    assert "nginx_vts_info" in body


def test_otel_exports_traces(server):
    # No collector runs during the tests, so the expected sign of a working
    # module is an "export failure" in the logs.
    http_get(server)

    deadline = time.time() + 15  # the module exports in batches, every few seconds
    while time.time() < deadline:
        if "OTel export failure" in docker("logs", CONTAINER_NAME):
            return
        time.sleep(1)

    pytest.fail("No OTel export attempt in the container logs within 15 seconds")
