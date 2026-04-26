{
  description = "mcpm – incremental test builds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ruby = pkgs.ruby_4_0;

        # Bundler environment built from Gemfile + gemset.nix
        gems = pkgs.bundlerEnv {
          name = "mcpm-gems";
          inherit ruby;
          gemdir = ./.;
          # Some gems have native extensions that need these
          buildInputs = [ pkgs.libyaml ];
        };

        # ── Test dependency manifest ────────────────────────────────
        # Each key is a test file; `srcs` lists the source files it
        # depends on. Changing any src (or the test itself, or shared
        # infra) invalidates the cached result → test re-runs.
        testDeps = import ./nix/test-deps.nix;

        # ── Shared test infrastructure ──────────────────────────────
        # These files are inputs to *every* test derivation. Changing
        # any of them invalidates all cached test results.
        sharedSrc = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [
            ./test/test_helper.rb
            ./test/fixtures
            ./lib              # test_helper.rb loads lib/ files at require time
            ./Gemfile
            ./Gemfile.lock
          ];
        };

        # ── Per-test derivation builder ─────────────────────────────
        mkTest = { testFile, srcs }:
          let
            # Collect all source files relevant to this test
            testSrc = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions (
                # The test file itself
                [ (./. + "/${testFile}") ]
                # Its declared source dependencies
                ++ map (f: ./. + "/${f}") srcs
                # Shared infra (test_helper, fixtures, lib, Gemfile)
                ++ [
                  ./test/test_helper.rb
                  ./test/fixtures
                  ./lib
                  ./Gemfile
                  ./Gemfile.lock
                ]
              );
            };

            safeName = builtins.replaceStrings [ "/" "." ] [ "-" "_" ] testFile;
          in
          pkgs.stdenv.mkDerivation {
            name = "mcpm-test-${safeName}";
            src = testSrc;

            nativeBuildInputs = [ gems ruby gems.wrappedRuby ];

            # Skip configure/build phases — we only need the check phase
            dontConfigure = true;
            dontBuild = true;

            # The test itself runs in the check phase
            doCheck = true;
            checkPhase = ''
              runHook preCheck

              export HOME=$TMPDIR
              echo "▶ Running ${testFile}..."
              ruby -Itest -Ilib ${testFile}

              runHook postCheck
            '';

            # Produce a marker output so Nix has something to cache
            installPhase = ''
              mkdir -p $out
              echo "PASS ${testFile}" > $out/result
              date -u '+%Y-%m-%dT%H:%M:%SZ' > $out/timestamp
            '';
          };

        # ── Build all test derivations from the manifest ────────────
        testDerivations = builtins.mapAttrs (testFile: deps:
          mkTest { inherit testFile; inherit (deps) srcs; }
        ) testDeps;

        # ── Aggregate: build this to run all tests ──────────────────
        allTests = pkgs.symlinkJoin {
          name = "mcpm-tests-all";
          paths = builtins.attrValues testDerivations;
        };

      in {
        packages = {
          tests = allTests;
        }
        # Also expose individual test derivations as packages
        // builtins.mapAttrs (name: drv: drv) testDerivations;

        # Quick check: `nix flake check` runs all tests
        checks.tests = allTests;
      }
    );
}
