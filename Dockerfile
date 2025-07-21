# https://github.com/nginxinc/nginx-otel
ARG OPENRESTY_TAG=1.27.1.2-2-bookworm-fat
FROM openresty/openresty:${OPENRESTY_TAG} AS builder
RUN apt update && \
    apt upgrade -y && \
    apt install -y cmake build-essential libssl-dev zlib1g-dev libpcre3-dev pkg-config libc-ares-dev libre2-dev git && \
    git clone https://github.com/nginx/nginx.git && \
    cd nginx && \
    git fetch --tags && \
    git checkout tags/release-1.27.1 -b release-1.27.1 && \
    auto/configure --with-compat
RUN git clone https://github.com/nginxinc/nginx-otel.git && \
    cd nginx-otel && \
    mkdir build && \
    cd build && \
    cmake -DNGX_OTEL_NGINX_BUILD_DIR=/nginx/objs .. && \
    make
FROM openresty/openresty:${OPENRESTY_TAG} AS runner
RUN mkdir /usr/local/openresty/nginx/modules && \
    apt update && \
    apt upgrade -y && \
    apt install libc-ares2
COPY --from=builder /nginx-otel/build/ngx_otel_module.so /usr/local/openresty/nginx/modules/
