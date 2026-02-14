ARG OPENRESTY_VERSION=1.27.1.1
ARG NJS_VERSION=0.9.5
ARG DEBIAN_RELEASE=trixie-slim

FROM debian:${DEBIAN_RELEASE} AS builder
ARG OPENRESTY_VERSION
ARG NJS_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  gettext \
  libpcre2-dev \
  libssl-dev \
  zlib1g-dev \
  git \
  cmake \
  pkg-config \
  libc-ares-dev \
  libre2-dev \
  libxslt1-dev \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN curl -fSL https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz -o openresty.tar.gz && \
  tar -zxvf openresty.tar.gz && \
  git clone --depth 1 --branch ${NJS_VERSION} https://github.com/nginx/njs.git /src/njs && \
  git clone --depth 1 https://github.com/nginxinc/nginx-otel.git /src/nginx-otel
WORKDIR /src/openresty-${OPENRESTY_VERSION}
RUN ./configure -j$(nproc) \
  --with-debug \
  --with-pcre-jit \
  --with-ipv6 \
  --with-threads \
  --with-file-aio \
  --with-http_v2_module \
  --with-http_realip_module \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_auth_request_module \
  --with-http_gzip_static_module \
  --with-http_gunzip_module \
  --with-http_sub_module \
  --with-http_xslt_module=dynamic \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --add-dynamic-module=/src/njs/nginx \
  --add-dynamic-module=/src/nginx-otel
WORKDIR /src/nginx-otel/build
RUN cmake -DNGX_OTEL_NGINX_BUILD_DIR=/src/openresty-${OPENRESTY_VERSION}/build/nginx-1.27.1/objs .. && \
  make -j$(nproc)
WORKDIR /src/openresty-${OPENRESTY_VERSION}
RUN make -j$(nproc) && make install && \
  cp /src/nginx-otel/build/ngx_otel_module.so /usr/local/openresty/nginx/modules/

FROM debian:${DEBIAN_RELEASE}
RUN apt-get update && apt-get install -y --no-install-recommends \
  curl \
  wget \
  libssl3t64 \
  libpcre2-8-0 \
  zlib1g \
  libxslt1.1 \
  libc-ares2 \
  && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/local/openresty /usr/local/openresty
ENV PATH="/usr/local/openresty/bin:/usr/local/openresty/nginx/sbin:${PATH}"
RUN ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log \
  && ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log
CMD ["openresty", "-g", "daemon off;"]
