{
  description = "An interface for current and future web projects.";

  inputs = {
    naersk = {
      url = "github:nmattia/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/master";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { naersk, nixpkgs, rust-overlay, self, utils }:
    utils.lib.eachDefaultSystem (
      system:
        let
          pkgs = import nixpkgs {
            inherit system;
            # apply rust-overlay
            overlays = [ rust-overlay.overlay ];
          };

          # define the rust toolchain used to build `api`
          #
          # refs:
          # - https://github.com/oxalica/rust-overlay#attributes-provided-by-the-overlay
          # - https://github.com/ebroto/rustup/blob/c2db7dac6b38c99538eec472db9d23d18f918409/README.md#the-toolchain-file
          rust = pkgs.rust-bin.nightly.latest.rust.override {
            # the set of additional extensions to install
            #
            # TODO: confirm the default set of extensions - https://github.com/oxalica/rust-overlay/issues/14
            #
            # refs:
            # - https://rust-lang.github.io/rustup/concepts/components.html
            # - https://github.com/oxalica/rust-overlay/blob/e97d64daac9333196691e776d5062713a79bf951/manifest.nix#L10
            extensions = [
              # source code for rust standard library - used by rust-analyzer
              "rust-src"

              # theoretically this is valid but it fails to build with it
              # ref: https://github.com/oxalica/rust-overlay/blob/e97d64daac9333196691e776d5062713a79bf951/manifest.nix#L21
              # "rustfmt-preview"
            ];

            # install standard library for given targets
            #
            # refs:
            # - https://github.com/ebroto/rustup/blob/c2db7dac6b38c99538eec472db9d23d18f918409/README.md#cross-compilation
            # - https://doc.rust-lang.org/beta/rustc/platform-support.html
            targets = [ "x86_64-unknown-linux-gnu" "x86_64-apple-darwin" ];
          };

          # specify the rust and cargo versions for `naersk` to use
          naersk-lib = naersk.lib."${system}".override {
            cargo = rust;
            rustc = rust;
          };
        in
          rec {
            # nix <command> . runs the default attribute corresponding to that
            # command
            # e.g. `nix run .` runs the `defaultApp`

            defaultApp = apps.api;
            defaultPackage = packages.api;

            # `nix run`
            apps.api = utils.lib.mkApp {
              drv = packages.api;

              # `naersk` builds packages whose derivations have names of the
              # form "{name}-{version}" but whose binaries exclude the version
              # in the filename. for `mkApp` to find the correct executable
              # target specify name w/o a version here.
              name = "api";
            };

            # checks to be run either manually, in CI, or in pre-commit hooks
            #
            # TODO: understand how to define arbitrary checks here.
            # documentation does not seem to have much about this.
            #
            # - https://nixos.wiki/wiki/Flakes#Output_schema
            # - https://discourse.nixos.org/t/my-painpoints-with-flakes/9750/12
            checks = {
              # confirm our api builds (same as `nix build .#api`)
              build = self.packages.${system}.api;

              # cargo-lint = "cargo clippy"
              # cargo-fmt = "cargo fmt -- --check";
            };

            # `nix develop`
            devShell = let
              cacert = pkgs.cacert;
            in
              pkgs.mkShell {
                # buildInputs = [ pkgs.openssl pkgs.cacert ];
                # buildInputs = with pkgs; [
                #   pkgconfig
                #   openssl
                #   cmake
                #   zlib
                #   libgit2
                # ];

                # cross-compilation - https://github.com/oxalica/rust-overlay/issues/11#issuecomment-772496493

                nativeBuildInputs = with pkgs; [
                  # use the rust version we specified above
                  rust
                  # can be run manually and also used by `rust-analyzer`
                  rustfmt
                  cargo-watch
                ]
                # ref - https://stackoverflow.com/a/51161923
                ++ lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.Security ];
                # ++ lib.optionals stdenv.isLinux [ pkg-config openssl ];

                shellHook = ''
                  export SOURCE_CODE="${self.outPath}"
                '' + (
                  if pkgs.stdenv.isLinux then ''
                    # CARGO_HTTP_CAINFO="/nix/store/gdgnc8r39yz1g74bw674flzdw759ml1c-nss-cacert-3.56/etc/ssl/certs/ca-bundle.crt"
                    export CARGO_HTTP_CAINFO="${cacert}/etc/ssl/certs/ca-bundle.crt"
                    export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
                  '' else ""
                );
              };

            # `nix build`
            packages = {
              docker = pkgs.dockerTools.streamLayeredImage {
                name = "api";
                contents = [ self.packages.x86_64-linux.api ];
                config.Cmd = [ "api" ];
              };

              # version & name are parsed from Cargo.toml
              api = naersk-lib.buildPackage {
                src = ./.;

                # buildInputs = [] ++ lib.optionals stdenv.isLinux [
                #   pkg-config
                #   openssl
                # ];
              };
            };

          }
    );
}
