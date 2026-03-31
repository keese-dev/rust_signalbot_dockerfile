FROM rust:1.92-slim-bookworm AS planner
RUN cargo install cargo-chef

WORKDIR /app
# Copy the whole project
COPY . .
# Prepare a build plan ("recipe")
RUN cargo chef prepare --recipe-path recipe.json




FROM rust:1.92-slim-bookworm AS builder
RUN cargo install cargo-chef
# Install build-time system dependencies.
# - libssl-dev & pkg-config: for the `openssl-sys` crate, a dependency of `reqwest` and `pq-sys`.
RUN apt-get update && apt-get install -y libssl-dev pkg-config && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Copy the build plan from the previous Docker stage
COPY --from=planner /app/recipe.json recipe.json

# Build dependencies - this layer is cached as long as `recipe.json`
# doesn't change.
RUN cargo chef cook --recipe-path recipe.json



# 1. Declare the build argument
ARG SERVER_SIGNAL_PHONE_NUMBER
ARG SIGNAL_API_URL


# 2. Map the build argument to an environment variable
# so the Rust compiler (cargo build) can read it
ENV SERVER_SIGNAL_PHONE_NUMBER=$SERVER_SIGNAL_PHONE_NUMBER
ENV SIGNAL_API_URL=$SIGNAL_API_URL

# Copy the application source code. A .dockerignore file should be used
# to prevent copying unnecessary files (like /target, .git, .env).
COPY . .

RUN cargo build --release
# Verify that the binary was created. This command will fail the build if the file is not found.
#RUN ls -la target/release/signal-bot-broker
#RUN #find / -type f | rg signal
#RUN ls -laR ../../



# Stage 2: Create a slim, production-ready image
FROM debian:bookworm-slim AS final

# Install runtime dependencies.
# - ca-certificates: for making HTTPS requests.
# - libssl3: the shared library for OpenSSL, needed by reqwest.
# The `pq-sys` crate is using the `bundled` feature, so `libpq` is statically
# linked into the binary and `libpq5` is not needed at runtime.
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*

# Create a non-root user for security.
RUN groupadd --system appuser && useradd --system --gid appuser appuser
USER appuser

# Copy the compiled binary from the builder stage.
# The binary name is taken from the `name` field in Cargo.toml.
COPY --from=builder /usr/src/app/target/release/signal-bot-broker /usr/local/bin/signal-bot-broker

# Set the command to run the application.
CMD ["signal-bot-broker"]
