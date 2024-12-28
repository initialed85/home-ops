FROM --platform=linux/amd64 rust:slim-bookworm

RUN apt-get update && apt-get install -y pkg-config libssl-dev jq curl

RUN cargo install --features=ssl websocat

COPY handle_event.sh /srv/handle_event.sh

ENTRYPOINT ["bash", "-c", "websocat -E ws://camry.initialed85.cc/api/__stream?include=video | /srv/handle_event.sh"]
CMD []
