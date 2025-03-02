FROM ubuntu:22.04

RUN apt-get update && apt-get install -y keepalived

COPY ./docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
