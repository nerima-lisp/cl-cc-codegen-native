{
  description = "Native code generation for the cl-cc Common Lisp compiler: register allocation, instruction selection, encoding and object emission";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-cc-ast = {
      url = "github:nerima-lisp/cl-cc-ast";
      flake = false;
    };
    cl-cc-type = {
      url = "github:nerima-lisp/cl-cc-type";
      flake = false;
    };
    cl-cc-bootstrap = {
      url = "github:nerima-lisp/cl-cc-bootstrap";
      flake = false;
    };
    cl-cc-runtime = {
      url = "github:nerima-lisp/cl-cc-runtime";
      flake = false;
    };
    cl-cc-vm = {
      url = "github:nerima-lisp/cl-cc-vm";
      flake = false;
    };
    cl-cc-mir = {
      url = "github:nerima-lisp/cl-cc-mir";
      flake = false;
    };
    cl-cc-target = {
      url = "github:nerima-lisp/cl-cc-target";
      flake = false;
    };
    cl-cc-binary = {
      url = "github:nerima-lisp/cl-cc-binary";
      flake = false;
    };
    cl-cc-optimize = {
      url = "github:nerima-lisp/cl-cc-optimize";
      flake = false;
    };
    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog";
      flake = false;
    };
    cl-parser-kit = {
      url = "github:nerima-lisp/cl-parser-kit/v1.0.2";
      flake = false;
    };
    # v2.0.0's own dependency chain is cl-date-kit, cl-concurrent-kit and
    # cl-host-kit (declared below) -- discovered one at a time as real ASDF
    # MISSING-DEPENDENCY build failures, not read off cl-log-kit.asd in
    # advance, so this is exactly the source registry v2.0.0 actually needs
    # and no more.
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v2.0.0";
      flake = false;
    };
    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit/v2.0.0";
      flake = false;
    };
    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.0.1";
      flake = false;
    };
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v1.0.0";
      flake = false;
    };
    # cl-log-kit v2.0.0's own dependencies, needed for it to resolve through
    # this repository's source registry.
    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v0.2.0";
      flake = false;
    };
    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.1.0";
      flake = false;
    };
    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.2.1";
      flake = false;
    };
    # Pinned to a release tag. A bare `github:nerima-lisp/cl-weave` follows
    # that repository's default branch, so an upstream push to main would
    # break this repository's CI without warning. This used to be a
    # `flake = false` source tree handed to the runner through an environment
    # variable; it is a normal flake input now, which is what lets ASDF find
    # cl-weave through CL_SOURCE_REGISTRY like any other dependency.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The same structural-refactoring CLI the AI-driven changes in this
    # repository are made with (see AGENTS.md / the paredit-cli skill). Its
    # `mkLintCheck` becomes `checks.paredit-lint` below: a parse-balance gate
    # over every .lisp/.asd file, independent of and much cheaper than
    # actually compiling them.
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      cl-weave,
      cl-cc-ast,
      cl-cc-type,
      cl-cc-bootstrap,
      cl-cc-runtime,
      cl-cc-vm,
      cl-cc-mir,
      cl-cc-target,
      cl-cc-binary,
      cl-cc-optimize,
      cl-prolog,
      cl-parser-kit,
      cl-log-kit,
      cl-date-kit,
      cl-concurrent-kit,
      cl-host-kit,
      cl-process-kit,
      cl-json-kit,
      cl-boundary-kit,
      paredit-cli,
      treefmt-nix,
      ...
    }:
    let
      # CI builds and tests only x86_64-linux, so that is the sole declared
      # system: the flake never advertises a platform it does not verify.
      # aarch64-darwin was dropped on 2026-08-01. Its only verification was a
      # local `nix flake check` on a development machine, and a run nobody can
      # tell was skipped is not a gate. aarch64-linux and x86_64-darwin were
      # already undeclared for the same reason.
      #
      # Consequence, accepted deliberately: every per-system output -- packages,
      # checks, apps AND devShells -- is generated from this one list, so
      # `nix develop` and `nix build` no longer work on macOS. Development
      # happens on Linux. See PACKAGE_STANDARD.md, section "systems".
      systems = [
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # CL_SOURCE_REGISTRY for the test, coverage and dev environments.
      sourceRegistry = "${cl-weave}//:${cl-cc-ast}//:${cl-cc-type}//:${cl-cc-bootstrap}//:${cl-cc-runtime}//:${cl-cc-vm}//:${cl-cc-mir}//:${cl-cc-target}//:${cl-cc-binary}//:${cl-cc-optimize}//:${cl-prolog}//:${cl-parser-kit}//:${cl-log-kit}//:${cl-date-kit}//:${cl-concurrent-kit}//:${cl-host-kit}//:${cl-process-kit}//:${cl-json-kit}//:${cl-boundary-kit}//:${self}//";

      # Single source of truth for the package version: the `:version` form in
      # cl-cc-codegen-native.asd. A release only ever edits the .asd file and every Nix
      # package follows automatically. Nix regexes are whole-string anchored
      # and `.` never spans newlines, so the version is extracted line-by-line
      # rather than with one multi-line match.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./cl-cc-codegen-native.asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate.
      # Scope is Nix only: nixfmt (RFC-style) is a zero-footgun, low-diff
      # formatter, whereas YAML formatters mangle the GitHub Actions `on:`
      # key and there is no docs/ tree here to justify a Markdown formatter
      # either. Mirrors sibling repos' flake.nix, which keep the same Nix-only
      # scope despite also having .github/workflows.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          cl-cc-codegen-native = pkgs.sbcl.buildASDFSystem {
            pname = "cl-cc-codegen-native";
            inherit version;
            src = self;
            systems = [ "cl-cc-codegen-native" ];
          };
          default = cl-cc-codegen-native;
        }
      );

      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching. Add a check here rather than a job in ci.yml.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default =
            pkgs.runCommand "cl-cc-codegen-native-tests"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.perl
                  pkgs.coreutils
                ];
                CL_SOURCE_REGISTRY = sourceRegistry;
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME" "$out"
                perl ${self}/scripts/with-timeout.pl 120 sbcl --script ${self}/run-tests.lisp
                touch "$out/passed"
              '';

          # Fails `nix flake check` when any tracked file is unformatted,
          # turning the formatter into an enforced CI gate.
          formatting = treefmtEval.${system}.config.build.check self;

          # Informational, not gated on a minimum yet: see
          # scripts/run-coverage.lisp for why. Runs the same suite a second
          # time under sb-cover instrumentation and records the percentages
          # in the derivation's build log.
          coverage =
            pkgs.runCommand "cl-cc-codegen-native-coverage"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.perl
                  pkgs.coreutils
                ];
                CL_SOURCE_REGISTRY = sourceRegistry;
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME" "$out"
                perl ${self}/scripts/with-timeout.pl 300 sbcl --script ${self}/scripts/run-coverage.lisp | tee "$out/report.txt"
              '';

          # Parse-balance gate over every .lisp/.asd file: independent of and
          # much cheaper than a full compile, and catches the one class of
          # error paredit-cli structural edits cannot themselves introduce
          # (an unbalanced file) but a hand edit could.
          paredit-lint = paredit-cli.lib.${system}.mkLintCheck {
            src = self;
            name = "cl-cc-codegen-native-paredit-lint";
          };
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          test = pkgs.writeShellApplication {
            name = "cl-cc-codegen-native-test";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.perl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${sourceRegistry}"
              exec perl ${self}/scripts/with-timeout.pl 120 sbcl --script ${self}/run-tests.lisp
            '';
          };
          coverage = pkgs.writeShellApplication {
            name = "cl-cc-codegen-native-coverage";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.perl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${sourceRegistry}"
              exec perl ${self}/scripts/with-timeout.pl 300 sbcl --script ${self}/scripts/run-coverage.lisp
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${test}/bin/cl-cc-codegen-native-test";
          };
          test = {
            type = "app";
            program = "${test}/bin/cl-cc-codegen-native-test";
          };
          coverage = {
            type = "app";
            program = "${coverage}/bin/cl-cc-codegen-native-coverage";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.sbcl
              pkgs.perl
              pkgs.coreutils
              paredit-cli.packages.${system}.default
            ];
            CL_SOURCE_REGISTRY = sourceRegistry;
          };
        }
      );
    };
}
