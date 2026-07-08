# capa_ci_pipeline

A build/release orchestrator, written as a multi-package Capa PRODUCT,
that runs a sequence of untrusted third-party "actions" as
sandbox-confined typed foreign Wasm components. It is a showcase for four
Capa capabilities working together end to end:

- **#4 typed foreign components** - each action is declared as
  `extern component <Name> from "<file>.wasm"` with a typed,
  capability-bearing method. The sandbox grants each action ONLY the
  capability it declares.
- **#1 composed SBOM** - `--compose-sbom` rolls the whole product's
  capability surface up over the dependency graph: the pure core is a
  zero-capability node, and each foreign-action boundary is a bounded
  node.
- **#6 capability policies** - an organization `capa-policy.toml` states
  product-wide compliance rules that `--check-policies` enforces and
  `--conformance-report` turns into signed evidence.
- **#2 signed capability diff** - `--capability-diff` between two
  releases shows exactly which authority each function gained or lost;
  `--fail-on-widening` is a CI gate.

## The story

A CI system runs four third-party actions in order:

| action  | job                          | capability it may hold |
|---------|------------------------------|------------------------|
| fetch   | download the source manifest | **Net** only           |
| parse   | normalize the package spec   | **nothing** (confined parser) |
| build   | compile in the checkout      | **Fs** only            |
| publish | upload the built artifact     | **Net** only           |

Each action is a hand-assembled Wasm Component Model artifact (see
`actions/src/*.wat` / `*.wit`). The orchestrator holds Net, Fs and Stdio,
but hands each action only the one capability its boundary declares -
and Net is first attenuated to the registry host. The parser is the
supply-chain punch line: it is granted NO capability, so even a hostile
parser cannot read a file or open a socket.

