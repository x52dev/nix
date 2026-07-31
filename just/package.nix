{ runCommand }:

runCommand "x52-just" { } ''
  mkdir -p "$out"
  cp ${./src}/*.just "$out/"
''
