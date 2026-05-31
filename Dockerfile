# SPDX-License-Identifier: ISC
# SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
# NOTE: Dockerfile written by an LLM

# Multi-stage Dockerfile for Tomasulo simulator
# Uses mise-en-place for tool management

# Stage 1: Base build environment with all dependencies
FROM fedora:43 AS build-base

# Install build dependencies and mise
RUN dnf update -y && \
    dnf install -y dnf-plugins-core && \
    dnf copr enable -y jdxcode/mise && \
    dnf install -y \
        mise \
        gcc \
        clang \
        musl-gcc \
        musl-clang \
        musl-libc-static \
        flex \
        bison \
        make \
        git \
        tar \
        xz \
    && dnf clean all

# Set up mise
ENV PATH="/root/.local/share/mise/shims:${PATH}"
ENV MISE_CONFIG_DIR="/app/.config/mise"

# Set working directory
WORKDIR /app

# Stage 2: Zig build
FROM build-base AS zig-build

# Copy source files and mise config
COPY . /app/

# Install tools via mise and build with Zig
RUN mise exec -- zig build -Dtarget=x86_64-linux-musl

# Run tests with Zig via mise
RUN mise exec -- zig build test

# Stage 3: Makefile build (alternative)
FROM build-base AS make-build

# Copy source files
COPY . /app/

# Build with Makefile
RUN make clean && make all CC=musl-clang

# Run Makefile simulations
RUN if [ -d simulations ]; then make test; fi

# Stage 4: Runtime (minimal image with just the binary)
FROM alpine:latest AS runtime

# Copy the built binary from Zig build
COPY --from=zig-build /app/zig-out/bin/tomasulo /usr/local/bin/tomasulo

# Add simulation files for runtime testing if needed
COPY --from=zig-build /app/simulations /app/simulations

WORKDIR /app

# Default command
CMD ["/usr/local/bin/tomasulo"]

# Stage 5: Development environment (includes all tools)
FROM build-base AS development

# Copy source files and mise config
COPY . /app/

# Install tools via mise
RUN mise install

# Keep the development environment ready with mise available
CMD ["/bin/bash"]
