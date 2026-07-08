# Dogfooding findings

Findings collected while building `capa_ci_pipeline` against the compiler
at `~/Desktop/Capa_language` on `main` (feature arc: #1 composed SBOM, #2
signed capability diff, #4 typed foreign components, #6 capability
policies). Each finding records the command, the input, observed vs
expected behavior, and whether it is a COMPILER issue (for triage) or a
DEMO authoring mistake (fixed here). The compiler repo was not modified.

Summary: 2 compiler findings (1 medium, 1 low), plus the ordinary
demo-authoring fixes. No finding is a soundness hole; both compiler
findings fail SAFE (they over-report authority or fail closed, never
under-report). One of them (F-1) BLOCKS one of the four intended
per-action policies from being demonstrated over the composed graph; the
demo works around it and the blocked policy is called out explicitly.

---

## F-1 (COMPILER, medium): composed SBOM attributes a product-wide UNION of foreign-component caps to every foreign-calling package

- Command:
  `python -m capa --compose-sbom --wasm main.capa`
- Input: the multi-package product. Four action packages each invoke ONE
  typed foreign component with distinct declared caps: `fetch_action`
  (Net), `parse_action` (none), `build_action` (Fs), `publish_action`
  (Net).
- Observed: every foreign-calling package's `composed_capabilities` is
  the UNION of ALL four boundaries' declared caps, `['Fs', 'Net']`,
  regardless of which single boundary that package actually invokes:

  ```
  build_action     attributed=['Fs']  composed=['Fs', 'Net']
  fetch_action     attributed=['Net'] composed=['Fs', 'Net']
  parse_action     attributed=[]      composed=['Fs', 'Net']
  publish_action   attributed=['Net'] composed=['Fs', 'Net']
  ```

  Note `parse_action`, a confined parser that invokes a NO-capability
  boundary, is reported as holding both Net and Fs.
- Expected: each package's composed authority reflects the caps of the
  boundaries IT invokes (`parse_action` -> `[]`, `build_action` ->
  `['Fs']`, etc.). The per-function manifest already records
  `foreign_component_calls` (e.g. `["Fetch.fetch"]`) and each component's
  own `declared_capabilities`, so a per-boundary attribution is derivable
  without new data.
- Root cause: `capa/manifest/_compose.py` (~lines 400-434) computes a
  single `foreign_caps_union` over `manifest["foreign_components"]` (the
  whole linked product) and assigns it to EVERY package with
  `calls_foreign_component`. The in-code comment states this is a
  deliberate "SOUND upper bound", so it is a known over-approximation,
  not an accidental bug.
- Impact: it is sound (over-reports authority, so policies fail safe),
  but it defeats per-action capability policies over the default
  `over = "composed"` view -- exactly the flagship feature-4 + feature-6
  combination ("a compromised action that gains authority is caught by a
  policy scoped to that action"). Concretely it BLOCKS the intended
  `forbid-capability` policy "the parse action must not hold Net": over
  the composed view `parse_action` appears to hold Net, so the policy
  fires as a FALSE POSITIVE on the clean product.
- Demo workaround:
  1. The exfil-vector exclusion ("build action must not hold Net AND Fs")
     is expressed with `over = "attributed"`, which reads each package's
     PRECISE attributed caps (`build_action` -> `['Fs']` in v1). This
     passes clean on v1 and correctly fails on the compromised v2 (where
     `build_action`'s attributed caps gain Net). So the headline rule is
     demonstrated honestly.
  2. `forbid-capability` has no `over` option (it always reads the
     composed union), so "parse must not hold Net" cannot be shown over
     the composed graph. It is REPLACED in `capa-policy.toml` by a
     working, precise `forbid-capability` ("no action may hold Proc"), and
     the parser-cannot-reach-the-network guarantee is instead demonstrated
     two other ways: structurally at runtime (negative N1: the compromised
     parser is denied at instantiation) and by construction (the parse
     boundary declares no capability parameter at all).
- Suggested fix for triage: attribute foreign-boundary caps per invoking
  package using the per-function `foreign_component_calls` -> component
  `declared_capabilities` mapping, instead of the product-wide union; or
  add an `over = "attributed"` option to `forbid-capability` / `purity`.

## F-2 (COMPILER, low): `--check-capabilities` ignores the `--wasm` sandbox posture

- Command:
  `python -m capa --check-capabilities --wasm main.capa`
- Input: the product with per-package `[capabilities]` ceilings (an
  earlier version of the demo declared them).
- Observed: FAILED with "composed authority is UNKNOWN ... not
  runtime-enforced on this backend (only the Wasm-sandbox posture
  enforces it)" for every foreign-calling package, even though `--wasm`
  was passed.
- Expected: consistent with `--compose-sbom --wasm` /
  `--check-policies --wasm` / `--conformance-report --wasm`, all of which
  DO thread the wasm-sandbox posture from `--wasm` and treat the foreign
  boundaries as bounded (not TOP).
- Root cause: in `capa/cli.py` the `--check-capabilities` branch calls
  `build_composed_sbom(module, manifest, root_dir)` with no
  `enforcement=` argument, so it defaults to posture `"none"`. The
  sibling subcommands pass `enforcement = "wasm-sandbox" if args.wasm
  else "none"`.
- Impact: low. `--check-capabilities` is not one of the four features
  exercised here, and it fails CLOSED (never a false pass). But a
  per-package ceiling on a foreign-calling package cannot be verified even
  under `--wasm`.
- Demo workaround: the per-package `[capabilities]` ceilings were removed;
  the product's authority limits are expressed with the organization
  `capa-policy.toml` instead (which does honor `--wasm`).
- Suggested fix for triage: thread `enforcement = "wasm-sandbox" if
  args.wasm else "none"` into the `--check-capabilities` compose call, the
  same way the other three subcommands already do.

## D-1 (DEMO): ordinary authoring fixes

Fixed in this repository; recorded for completeness.

- Capa line comments are `//`, not `#`. (`#` is only for `.toml`.)
- Several modules named `api.capa` collide on the import alias `api`;
  disambiguated with `import <pkg>.api as <alias>` and qualified calls
  (`core.banner(...)`, `fetch.run_fetch(...)`).
- The compiler rejects an unused capability parameter; a genuinely-unused
  cap param in a negative fixture must be `_`-prefixed
  (`deploy(_net: Net, _fs: Fs)`), which still attributes the capability.
- Vendored dependencies are declared as PATH deps (`path =
  "vendor/<name>"`) so the whole product builds, composes, runs, and is
  policy-checked with no network and no `capa install` / GPG step. Git
  deps would require a `capa.lock` and signature verification on the
  build path.
- A typed foreign-component artifact path is resolved relative to the
  ROOT source file being run, so the four action `.wasm` components live
  at the product root (where `main.capa` is), not inside each vendored
  package directory. `scripts/build_fixtures.sh` copies them there.
