// We need to forward routine registration from C to Rust
// to avoid the linker removing the static library.
//
// R calls R_init_<package name>, i.e. R_init_layaR. The Rust crate is named
// laya_r (snake case), so extendr_module! { mod laya_r; } generates
// R_init_laya_r_extendr. rextendr 0.5.0 generated R_init_laya_r here, which R
// never calls for a package named layaR, so it is corrected by hand.

void R_init_laya_r_extendr(void *dll);
void register_extendr_panic_hook(void);

void R_init_layaR(void *dll) {
    register_extendr_panic_hook();
    R_init_laya_r_extendr(dll);
}
