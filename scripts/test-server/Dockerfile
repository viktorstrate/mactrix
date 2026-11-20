FROM ghcr.io/nix-community/docker-nixpkgs/nix:nixos-25.11-aarch64-linux

# Disable sandbox (not supported inside Docker without --privileged)
RUN mkdir -p /etc/nix && \
    echo 'sandbox = false' >> /etc/nix/nix.conf

# Copy the test-server contents into the image
WORKDIR /test-server
COPY shell.nix ./shell.nix
COPY npins ./npins
COPY users.csv ./users.csv
COPY run-matrix-server.sh ./run-matrix-server.sh
COPY populate-matrix-server.py ./populate-matrix-server.py

# Pre-build the nix shell so all dependencies are cached in the image
RUN nix-build shell.nix

# When the container starts, enter the nix shell
CMD ["nix-shell"]
