ARG OPENRESTY_VERSION=1.31.9.1
# OpenResty source: git = build from pinned upstream commit (unreleased fixes), release = official openresty.org tarball
ARG OPENRESTY_SOURCE=git
# Upstream master commit with nginx core 1.31.9 (includes the nginx 1.31.9 security fixes).
ARG OPENRESTY_GIT_REF=0b91f30b31a9c711ff763f63807ae95d2fe2ceed
ARG NJS_VERSION=1.0.1
# Commits, not tags: the latest tags are far behind master and miss fixes.
ARG NGINX_OTEL_REF=e3b6c98b1556e4c82cec39acc7be91a62449fa84
ARG NGINX_VTS_REF=3b9235819e4a8bdadd30fbb70434b07d20c33248
ARG DEBIAN_RELEASE=13.5-slim

# OpenResty source option 1: build the tarball from a pinned upstream commit
FROM debian:${DEBIAN_RELEASE} AS src-git

ARG OPENRESTY_VERSION
ARG OPENRESTY_GIT_REF

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  dos2unix \
  git \
  gzip \
  make \
  patch \
  perl \
  tar \
  wget \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /openresty
# Fails if OPENRESTY_VERSION doesn't match the version at OPENRESTY_GIT_REF.
RUN git init -q && \
  git remote add origin https://github.com/openresty/openresty.git && \
  git fetch -q --depth 1 origin ${OPENRESTY_GIT_REF} && \
  git checkout -q FETCH_HEAD && \
  test "$(./util/ver)" = "${OPENRESTY_VERSION}" && \
  make && \
  mv openresty-${OPENRESTY_VERSION}.tar.gz /openresty.tar.gz

# OpenResty source option 2: official release tarball
FROM debian:${DEBIAN_RELEASE} AS src-release

ARG OPENRESTY_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fSL https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz -o /openresty.tar.gz

# Select the source stage
FROM src-${OPENRESTY_SOURCE} AS src

FROM debian:${DEBIAN_RELEASE} AS builder

ARG OPENRESTY_VERSION
ARG NJS_VERSION
ARG NGINX_OTEL_REF
ARG NGINX_VTS_REF

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
# Unpack the OpenResty source from the selected stage and clone required modules
COPY --from=src /openresty.tar.gz openresty.tar.gz
RUN tar -zxf openresty.tar.gz && \
  git clone --depth 1 --branch ${NJS_VERSION} https://github.com/nginx/njs.git /src/njs && \
  git clone https://github.com/nginxinc/nginx-otel.git /src/nginx-otel && \
  git -C /src/nginx-otel checkout ${NGINX_OTEL_REF} && \
  git clone https://github.com/vozlt/nginx-module-vts.git /src/nginx-module-vts && \
  git -C /src/nginx-module-vts checkout ${NGINX_VTS_REF}

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
