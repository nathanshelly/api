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
          rust-overlay' = import rust-overlay;
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay' ];
          };

          rust = (
            pkgs.rustChannelOf {
              date = "2021-01-28";
              channel = "nightly";
            }
          ).rust;

          naersk-lib = naersk.lib."${system}".override {
            cargo = rust;
            rustc = rust;
          };
        in
          rec {
            # `nix build`
            packages.api = naersk-lib.buildPackage {
              pname = "api";
              root = ./.;
            };
            defaultPackage = packages.api;

            # `nix run`
            apps.api = utils.lib.mkApp {
              drv = packages.api;
            };
            defaultApp = apps.api;

            # `nix develop`
            devShell = pkgs.mkShell {
              # supply the specific rust version
              nativeBuildInputs = with pkgs; [ rust ]
              ++ lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.Security ];
            };
          }
    );
}
