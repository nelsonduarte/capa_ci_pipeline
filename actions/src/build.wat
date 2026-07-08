;; build action (Fs only).
;;
;; Imports capa:host/fs.allows and exports build(spec) -> string.
;; Consults fs.allows("/workspace") to prove the Fs it holds is the
;; caller's attenuated capability, then returns "ok:"/"no:" + the echoed
;; spec. Token logic; the fs.allows signature (handle, path -> bool) has
;; the same wire shape as net.allows, so the WAT body mirrors fetch.
(module
  (import "capa:host/fs" "allows" (func $allows (param i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 8) "/workspace")
  (data (i32.const 32) "ok:")
  (data (i32.const 40) "no:")
  (global $bump (mut i32) (i32.const 1024))
  (func $realloc (export "cabi_realloc") (param i32 i32 i32 i32) (result i32)
    (local $p i32)
    global.get $bump i32.const 7 i32.add i32.const -8 i32.and local.set $p
    local.get $p local.get 3 i32.add global.set $bump local.get $p)
  (func $build (export "build") (param $sptr i32) (param $slen i32) (result i32)
    (local $out i32) (local $ret i32) (local $pfx i32)
    (local.set $pfx (if (result i32)
      (i32.const 0) (i32.const 8) (i32.const 10) (call $allows)
      (then (i32.const 32)) (else (i32.const 40))))
    (local.set $out (call $realloc (i32.const 0)(i32.const 0)(i32.const 1)(i32.add (local.get $slen)(i32.const 3))))
    (memory.copy (local.get $out) (local.get $pfx) (i32.const 3))
    (memory.copy (i32.add (local.get $out)(i32.const 3)) (local.get $sptr) (local.get $slen))
    (local.set $ret (call $realloc (i32.const 0)(i32.const 0)(i32.const 4)(i32.const 8)))
    (i32.store (local.get $ret) (local.get $out))
    (i32.store offset=4 (local.get $ret) (i32.add (local.get $slen)(i32.const 3)))
    (local.get $ret)))
