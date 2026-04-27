{
  description = "mcpm – incremental test builds (per-method)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ruby = pkgs.ruby_4_0;

        gems = pkgs.bundlerEnv {
          name = "mcpm-gems";
          inherit ruby;
          gemdir = ./.;
          buildInputs = [ pkgs.libyaml ];
        };

        # ── Per-method test manifest (auto-generated) ───────────────
        # Produced by: bin/trace-deps --all && bin/compile-test-deps
        # Each entry has: name, testFile, methodName, deps
        # deps are ONLY the files whose code executed during that
        # method at runtime (Rotoscope-traced, not require-based).
        testMethods = import ./nix/test-deps.nix;

        # ── Per-method derivation builder ───────────────────────────
        # Each test method is its own derivation. The src contains
        # ONLY the files that executed during that method. If none
        # of them change, Nix skips the test entirely (cache hit).
        mkMethodTest = { name, testFile, methodName, deps, bootDeps }:
          let
            # Runtime deps (from Rotoscope) are the CACHE KEY — changing
            # these triggers a rebuild. Boot deps (from $LOADED_FEATURES)
            # are files needed to load the test but don't affect the
            # result. Both are included in src, but only runtime deps
            # drive invalidation in practice because boot deps are stable
            # (they only change when require statements change, which
            # would also change the source file — a runtime dep).
            allFiles = pkgs.lib.lists.unique (deps ++ bootDeps);

            testSrc = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions (
                (map (f: ./. + "/${f}") allFiles)
                ++ [ ./test/fixtures ]
              );
            };
          in
          pkgs.stdenv.mkDerivation {
            name = "mcpm-test-${name}";
            src = testSrc;

            nativeBuildInputs = [ gems ruby gems.wrappedRuby ];

            dontConfigure = true;
            dontBuild = true;

            doCheck = true;
            checkPhase = ''
              runHook preCheck
              export HOME=$TMPDIR
              echo "▶ ${name}"
              ruby -Itest -Ilib ${testFile} --name ${methodName}
              runHook postCheck
            '';

            installPhase = ''
              mkdir -p $out
              echo "PASS ${name}" > $out/result
            '';
          };

        # ── Build all method derivations ────────────────────────────
        testDerivations = map mkMethodTest testMethods;

        # Named attribute set for individual access
        testsByName = builtins.listToAttrs (
          map (t: {
            name = t.name;
            value = mkMethodTest t;
          }) testMethods
        );

        # ── Aggregate ───────────────────────────────────────────────
        allTests = pkgs.symlinkJoin {
          name = "mcpm-tests-all";
          paths = testDerivations;
        };

      in {
        packages = {
          tests = allTests;
        } // testsByName;

        checks.tests = allTests;
      }
    );
}
