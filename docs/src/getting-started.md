# Getting Started

This page adds `cl-cc-codegen-native` to a project and compiles one VM program
all the way down to x86-64 machine code.

## Install

=== "Nix flake"

    ```nix
    # flake.nix
    inputs.cl-cc-codegen-native = {
      url = "github:nerima-lisp/cl-cc-codegen-native/v0.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ```

    Pin the tag. Consumers inside the org must not follow the default branch:
    an upstream push would otherwise break your build with no change on your
    side.

=== "ASDF"

    Put the checkout somewhere ASDF can see it, along with the sibling
    systems it depends on, and load the umbrella system:

    ```lisp
    (asdf:load-system "cl-cc-codegen-native")
    ```

Then add the system to your own `.asd`:

```lisp
:depends-on ("cl-cc-codegen-native")
```

`cl-cc-codegen-native` defines no components of its own. It exists so that one
name pulls the whole native backend, and it depends on the three systems that
do the work:

```lisp
:depends-on ("cl-cc-regalloc" "cl-cc-codegen" "cl-cc-emit")
```

Depend on the umbrella unless you have a reason to pull a single subsystem.

This backend consumes the cl-cc VM instruction format, so `cl-cc-vm`,
`cl-cc-mir`, `cl-cc-target`, `cl-cc-optimize`, `cl-cc-runtime` and
`cl-cc-binary` arrive transitively. They are separate repositories and each is
a flake input in turn.

## Compiling a VM program

The backend's input is a `cl-cc/vm:vm-program`: a flat list of instructions
over unlimited virtual registers named `:r0`, `:r1`, and so on. Build a small
one that adds two constants and returns the sum.

```lisp
(asdf:load-system "cl-cc-codegen-native")

(defparameter *program*
  (cl-cc/vm:make-vm-program
   :instructions (list (cl-cc/vm:make-vm-const :dst :r0 :value 3)
                       (cl-cc/vm:make-vm-const :dst :r1 :value 4)
                       (cl-cc/vm:make-vm-add :dst :r2 :lhs :r0 :rhs :r1)
                       (cl-cc/vm:make-vm-ret :reg :r2))
   :result-register :r2))
```

Nothing has assigned a machine register yet. `:r0` through `:r2` are virtual;
a real x86-64 has sixteen general-purpose registers and this program could
just as easily have used two hundred virtual ones.

Compiling resolves that:

```lisp
(defparameter *code* (cl-cc/codegen:compile-to-x86-64-bytes *program*))

(array-element-type *code*)  ; => (UNSIGNED-BYTE 8)
(plusp (length *code*))      ; => T
```

`*code*` is a `(simple-array (unsigned-byte 8) (*))` holding the encoded
instruction bytes, ready to be written into an object file or an executable
page.

## What that call did

`compile-to-x86-64-bytes` runs the whole pipeline. The stages are separately
callable, which matters when you are debugging one of them:

```lisp
;; Liveness: where each virtual register is born and dies.
(defparameter *intervals*
  (cl-cc/regalloc:compute-live-intervals
   (cl-cc/vm:vm-program-instructions *program*)))

(length *intervals*)  ; => 3
```

One `live-interval` per virtual register — `:r0`, `:r1` and `:r2`. Each one
records the instruction index where the register is first written and where it
is last read:

```lisp
(mapcar #'cl-cc/regalloc:interval-vreg *intervals*)
;; => (:R0 :R1 :R2)
```

Allocation consumes those intervals. `cl-cc/regalloc:allocate-registers` takes
the instruction list and a target descriptor and returns a `regalloc-result`,
which carries the virtual-to-physical assignment, the spill map, the register
pressure it observed, and the rewritten instruction stream with spill code
inserted. `compile-to-x86-64-bytes` calls it for you with the descriptor its
own frame-pointer policy implies; call it directly only when you are driving
the stages yourself.

`cl-cc/regalloc:regalloc-lookup` answers the question every later stage asks of
that result — which physical register did this virtual one get?

```lisp
(cl-cc/regalloc:regalloc-lookup result :r2)
;; => a physical register keyword such as :RAX, or NIL when :R2 was spilled
```

## Other targets

The same `vm-program` drives every backend. Each entry point returns a byte
vector except the WebAssembly text one, which returns a string:

```lisp
(cl-cc/codegen:compile-to-aarch64-bytes *program*)
(cl-cc/codegen:compile-to-riscv64-bytes *program*)
(cl-cc/codegen:compile-to-wasm-binary *program*)
(cl-cc/codegen:compile-to-wasm-wat *program*)  ; => "(module ...)"
```

## Running the tests

The suite runs under [cl-weave](https://github.com/nerima-lisp/cl-weave).

```sh
nix flake check      # tests, coverage, formatting, paredit lint, and this docs site
```

Outside Nix, go through the bounded-execution wrapper rather than a bare
`timeout`, which is GNU coreutils and absent by default on macOS:

```sh
perl scripts/with-timeout.pl 120 sbcl --script run-tests.lisp
```

Coverage is measured but not gated:

```sh
nix build .#checks.x86_64-linux.coverage
```

## Where to go next

[Reference: API](reference/api.md) lists the exported symbols of all three
subsystems, grouped by the package that exports them.
