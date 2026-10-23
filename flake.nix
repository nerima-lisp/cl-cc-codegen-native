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
      url = "github:nerima-lisp/cl-cc-ast/a45c5acecfccb91a43f6a04251e8a5d6ec3d3213";
      flake = false;
    };
    cl-cc-type = {
      url = "github:nerima-lisp/cl-cc-type/ff2e742911b4b193457a75208b7b9ad6b06ab23a";
      flake = false;
    };
    cl-cc-bootstrap = {
      url = "github:nerima-lisp/cl-cc-bootstrap/027f6c9826010c15789454e69abd2930738b50af";
      flake = false;
    };
    cl-cc-runtime = {
      url = "github:nerima-lisp/cl-cc-runtime/d23ea44512b162def39ec981426c4c8e1af4df84";
      flake = false;
    };
    cl-cc-vm = {
      url = "github:nerima-lisp/cl-cc-vm/462213fcf5e0e6cecc09992e8cb0b7ed48dbce2f";
      flake = false;
    };
    # Also provides cl-cc-target (folded in 2026-08-01: the two were always
    # co-consumed as a pair and combined under 1000 loc). No separate
    # cl-cc-target input any more -- both systems come from this one source
    # tree via CL_SOURCE_REGISTRY below.
    cl-cc-mir = {
      url = "github:nerima-lisp/cl-cc-mir/663c4c01c800ca7e64d444c53204645173e84854";
      flake = false;
    };
    cl-cc-binary = {
      url = "github:nerima-lisp/cl-cc-binary/4c0661c1b2e22be5f28277b0d563eea6651c51e3";
      flake = false;
    };
    cl-cc-optimize = {
      url = "github:nerima-lisp/cl-cc-optimize/f6cd93f54b4e04083aad0f3fee30def14a427f89";
      flake = false;
    };
    cl-prolog-kit = {
      url = "github:nerima-lisp/cl-prolog-kit/v1.5.0";
      flake = false;
    };
    cl-parser-kit = {
      url = "github:nerima-lisp/cl-parser-kit/v1.1.1";
      flake = false;
    };
    # These inputs satisfy cl-log-kit v2.2.0's ASDF dependencies; the shared
    # source registry below makes each system discoverable to ASDF.
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v2.2.0";
      flake = false;
    };
    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit/v3.4.0";
      flake = false;
    };
    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.6.0";
      flake = false;
    };
    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.2.0";
      flake = false;
    };
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v2.3.0";
      flake = false;
    };
    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v1.1.1";
      flake = false;
    };
    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.6.1";
      flake = false;
    };
    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      flake = false;
    };
    cl-regex-kit = {
      url = "github:nerima-lisp/cl-regex-kit/v2.2.0";
      flake = false;
    };
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.6.1";
      flake = false;
    };
    # Pin a release because a bare GitHub reference follows the default branch.
    # As a flake input, cl-weave is available to ASDF through CL_SOURCE_REGISTRY.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # `mkLintCheck` provides `checks.paredit-lint`: a parse-balance gate over
    # every .lisp/.asd file, separate from and cheaper than compiling them.
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.6.3";
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
      cl-prolog-kit,
      cl-parser-kit,
      cl-log-kit,
      cl-date-kit,
      cl-concurrent-kit,
      cl-host-kit,
      cl-regex-kit,
      cl-tty-kit,
      cl-process-kit,
      cl-codec-kit,
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
      # happens on Linux.
      systems = [
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # CL_SOURCE_REGISTRY for the test, coverage and dev environments.
      # cl-cc-mir's own source tree also provides cl-cc-target (folded in
      # 2026-08-01), so one ${cl-cc-mir}//: entry resolves both systems.
      sourceRegistry = "${cl-weave}//:${cl-cc-ast}//:${cl-cc-type}//:${cl-cc-bootstrap}//:${cl-cc-runtime}//:${cl-cc-vm}//:${cl-cc-mir}//:${cl-cc-binary}//:${cl-cc-optimize}//:${cl-prolog-kit}//:${cl-parser-kit}//:${cl-log-kit}//:${cl-date-kit}//:${cl-concurrent-kit}//:${cl-host-kit}//:${cl-regex-kit}//:${cl-tty-kit}//:${cl-process-kit}//:${cl-codec-kit}//:${cl-json-kit}//:${cl-boundary-kit}//:${self}//";

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
      # YAML stays out because YAML formatters can rewrite GitHub Actions'
      # `on:` key; MkDocs validates docs with a strict build.
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

          orphan-tests =
            pkgs.runCommand "cl-cc-codegen-native-orphan-tests"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.coreutils
                  pkgs.findutils
                ];
                CL_SOURCE_REGISTRY = sourceRegistry;
              }
              ''
                set -eu

                export HOME="$TMPDIR/home"
                mkdir -p "$HOME" "$out"
                source_root="${self}"

                find "$source_root" -type f -name '*.asd' -print | sort > "$TMPDIR/asd-files"
                # The root run-tests.lisp is the test entrypoint invoked by the default check.
                # This gate tracks ASDF-loaded test sources, not entrypoint scripts.
                find "$source_root" -type f -name '*.lisp' -print \
                  | awk -v root="$source_root/" '
                      {
                        relative = substr($0, length(root) + 1)
                        count = split(relative, parts, "/")
                        candidate = tolower(parts[count]) ~ /test/ &&
                                    tolower(relative) != "run-tests.lisp"
                        for (i = 1; i < count; i++) {
                          directory = tolower(parts[i])
                          if (directory == "t" || directory ~ /test/) candidate = 1
                        }
                        if (candidate) print relative
                      }
                    ' \
                  | sort -u > "$TMPDIR/candidates"

                asd_count="$(wc -l < "$TMPDIR/asd-files")"
                candidate_count="$(wc -l < "$TMPDIR/candidates")"
                if [ "$asd_count" -eq 0 ]; then
                  echo "No local ASDF systems found" >&2
                  exit 1
                fi
                if [ "$candidate_count" -eq 0 ]; then
                  echo "No test or test-support Lisp files found" >&2
                  exit 1
                fi

                cat > "$TMPDIR/orphan-tests.lisp" <<'LISP'
                (require :asdf)

                (defvar *orphan-source-root*
                  (uiop:ensure-directory-pathname
                   (truename (uiop:getenv "ORPHAN_SOURCE_ROOT"))))
                (defvar *orphan-loaded-files* nil)
                (defvar *orphan-test-named-systems* nil)

                (defun orphan-relative-path (pathname)
                  (let ((root (namestring *orphan-source-root*))
                        (file (namestring (truename pathname))))
                    (when (and (>= (length file) (length root))
                               (string= root file :end2 (length root)))
                      (subseq file (length root)))))

                (defmethod asdf:perform :around
                    ((operation asdf:load-op) (component asdf:component))
                  (declare (ignore operation))
                  (let ((pathname (ignore-errors (asdf:component-pathname component))))
                    (when (and pathname (probe-file pathname))
                      (let ((relative (orphan-relative-path pathname)))
                        (when relative
                          (pushnew relative *orphan-loaded-files* :test #'string=)))))
                  (call-next-method))

                (with-open-file (systems (uiop:getenv "ORPHAN_ASD_FILES"))
                  (loop for asd = (read-line systems nil nil)
                        while asd
                        do (asdf:load-asd asd)))

                ;; Load local ASDF systems whose names contain "test"; the default check runs test-op.
                (let ((test-named-systems
                        (loop for name in (asdf:registered-systems)
                              for system = (asdf:find-system name nil)
                              for source = (and system (asdf:system-source-file system))
                              when (and source
                                        (search "test" name :test #'char-equal)
                                        (orphan-relative-path source))
                                collect name)))
                  (when (null test-named-systems)
                    (error "No local ASDF system names containing test found"))
                  (dolist (name (sort test-named-systems #'string<))
                    (asdf:load-system name)
                    (pushnew name *orphan-test-named-systems* :test #'equal)))

                (with-open-file (output (uiop:getenv "ORPHAN_LOADED_FILES")
                                        :direction :output :if-exists :supersede)
                  (dolist (path (sort *orphan-loaded-files* #'string<))
                    (format output "~a~%" path)))
                (with-open-file (output (uiop:getenv "ORPHAN_TEST_NAMED_SYSTEMS")
                                        :direction :output :if-exists :supersede)
                  (dolist (name (sort *orphan-test-named-systems* #'string<))
                    (format output "~a~%" name)))
                (uiop:quit 0)
                LISP

                export ORPHAN_SOURCE_ROOT="$source_root"
                export ORPHAN_ASD_FILES="$TMPDIR/asd-files"
                export ORPHAN_LOADED_FILES="$TMPDIR/loaded-files"
                export ORPHAN_TEST_NAMED_SYSTEMS="$TMPDIR/test-named-systems"
                sbcl --script "$TMPDIR/orphan-tests.lisp"

                sort -u "$TMPDIR/loaded-files" -o "$TMPDIR/loaded-files"
                comm -23 "$TMPDIR/candidates" "$TMPDIR/loaded-files" > "$TMPDIR/orphans"
                loaded_count="$(comm -12 "$TMPDIR/candidates" "$TMPDIR/loaded-files" | wc -l)"
                orphan_count="$(wc -l < "$TMPDIR/orphans")"
                test_named_system_count="$(wc -l < "$TMPDIR/test-named-systems")"
                echo "Test/test-support Lisp candidates: $candidate_count"
                echo "Candidates loaded by local ASDF systems with test in the name: $loaded_count"
                echo "Local ASDF systems with test in the name loaded by LOAD-OP: $test_named_system_count"
                if [ "$orphan_count" -gt 0 ]; then
                  echo "Orphan test files:" >&2
                  cat "$TMPDIR/orphans" >&2
                  exit 1
                fi
                touch "$out/passed"
              '';

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
