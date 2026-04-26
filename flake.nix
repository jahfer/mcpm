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
          buildInputs = [ pkgs.libyaml ];
        };

        # ── Test dependency manifest (auto-generated) ───────────────
        # Produced by: bin/trace-deps --all && bin/compile-test-deps
        testDeps = import ./nix/test-deps.nix;

        # ── Tier 1: shared deps (test_helper.rb + its transitive requires)
        sharedFiles = testDeps._shared.srcs;

        # ── Per-test entries (everything except _shared) ────────────
        perTestDeps = builtins.removeAttrs testDeps [ "_shared" ];

        # ── Per-test derivation builder ─────────────────────────────
        mkTest = testFile: { srcs }:
          let
            # All files this test needs: the test itself + per-test srcs + shared srcs + fixtures
            allFiles =
              [ testFile ]
              ++ srcs
              ++ sharedFiles;

            testSrc = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions (
                # Precise file-level deps from Rotoscope tracing
                (map (f: ./. + "/${f}") allFiles)
                # Fixtures are directories, always included
                ++ [ ./test/fixtures ]
              );
            };

            safeName = builtins.replaceStrings [ "/" "." ] [ "-" "_" ] testFile;
          in
          pkgs.stdenv.mkDerivation {
            name = "mcpm-test-${safeName}";
            src = testSrc;

            nativeBuildInputs = [ gems ruby gems.wrappedRuby ];

            dontConfigure = true;
            dontBuild = true;

            doCheck = true;
            checkPhase = ''
              runHook preCheck
              export HOME=$TMPDIR
              echo "▶ Running ${testFile}..."
              ruby -Itest -Ilib ${testFile}
              runHook postCheck
            '';

            installPhase = ''
              mkdir -p $out
              echo "PASS ${testFile}" > $out/result
              date -u '+%Y-%m-%dT%H:%M:%SZ' > $out/timestamp
            '';
          };

        # ── Build all test derivations from the manifest ────────────
        testDerivations = builtins.mapAttrs mkTest perTestDeps;

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
        // builtins.mapAttrs (_: drv: drv) testDerivations;

        # Quick check: `nix flake check` runs all tests
        checks.tests = allTests;
      }
    );
}
