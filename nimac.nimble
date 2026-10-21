version       = "0.1.0"
author        = "Hideto Niimi"
description   = "Download AtCoder samples once, then compile and test C++ solutions."
license       = "MIT"
srcDir        = "src"
bin           = @["nimac"]

requires "nim >= 2.0.0"

task test, "Run the test suite":
  mkDir "build"
  exec "nim c -r --path:src --outdir:build --nimcache:build/test-nimcache tests/test_all.nim"

