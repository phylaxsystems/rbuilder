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

        # Get both nightly and stable Rust, but nightly is primary
        rustNightly = pkgs.rust-bin.nightly.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" "cargo" ];
        };
        
        rustStable = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" "cargo" ];
        };

        # System-specific packages
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
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Rust toolchains (nightly first)
            rustNightly
            rustStable

            # C/C++ toolchains
            clang
            lldb
            gnumake

            # Development tools
            pkg-config
            openssl
            git

          ] ++ systemSpecific;

          shellHook = ''
            export RUST_BACKTRACE=1
            export RUST_SRC_PATH=${rustNightly}/lib/rustlib/src/rust/library
            
            # Set CC and CXX environment variables
            export CC=${pkgs.clang}/bin/clang
            export CXX=${pkgs.clang}/bin/clang++
            
            # Add cargo bins to PATH
            export PATH=$PATH:$HOME/.cargo/bin
            
            # Set nightly as default
            rustup default nightly 2>/dev/null || true
            
            # Platform-specific environment setup
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
        };
      });
}