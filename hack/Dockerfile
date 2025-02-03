FROM --platform=linux/amd64 rust:slim-bookworm

RUN apt-get update && apt-get install -y pkg-config libssl-dev jq curl ca-certificates postgresql-client

RUN cargo install --features=ssl websocat

COPY handle_event.sh /srv/handle_event.sh

# ENV CAMERA_ID=""
# ENV CLASS_NAME=""
# ENV WEBHOOK_SUFFIX=""

ENTRYPOINT ["bash", "-c", "websocat -E ws://camry.initialed85.cc/api/__stream?include=video | ./srv/handle_event.sh"]
CMD []
