ARG OPENRESTY_VERSION=1.29.2.5
ARG NJS_VERSION=0.9.6
ARG DEBIAN_RELEASE=13.5-slim

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
# Download OpenResty and clone required modules
RUN curl -fSL https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz -o openresty.tar.gz && \
  tar -zxvf openresty.tar.gz && \
  git clone --depth 1 --branch ${NJS_VERSION} https://github.com/nginx/njs.git /src/njs && \
  git clone --depth 1 https://github.com/nginxinc/nginx-otel.git /src/nginx-otel && \
  git clone --depth 1 https://github.com/vozlt/nginx-module-vts.git /src/nginx-module-vts

WORKDIR /src/openresty-${OPENRESTY_VERSION}
# Configure OpenResty with desired modules and dynamic module support
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
  --add-dynamic-module=/src/nginx-otel \
  --add-module=/src/nginx-module-vts

# Compile and install OpenResty
# Compile OpenResty first to generate the NGINX object files required by the OTel build system.
RUN make -j$(nproc)
RUN make install

# Build the OTEL module
WORKDIR /src/nginx-otel/build

# Generate the build system files using CMake
# Pass the path to the NGINX binary objects created during the OpenResty build phase
# This ensures OTel module is compiled with matching binary compatibility
RUN NGX_BUILD_DIR=$(find /src/openresty-${OPENRESTY_VERSION}/build -name "nginx-*" -type d)/objs && \
    cmake -DNGX_OTEL_NGINX_BUILD_DIR=${NGX_BUILD_DIR} ..

# Compile the OTEL module
RUN make -j$(nproc)

# Copy OTEL module into OpenResty
RUN cp /src/nginx-otel/build/ngx_otel_module.so /usr/local/openresty/nginx/modules/

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

# Copy the compiled OpenResty directory from the builder stage
COPY --from=builder /usr/local/openresty /usr/local/openresty

# Set up environment paths
ENV PATH="/usr/local/openresty/bin:/usr/local/openresty/nginx/sbin:${PATH}"

# Forward NGINX logs to Docker log collector
RUN ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log \
  && ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log

STOPSIGNAL SIGQUIT
CMD ["openresty", "-g", "daemon off;"]
