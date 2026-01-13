# https://github.com/nginxinc/nginx-otel
# https://github.com/nginx/njs

ARG NGINX_VERSION=1.27.1
ARG OPENRESTY_VERSION=1.27.1.2
ARG OPENRESTY_TAG=1.27.1.2-2-bookworm
FROM openresty/openresty:${OPENRESTY_TAG} AS builder
ARG OPENRESTY_VERSION
ARG NGINX_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    cmake \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libpcre2-dev \
    pkg-config \
    libc-ares-dev \
    libre2-dev \
    libxslt1-dev
RUN wget https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz && \
    tar -xzvf openresty-${OPENRESTY_VERSION}.tar.gz && \
    git clone --depth 1 https://github.com/nginx/njs.git /njs && \
    git clone --depth 1 https://github.com/nginxinc/nginx-otel.git /nginx-otel
WORKDIR /openresty-${OPENRESTY_VERSION}/bundle/nginx-${NGINX_VERSION}
RUN ./configure \
    --with-compat \
    --add-dynamic-module=/njs/nginx \
    --with-pcre \
    --with-pcre-jit && \
    make -j$(nproc) modules
WORKDIR /nginx-otel/build
RUN cmake -DNGX_OTEL_NGINX_BUILD_DIR=/openresty-${OPENRESTY_VERSION}/bundle/nginx-${NGINX_VERSION}/objs .. && \
    make -j$(nproc)

FROM openresty/openresty:${OPENRESTY_TAG}
ARG OPENRESTY_VERSION
ARG NGINX_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxslt1.1 \
    libc-ares2
COPY --from=builder /openresty-${OPENRESTY_VERSION}/bundle/nginx-${NGINX_VERSION}/objs/ngx_http_js_module.so /usr/local/openresty/nginx/modules/
COPY --from=builder /nginx-otel/build/ngx_otel_module.so /usr/local/openresty/nginx/modules/
