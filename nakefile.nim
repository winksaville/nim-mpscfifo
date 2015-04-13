import nake

#cao.parseArgsOpts()

var
  buildArtifacts = @["nimcache", "mpscfifo", "tests/nimcache", "tests/t1"]
  #buildFlags = "-d:release --verbosity:1 --hints:off --warnings:off --threads:on --embedsrc --lineDir:on"
  buildFlags = "-d:release --verbosity:3 --hints:off --warnings:on --threads:on --embedsrc --lineDir:on --parallelBuild:1"

  docFlags = ""
  docFiles: seq[string] = @[]
  exampleFiles: seq[string] = @[]

proc compileNim(fullPath: string) =
  echo "nim c: ", fullPath
  if not shell(nimExe, "c",  buildFlags, fullPath):
    echo "error compiling"
    quit 1

proc runNim(fullPath: string) =
  echo "run: ", fullPath
  if not shell(fullPath):
    echo "error running: file=", fullPath
    quit 1

proc fullCompileRun(fullPath: string) =
  runTask "clean"
  runTask "docs"
  compileNim(fullPath)
  runNim(fullPath)

task "t1", "Clean, Compile and run the tests":
  fullCompileRun("tests/t1")

task "build-t1", "Build t1":
  compileNim("tests/t1")

task "run-t1", "Run t1":
  runNim("tests/t1")

task "mpscfifo", "build, run mpscfifo":
  compileNim("./mpscfifo")
  runNim("./mpscfifo")

task "docs", "Buiild the documents":
  for file in docFiles:
    if not shell(nimExe, "doc", docFlags, file):
      echo "error generating docs"
      quit 1

task "exmpl", "Build and run the exmpl":
  for file in exampleFiles:
    compileNim(file)
    runNim(file)

task "clean", "clean build artifacts":
  proc removeFileOrDir(file: string) =
    try:
      removeFile(file)
    except OSError:
      try:
        removeDir(file)
      except OSError:
        echo "Could not remove: ", file, " ", getCurrentExceptionMsg()

  for file in buildArtifacts:
    removeFileOrDir(file)

