# syntax=docker/dockerfile:1
# check=error=true

ARG DOCKER_IMAGE=alpine:3.23
ARG LUANTI_VERSION=master

FROM $DOCKER_IMAGE AS dev

ENV LUAJIT_VERSION=v2.1

RUN apk add --no-cache git build-base cmake curl-dev zlib-dev zstd-dev \
		sqlite-dev postgresql-dev hiredis-dev leveldb-dev \
		gmp-dev jsoncpp-dev ninja ncurses-dev

WORKDIR /usr/src/

ADD https://github.com/jupp0r/prometheus-cpp.git?branch=master /usr/src/prometheus-cpp
ADD https://github.com/libspatialindex/libspatialindex.git?branch=main /usr/src/libspatialindex
ADD --keep-git-dir https://luajit.org/git/luajit.git?branch=${LUAJIT_VERSION} /usr/src/luajit

RUN cd prometheus-cpp && \
		cmake -B build \
			-DCMAKE_INSTALL_PREFIX=/usr/local \
			-DCMAKE_BUILD_TYPE=Release \
			-DENABLE_TESTING=0 \
			-GNinja && \
		cmake --build build && \
		cmake --install build && \
		cd /usr/src/ && \
	cd libspatialindex && \
		cmake -B build \
			-DCMAKE_INSTALL_PREFIX=/usr/local && \
		cmake --build build && \
		cmake --install build && \
		cd /usr/src/ && \
	cd luajit && \
		make amalg && make install && \
	cd /usr/src/

FROM dev AS builder

ARG LUANTI_VERSION
ADD --keep-git-dir https://github.com/luanti-org/luanti.git?ref=${LUANTI_VERSION} /usr/src/luanti
COPY patches/ /tmp/patches/

WORKDIR /usr/src/luanti
RUN git apply --whitespace=nowarn /tmp/patches/0001-pelican-terminal-plain-mode.patch && \
	cmake -B build \
		-DCMAKE_INSTALL_PREFIX=/usr/local \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SERVER=TRUE \
		-DENABLE_PROMETHEUS=TRUE \
		-DBUILD_UNITTESTS=FALSE -DBUILD_BENCHMARKS=FALSE \
		-DBUILD_CLIENT=FALSE \
		-DENABLE_CURSES=TRUE \
		-GNinja && \
	cmake --build build && \
	cmake --install build

FROM $DOCKER_IMAGE AS runtime

RUN apk add --no-cache curl gmp libstdc++ libgcc libpq jsoncpp zstd-libs \
				sqlite-libs postgresql hiredis leveldb ncurses tini su-exec && \
	adduser -D container --uid 1000 -h /home/container && \
	chown -R container:container /home/container

WORKDIR /home/container

COPY --from=builder /usr/local/share/luanti /usr/local/share/luanti
COPY --from=builder /usr/local/bin/luantiserver /usr/local/bin/luantiserver
COPY --from=builder /usr/local/share/doc/luanti/minetest.conf.example /etc/minetest/minetest.conf
COPY --from=builder /usr/local/lib/libspatialindex* /usr/local/lib/
COPY --from=builder /usr/local/lib/libluajit* /usr/local/lib/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 30000/udp 30000/tcp

ENTRYPOINT ["/sbin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
