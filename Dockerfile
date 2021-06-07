ARG NEXUS_VERSION="3.30.1"

FROM sonatype/nexus3:${NEXUS_VERSION} as app
USER root
RUN curl -L -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && \
    chmod +x /usr/local/bin/jq

USER nexus
ENV NEXUS_DATA_PATH="/nexus-data" \
    NEXUS_ADMIN_USERNAME="admin" \
    NEXUS_ADMIN_PASSWORD="admin" \
    NEXUS_API_PATH="service/rest/v1" \
    NEXUS_BASE_PATH="http://localhost:8081" \
    NEXUS_OPS_VERBOSE="false"
WORKDIR /"${NEXUS_DATA_PATH}/nexus-ops/"
COPY provision/ .
CMD /nexus-data/nexus-ops/entrypoint.sh
