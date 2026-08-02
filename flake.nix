{
  description = "Native code generation for the cl-cc Common Lisp compiler: register allocation, instruction selection, encoding and object emission";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The cl-cc-* siblings below are pinned to 40-character commit SHAs, not to
    # release tags. Every one of them was a bare `github:nerima-lisp/<name>`
    # reference, which follows the default branch: an upstream push changed this
    # build with no change here and no warning.
    #
    # A SHA rather than a tag, deliberately. cl-cc-mir (which also provides
    # cl-cc-target, folded in 2026-08-01 -- see its own flake.nix / README for
    # why) has published no tags at all, so a SHA is the only immutable target
    # that exists for it -- the case CONFORMANCE.md names when it accepts a
    # SHA as equivalent to a tag. For the rest, the tags that do exist are older than
    # the default-branch commits this repository has actually been building
    # against, so pinning to them would move the build backwards rather than
    # freeze it. These SHAs are the commits the bare references already
    # resolved to, so the build does not change; only the drift stops.
    #
    # Re-resolve before bumping, and do not copy a SHA you have not resolved:
    #   gh api repos/nerima-lisp/<name>/commits/main --jq .sha
    cl-cc-ast = {
      url = "github:nerima-lisp/cl-cc-ast/ad554c7a7401cdf454707eb56a37da6aaaea2a95";
      flake = false;
    };
    cl-cc-type = {
      url = "github:nerima-lisp/cl-cc-type/adf449080c07dea93bd7947f51b6eba8277a7bf6";
      flake = false;
    };
    cl-cc-bootstrap = {
      url = "github:nerima-lisp/cl-cc-bootstrap/821bc1f853dbdad2a66e852216d651a7deee5ad2";
      flake = false;
    };
    cl-cc-runtime = {
      url = "github:nerima-lisp/cl-cc-runtime/e47f0917abc759f4798633cfa427f30ad08eb277";
      flake = false;
    };
    cl-cc-vm = {
      url = "github:nerima-lisp/cl-cc-vm/4508154e0a170c2dc7647825f7b41741e1de1ff7";
      flake = false;
    };
    # Also provides cl-cc-target (folded in 2026-08-01: the two were always
    # co-consumed as a pair and combined under 1000 loc). No separate
    # cl-cc-target input any more -- both systems come from this one source
    # tree via CL_SOURCE_REGISTRY below.
    cl-cc-mir = {
      url = "github:nerima-lisp/cl-cc-mir/9679e3a471df1bea446df9b22cb26a32e85c42c8";
      flake = false;
    };
    cl-cc-binary = {
      url = "github:nerima-lisp/cl-cc-binary/b70205834e711181bd2c2ec0299bd5c3ab5e0673";
      flake = false;
    };
    cl-cc-optimize = {
      url = "github:nerima-lisp/cl-cc-optimize/9f0587ea9211ea4d234b045cfb8d71a1fb40bab4";
      flake = false;
    };
    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog/c0b22e98b0ac54f94e0949ed1e2b347f36a78635";
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
    cl-regex-kit = {
      url = "github:nerima-lisp/cl-regex-kit/d7d1a0e4d5a15765b1f781993949ae2e3cb796f9";
      flake = false;
    };
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.0.3";
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
      cl-cc-binary,
      cl-cc-optimize,
      cl-prolog,
      cl-parser-kit,
      cl-log-kit,
      cl-date-kit,
      cl-concurrent-kit,
      cl-host-kit,
      cl-regex-kit,
      cl-tty-kit,
      cl-process-kit,
      cl-json-kit,
      cl-boundary-kit,
      paredit-cli,
      treefmt-nix,
      ...
    }:
    let
      # x86_64-linux is what CI gates; aarch64-darwin is the development
      # machine. Every per-system output -- packages, checks, apps AND devShells
      # -- comes from this one list, so leaving aarch64-darwin out takes `nix
      # build` and `nix develop` off the development machine as well. That trade
      # was made on 2026-08-01 and reverted on 2026-08-02; aarch64-darwin carries
      # no CI gate, which PACKAGE_STANDARD.md's "systems" section accepts
      # explicitly. aarch64-linux and x86_64-darwin are nobody's verification and
      # are not declared.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # CL_SOURCE_REGISTRY for the test, coverage and dev environments.
      # cl-cc-mir's own source tree also provides cl-cc-target (folded in
      # 2026-08-01), so one ${cl-cc-mir}//: entry resolves both systems.
      sourceRegistry = "${cl-weave}//:${cl-cc-ast}//:${cl-cc-type}//:${cl-cc-bootstrap}//:${cl-cc-runtime}//:${cl-cc-vm}//:${cl-cc-mir}//:${cl-cc-binary}//:${cl-cc-optimize}//:${cl-prolog}//:${cl-parser-kit}//:${cl-log-kit}//:${cl-date-kit}//:${cl-concurrent-kit}//:${cl-host-kit}//:${cl-regex-kit}//:${cl-tty-kit}//:${cl-process-kit}//:${cl-json-kit}//:${cl-boundary-kit}//:${self}//";

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

          # Rendered documentation site (Material for MkDocs).
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          #
          # The fileset is rooted at ./docs so that mkdocs.yml's own relative
          # paths (docs_dir: src) resolve the same way they do for a
          # contributor running `mkdocs build --config-file docs/mkdocs.yml`
          # by hand. --site-dir overrides the config's `site_dir: ../site`,
          # which would otherwise try to write outside the build directory.
          docs = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-cc-codegen-native-docs";
            inherit version;
            src = pkgs.lib.fileset.toSource {
              root = ./docs;
              fileset = pkgs.lib.fileset.unions [
                ./docs/mkdocs.yml
                ./docs/src
              ];
            };
            nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
            buildPhase = ''
              runHook preBuild
              mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
              runHook postBuild
            '';
            dontInstall = true;
            meta = {
              description = "Rendered MkDocs (Material) documentation for cl-cc-codegen-native";
              homepage = "https://github.com/nerima-lisp/cl-cc-codegen-native";
              license = pkgs.lib.licenses.mit;
            };
          };
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

          # The docs package builds with `mkdocs --strict`, so a broken link or
          # a page missing from the nav fails the build. Without this the docs
          # are only ever built by the publish workflow, which runs after a
          # merge to main, meaning such a break surfaces as a failed deploy
          # rather than as a failed pull request.
          docs = self.packages.${system}.docs;

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
