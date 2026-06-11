FROM alpine:3.20

# Versión de PocketBase fijada (ver .pocketbase-version)
ARG POCKETBASE_VERSION=0.38.0

RUN apk add --no-cache ca-certificates unzip wget \
    && wget -O /tmp/pocketbase.zip "https://github.com/pocketbase/pocketbase/releases/download/v${POCKETBASE_VERSION}/pocketbase_${POCKETBASE_VERSION}_linux_amd64.zip" \
    && unzip /tmp/pocketbase.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/pocketbase \
    && rm /tmp/pocketbase.zip

WORKDIR /pb

EXPOSE 8090

# Los datos viven en /pb/pb_data, montado como volumen ./pb_data desde el host.
CMD ["pocketbase", "serve", "--http=0.0.0.0:8090", "--dir=/pb/pb_data"]
