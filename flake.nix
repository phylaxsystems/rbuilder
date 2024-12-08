{
  description = "rbuilder";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, rust-overlay, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        
        rustNightly = pkgs.rust-bin.nightly.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" "cargo" ];
        };
        
        rustStable = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" "cargo" ];
        };

        readCargoToml = path: 
          let 
            toml = builtins.readFile path;
            match = builtins.match ''.*version = ["']([^"']*)["'].*'' toml;
          in
            if match == null then "0.1.0" else builtins.head match;

        filterSource = name: 
          pkgs.lib.cleanSourceWith {
            src = ./.;
            filter = path: type: let 
              baseName = baseNameOf (toString path);
              path' = toString path;
              cratePath = "crates/${name}";
            in (
              baseName == "Cargo.toml" ||
              baseName == "Cargo.lock" ||
              (pkgs.lib.hasPrefix cratePath path' && (
                baseName == "Cargo.toml" ||
                pkgs.lib.hasPrefix "src" baseName ||
                pkgs.lib.hasSuffix ".rs" baseName
              ))
            );
          };

        systemSpecific = with pkgs;
          if stdenv.isDarwin then [
            darwin.apple_sdk.frameworks.Security
            darwin.apple_sdk.frameworks.SystemConfiguration
            darwin.cctools
            libiconv
          ] else [
            glibc
            gdb
          ];

        commonBuildInputs = with pkgs; [
          openssl
          pkg-config
        ] ++ systemSpecific;

        commonNativeBuildInputs = with pkgs; [
          rustNightly
          pkg-config
        ];

      in
      {
        packages = {
          op-rbuilder = pkgs.rustPlatform.buildRustPackage {
            pname = "op-rbuilder";
            version = readCargoToml ./crates/op-rbuilder/Cargo.toml;
            src = filterSource "op-rbuilder";
            
            buildInputs = commonBuildInputs;
            nativeBuildInputs = commonNativeBuildInputs;

            cargoLock = {
              lockFile = ./Cargo.lock;
              allowBuiltinFetchGit = true;
            };
          };

          reth-rbuilder = pkgs.rustPlatform.buildRustPackage {
            pname = "reth-rbuilder";
            version = readCargoToml ./crates/reth-rbuilder/Cargo.toml;
            src = filterSource "reth-rbuilder";
            
            buildInputs = commonBuildInputs;
            nativeBuildInputs = commonNativeBuildInputs;

            cargoLock = {
              lockFile = ./Cargo.lock;
              allowBuiltinFetchGit = true;
            };
          };

          default = self.packages.${system}.op-rbuilder;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            rustNightly
            rustStable
            clang
            lldb
            gnumake
            pkg-config
            openssl
            git
          ] ++ systemSpecific;

          shellHook = ''
            export OLD_PS1="$PS1" # Preserve the original PS1
            export PS1="nix-shell:rbuilder $PS1"

            export RUST_BACKTRACE=1
            export RUST_SRC_PATH=${rustNightly}/lib/rustlib/src/rust/library
            
            export CC=${pkgs.clang}/bin/clang
            export CXX=${pkgs.clang}/bin/clang++
            
            export PATH=$PATH:$HOME/.cargo/bin
            
            rustup default nightly 2>/dev/null || true
            
            ${if pkgs.stdenv.isDarwin then ''
              export DYLD_LIBRARY_PATH=${pkgs.openssl}/lib:$DYLD_LIBRARY_PATH
              export LIBRARY_PATH=${pkgs.openssl}/lib:$LIBRARY_PATH
              export CPPFLAGS="-I${pkgs.openssl}/include"
              export LDFLAGS="-L${pkgs.openssl}/lib"
            '' else ''
              export LD_LIBRARY_PATH=${pkgs.openssl}/lib:$LD_LIBRARY_PATH
            ''}
            echo "Nightly Rust toolchain is set as default."
            echo "Use 'rustup override set stable' to switch to stable if needed."
          '';
          
          # reset ps1
          shellExitHook = ''
            export PS1="$OLD_PS1"
          '';
        };
      });
}