Then a later release of the build action is COMPROMISED (the "node-ipc
moment"): it quietly gains Net. Two independent Capa guarantees catch it
- the signed capability diff, and the organization exclusion policy.

## Layout

```
capa.toml                 root product manifest (path deps into vendor/)
main.capa                 the orchestrator
capa-policy.toml          organization compliance policies
fetch/parse/build/publish.wasm   the four action components (run from here)
vendor/
  pipeline_core/          PURE core library (DAG/formatting), zero caps
  fetch_action/           extern component Fetch + wrapper (Net)
  parse_action/           extern component Parse  + wrapper (no caps)
  build_action/           extern component Build  + wrapper (Fs)   [v1 clean]
  publish_action/         extern component Publish + wrapper (Net)
v2/                       full product overlay: the COMPROMISED build action
actions/src/              the .wat / .wit sources for every component
scripts/build_fixtures.sh rebuilds every .wasm with wasm-tools
artifacts/                pre-generated manifests for the capability diff
negatives/                the three guarantee-proving negatives
```

## Rebuilding the Wasm fixtures

The `.wasm` files are committed, but you can rebuild them from source
(requires `wasm-tools` on PATH):

```
sh scripts/build_fixtures.sh
```

Each is built exactly like the compiler's own foreign fixtures:
`wasm-tools parse` the `.wat` core module, `wasm-tools component embed
--world <w>` the `.wit`, then `wasm-tools component new`.

---

## Demonstrations

All commands are run from the product root unless noted. Set
`NO_COLOR=1` to match the output shown here.

### #4 Typed foreign components (run the pipeline end to end)

```
python -m capa --wasm --run main.capa
```

Each stage is a confined foreign component. Net is attenuated to
`registry.internal` before fetch/publish; parse holds no capability;
build holds Fs. Observed output:

```
== stage: fetch ==
  fetched: ok:app-1.2.3.tar
== stage: parse ==
  spec: #ok:app-1.2.3.tar
== stage: build ==
  artifact: ok:#ok:app-1.2.3.tar
== stage: publish ==
  published: ok:ok:#ok:app-1.2.3.tar
pipeline ok: true
```

(The `ok:` prefixes come from each action consulting its granted cap's
`allows(...)`; the `#` is the parser's normalization marker. The values
are tokens - the point is the typed, confined boundary, not real build
logic.)

### #1 Composed SBOM

```
python -m capa --compose-sbom --wasm main.capa
```

Emits the canonical composed product SBOM. Under the `--wasm` (wasm
-sandbox) posture the foreign-action boundaries compose as BOUNDED nodes
of their declared caps rather than authority-unknown. The per-package
roll-up (summarized):

```
enforcement_posture: wasm-sandbox
product composed: ['Fs', 'Net', 'Stdio']   authority_unknown: False

capa_ci_pipeline   attributed=['Fs','Net','Stdio']  composed=['Fs','Net','Stdio']
build_action       attributed=['Fs']                composed=['Fs','Net']
fetch_action       attributed=['Net']               composed=['Fs','Net']
parse_action       attributed=[]                    composed=['Fs','Net']
pipeline_core      attributed=[]                    composed=[]
publish_action     attributed=['Net']               composed=['Fs','Net']
```

`pipeline_core` is a zero-capability node, exactly as a pure library
should be. Each action boundary carries a reason string explaining the
bounded posture, e.g. for `fetch_action`:

> a function in this package invokes a typed foreign component; under the
> Wasm-sandbox enforcement posture the child is instantiated with a
> restricted linker binding ONLY its declared capabilities, so the
> boundary composes as a BOUNDED node of ['Net'] (cap-set host-enforced)

Note the `composed` column shows `['Fs','Net']` on every action, not each
action's own single cap. That is a known compiler over-approximation
(the `attributed` column IS precise); see `DOGFOOD_FINDINGS.md` F-1.

### #6 Capability policies (clean product passes)

```
python -m capa --check-policies --wasm main.capa
```

`capa-policy.toml` declares four organization rules: the core library is
pure; the build action must not hold Net AND Fs; no action may spawn a
process; and product authority must stay within {Net, Fs, Stdio}. On the
clean v1 product they all hold:

```
capa: --check-policies: OK - every declared compliance policy holds.
```

(exit 0)

Signed evidence:

```
python -m capa --conformance-report --wasm main.capa
```

Emits a canonical, byte-reproducible conformance report wrapped in a
content-integrity envelope (a sha256 digest over the canonical bytes with
an empty detached-signature slot for an external signer). `pass` is
`true`, one result per policy, all PASS; two identical runs are
byte-for-byte identical.

### #2 Signed capability diff (the compromised build action)

The `v2/` overlay is the same product one release later, with a
COMPROMISED build action that gained Net. Two pre-generated manifests of
the build action (v1 and v2) live in `artifacts/`; regenerate them with:

```
(cd vendor/build_action    && python -m capa --manifest-digest api.capa) > artifacts/build_action.v1.json
(cd v2/vendor/build_action && python -m capa --manifest-digest api.capa) > artifacts/build_action.v2.json
```

Diff them, failing the build on any widening:

```
python -m capa --capability-diff artifacts/build_action.v1.json artifacts/build_action.v2.json --fail-on-widening
```

The changelog reports that `run_build` GAINED Net (a widening), and the
gate exits non-zero:

```
  "functions": [
    {
      "added": ["Net"],
      "classification": "widening",
      "name": "run_build",
      ...
    }
  ]
```

```
capa: --capability-diff: FAILED --fail-on-widening: 1 widening(s)
```

(exit 1)

The same regression is caught by the policy gate. Run the check on the
compromised overlay (from inside `v2/`):

```
cd v2 && python -m capa --check-policies --wasm main.capa
```

The exfil-vector exclusion fires: the build action now holds Net AND Fs.

```
capa: --check-policies: FAILED - 1 policy(ies), 1 violation(s):
  policy 'build-no-net-and-fs' (kind exclusion):
    - [violation] package 'build_action' holds all of ['Fs', 'Net'] simultaneously (attributed capabilities), which policy 'build-no-net-and-fs' forbids
```

(exit 1)

---

## Negatives (proving the guarantees)

### N1 - an action importing an un-granted capability is denied at instantiation

`negatives/ungranted_cap/` holds a COMPROMISED parser
(`mal_parse.wasm`): its exported `parse` looks honest, but the component
secretly imports `capa:host/net`. The Capa declaration grants it no
capability, so the sandbox refuses to instantiate it.

```
cd negatives/ungranted_cap && python -m capa --wasm --run prog.capa
```

```
capa: foreign component Parse.parse: instantiation denied -- the component imports a capability interface the call did not grant (granted: none). Underlying: component imports instance `capa:host/net`, but a matching implementation was not found in the linker
```

(exit 1) The parser never runs; it never reaches the network.

### N2 - a policy-violating configuration is rejected, naming the package

`negatives/net_and_fs_action/` is a product whose action holds both Net
and Fs (ordinary parameters, so attribution is exact), tripping a
product-wide exclusion.

```
cd negatives/net_and_fs_action && python -m capa --check-policies main.capa
```

```
capa: --check-policies: FAILED - 1 policy(ies), 1 violation(s):
  policy 'no-net-and-fs' (kind exclusion):
    - [violation] package 'net_and_fs_action' holds all of ['Fs', 'Net'] simultaneously (composed capabilities), which policy 'no-net-and-fs' forbids
```

(exit 1)

### N3 - an unresolvable / native action composes as authority-unknown, and policy fails closed

`negatives/native_action/` declares a dependency on `legacy_action`,
which ships a `capa.toml` but no Capa source (a native action). Its
authority cannot be derived, so the product composes as authority
-UNKNOWN and a policy over it fails CLOSED (distinct from a concrete
violation).

```
cd negatives/native_action && python -m capa --compose-sbom --wasm main.capa   # product authority_unknown: True
cd negatives/native_action && python -m capa --check-policies --wasm main.capa
```

```
capa: --check-policies: FAILED - 1 policy(ies), 1 violation(s):
  policy 'product-authority' (kind product-subset):
    - [authority_unknown] the product's composed authority is UNKNOWN: 'legacy_action' of 'native_prod' (package has a capa.toml but no Capa source (native / non-Capa dependency; its authority cannot be derived)) (via native_prod); a product-subset policy cannot be proven over an unanalyzable subtree. Set allow_unknown = true to waive.
```

(exit 1)

---

## Notes and honesty

Building this demo surfaced two compiler findings, recorded in
`DOGFOOD_FINDINGS.md`. The important one (F-1) is that the composed SBOM
attributes a product-wide UNION of foreign-component capabilities to
every foreign-calling package, which over-reports per-action authority.
It is sound (it never under-reports), but it blocked one intended policy
("the parse action must not hold Net") from being demonstrated over the
composed graph. That policy was replaced by a working precise one, and
the parser-confinement guarantee is instead shown structurally at runtime
(N1) and by construction (the parse boundary declares no capability). The
exfil-vector exclusion uses `over = "attributed"` to read the precise,
per-package caps, which is why it passes clean on v1 and correctly fails
on the compromised v2.

Every command and output above was run against the compiler and
transcribed, not invented.
