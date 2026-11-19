# Openresty

The purpose of this repository is to add the Nginx OTEL module to an Openresty Docker image.

## OpenResty source

The Dockerfile can get the OpenResty source tarball in two ways, chosen with the `OPENRESTY_SOURCE` build arg:

- `git` (current default): builds the tarball from a pinned commit (`OPENRESTY_GIT_REF`) of
  [openresty/openresty](https://github.com/openresty/openresty) by running its `make` (`util/mirror-tarballs`).
  Use this when nginx security fixes are on OpenResty's master branch but not yet in an official release.
  `OPENRESTY_VERSION` must match `util/ver` at that commit, or the build fails.
- `release`: downloads the official `openresty-${OPENRESTY_VERSION}.tar.gz` from openresty.org.

To verify the nginx version in a built image:
```
docker compose run --rm openresty openresty -V
```

## Smoke tests

[pytest](https://docs.pytest.org/) tests in `tests/` build the image and check that OpenResty, LuaJIT,
njs, OTel, VTS and XSLT are built and work with this repo's `nginx.conf` and `http.js`.

Prerequisites: Docker and Python 3 with `venv` (on Debian/Ubuntu: `sudo apt install python3-venv`).

```
python3 -m venv .venv
.venv/bin/pip install -r requirements-test.txt
.venv/bin/python -m pytest -v
```

## Local testing

1. Prerequisites:
    - Docker and Docker Compose
1. In a terminal window, start the Openresty container:
    ```
    docker compose up
    ```
1. In a new terminal window, send a request to the container:
    ```
    curl localhost
    ```
1. Observe the logs from the Openresty container. The purpose of this test is to verify the OTEL module starts.
    ```
    docker compose up
    ...
    Attaching to openresty-1
    openresty-1  | 172.18.0.1 - - [21/Jul/2025:14:09:01 +0000] "GET / HTTP/1.1" 200 13 "-" "curl/8 5.0"
    openresty-1  | 2025/07/21 14:09:04 [error] 7#11: OTel export failure: failed to connect to all addresses; last error: UNKNOWN: Failed to connect to remote host: Connection refused
    ```
    An OTEL export failure is expected since no OTEL collector has been setup, but it indicates the module is functioning correctly.
