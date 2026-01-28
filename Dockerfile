# https://github.com/nginxinc/nginx-otel
# https://github.com/nginx/njs

ARG OPENRESTY_TAG=1.27.1.2-2-bookworm
ARG NGINX_VERSION=1.27.1
ARG OPENRESTY_VERSION=1.27.1.2

FROM openresty/openresty:${OPENRESTY_TAG} AS base-builder
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

# Build NJS module
FROM base-builder AS njs-builder
ARG NGINX_VERSION
ARG OPENRESTY_VERSION

RUN wget https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz && \
    tar -xzvf openresty-${OPENRESTY_VERSION}.tar.gz
RUN git clone --depth 1 https://github.com/nginx/njs.git /njs

WORKDIR /openresty-${OPENRESTY_VERSION}/bundle/nginx-${NGINX_VERSION}
RUN ./configure --with-compat --add-dynamic-module=/njs/nginx --with-pcre-jit && \
    make -j$(nproc) modules

# Build TypeScript definition files (.d.ts)
WORKDIR /njs
RUN ./configure && make ts

# Build OTEL module
FROM base-builder AS otel-builder
ARG NGINX_VERSION
ARG OPENRESTY_VERSION
RUN wget https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz && \
    tar -xzvf openresty-${OPENRESTY_VERSION}.tar.gz
RUN git clone --depth 1 https://github.com/nginxinc/nginx-otel.git /nginx-otel
WORKDIR /openresty-${OPENRESTY_VERSION}/bundle/nginx-${NGINX_VERSION}
RUN ./configure --with-compat --with-pcre-jit
WORKDIR /nginx-otel/build
RUN cmake -DNGX_OTEL_NGINX_BUILD_DIR=/openresty-${OPENRESTY_VERSION}/bundle/nginx-${NGINX_VERSION}/objs .. && \
    make -j$(nproc)

# Final image
FROM openresty/openresty:${OPENRESTY_TAG}
ARG NGINX_VERSION
ARG OPENRESTY_VERSION

# Runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxslt1.1 \
    libc-ares2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=njs-builder /openresty-${OPENRESTY_VERSION}/bundle/nginx-${NGINX_VERSION}/objs/ngx_http_js_module.so /usr/local/openresty/nginx/modules/
COPY --from=otel-builder /nginx-otel/build/ngx_otel_module.so /usr/local/openresty/nginx/modules/

# Copy TypeScript definitions for NJS development
RUN mkdir -p /usr/local/openresty/njs/ts/
COPY --from=njs-builder /njs/build/ts/*.d.ts /usr/local/openresty/njs/ts/
