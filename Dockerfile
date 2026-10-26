FROM alpine:3.22 AS pocketbase-download

ARG TARGETARCH
ARG PB_VERSION=0.40.6

RUN set -eux; \
    apk add --no-cache ca-certificates wget unzip; \
    case "${TARGETARCH}" in \
      amd64) pb_arch="amd64" ;; \
      arm64) pb_arch="arm64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    PB_ARCHIVE="pocketbase_${PB_VERSION}_linux_${pb_arch}.zip"; \
    wget -q -O "/tmp/${PB_ARCHIVE}" "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/${PB_ARCHIVE}"; \
    wget -q -O /tmp/checksums.txt "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/checksums.txt"; \
    cd /tmp; \
    grep " ${PB_ARCHIVE}$" checksums.txt | sha256sum -c -; \
    unzip "${PB_ARCHIVE}" pocketbase -d /out

FROM alpine:3.22

RUN apk add --no-cache ca-certificates sqlite tzdata \
    && addgroup -S -g 10001 pocketbase \
    && adduser -S -D -H -u 10001 -G pocketbase pocketbase \
    && mkdir -p /pb_data \
    && chown -R pocketbase:pocketbase /pb_data

COPY --from=pocketbase-download /out/pocketbase /usr/local/bin/pocketbase

USER pocketbase
EXPOSE 8090

ENTRYPOINT ["/usr/local/bin/pocketbase"]
CMD ["serve", "--http=0.0.0.0:8090", "--dir=/pb_data", "--migrationsDir=/pb_migrations", "--hooksDir=/pb_hooks", "--encryptionEnv=PB_ENCRYPTION_KEY"]
