ARG NEXUS_VERSION="3.30.1"

FROM sonatype/nexus3:${NEXUS_VERSION} as app
USER root
RUN curl -L -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && \
    chmod +x /usr/local/bin/jq

USER nexus
WORKDIR /nexus-data/nexus-ops/
COPY provision/ .
CMD /nexus-data/nexus-ops/entrypoint.sh
