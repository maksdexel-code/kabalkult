# Price relayer as a one-shot container (Cloud Run job, triggered every 5 minutes by Cloud Scheduler).
# Runs scripts/relayer/relay.sh --once. Keys come from Secret Manager as env vars, never baked into the image.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends bash curl jq ca-certificates gawk \
 && rm -rf /var/lib/apt/lists/*
# cast from the same Foundry release used to build and test the contracts.
ARG FOUNDRY=v1.10.0
RUN curl -fsSL "https://github.com/foundry-rs/foundry/releases/download/${FOUNDRY}/foundry_${FOUNDRY}_linux_amd64.tar.gz" \
  | tar -xz -C /usr/local/bin cast && cast --version
WORKDIR /app
COPY relay.sh usd.jq scripts/relayer/
RUN mkdir logs
ENV RELAY_LOG_STDOUT=1
ENTRYPOINT ["bash", "scripts/relayer/relay.sh", "--once"]
