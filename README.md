# Openresty

The purpose of this repository is to add the Nginx OTEL module to an Openresty Docker image.

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
