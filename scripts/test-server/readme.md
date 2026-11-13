# Test server

Infrastructure to launch a ephemeral matrxi server.

## Requirements

- a [continuwuity](https://continuwuity.org) binary
- a recent version of python
- [matrix-nio](https://github.com/matrix-nio/matrix-nio), a python library to use the matrix api

If you use the [nix package manager](https://nixos.org), you can use `nix-shell` to have everything needed available in your local shell. This is also what the CI environment uses.

## Launch

The [run-matrix-server.sh](./run-matrix-server.sh) script will start a [continuwuity](https://continuwuity.org) matrix server, read a list of users from [users.csv](./users.csv) and use the continuwuity CLI to register them.

Once the server is running, inside another terminal run [populate-matrix-server.py](./populate-matrix-server.py) to make users sign in and send messages. Afterwards, you can sign in with any matrix client to [http://localhost:8008](http://localhost:8008).

Note: The first user contained in [users.csv](./users.csv) will become the administrator of the server.

To debug things or know what is happening on the server, if you are inside the `nix-shell`, you can run `element-web-client` to start a python server on [http://localhost:8000](http://localhost:8000) with a element web client.

## Nix stuff

Nix is used to have a reproducible environment between CI and developers machines, across macOS and Linux. The tool [npins](https://github.com/andir/npins) is used to pin a precise version of [nixpkgs](https://github.com/nixos/nixpkgs), declaring which versions of tools defined in [shell.nix](./shell.nix) will be used.

If you want to get newer versions of tools, run:

```shell
nix-shell --run "npins update"
```

Next time you will inside the `nix-shell`, the latest versions will be made available automatically.
