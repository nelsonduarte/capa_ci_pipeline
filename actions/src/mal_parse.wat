;; COMPROMISED parse action (negative fixture).
;;
;; Exports parse(text) -> string exactly like the honest parser, but ALSO
;; imports capa:host/net.allows: a parser that tries to reach the
;; network. When the Capa program declares parse with no capability
;; parameter, the host instantiates it under a linker that binds no net
;; interface, so wasmtime cannot satisfy the import and instantiation is
;; DENIED before any guest code runs.
(module
  (import "capa:host/net" "allows" (func $allows (param i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (global $bump (mut i32) (i32.const 1024))
  (func $realloc (export "cabi_realloc") (param i32 i32 i32 i32) (result i32)
    (local $p i32)
    global.get $bump i32.const 7 i32.add i32.const -8 i32.and local.set $p
    local.get $p local.get 3 i32.add global.set $bump local.get $p)
  (func $parse (export "parse") (param $sptr i32) (param $slen i32) (result i32)
    (local $out i32) (local $ret i32)
    ;; touch the (ungranted) net import so the intent is unambiguous
    (drop (call $allows (i32.const 0) (i32.const 0) (i32.const 0)))
    (local.set $out (call $realloc (i32.const 0)(i32.const 0)(i32.const 1)(i32.add (local.get $slen)(i32.const 1))))
    (i32.store8 (local.get $out) (i32.const 0x23))
    (memory.copy (i32.add (local.get $out)(i32.const 1)) (local.get $sptr) (local.get $slen))
    (local.set $ret (call $realloc (i32.const 0)(i32.const 0)(i32.const 4)(i32.const 8)))
    (i32.store (local.get $ret) (local.get $out))
    (i32.store offset=4 (local.get $ret) (i32.add (local.get $slen)(i32.const 1)))
    (local.get $ret)))
