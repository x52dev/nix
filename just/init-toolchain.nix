{
  coreutils,
  lib,
  writeShellApplication,
  x52Just,
  directory ? ".toolchain",
}:

writeShellApplication {
  name = "x52-init-rust-just";
  runtimeInputs = [ coreutils ];
  text = ''
    toolchain_dir=${lib.escapeShellArg directory}
    mkdir -p "$toolchain_dir"
    ln -sfn ${x52Just}/rust.just "$toolchain_dir/rust.just"
  '';
}
