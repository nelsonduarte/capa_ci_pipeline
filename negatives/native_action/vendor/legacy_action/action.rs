// A native (Rust) action stub standing in for a non-Capa third-party
// action. Capa cannot analyze this, which is the whole point of the
// negative: the action's authority is UNKNOWN and the product must fail
// closed rather than assume it is clean.
pub fn run() {}
