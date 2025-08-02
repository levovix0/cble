cble is a [nob](https://github.com/tsoding/nob.h)-like build system for nim (and c).  
currently works only on linux


# Installing
```sh
nimble install https://github.com/levovix0/cble
```

# Running
to run the build for the first time:
```sh
nim c -r package.nim
```

then, the build will automatically rebuild itself if needed, so just run
```sh
./package
```

# Cmd
in [examples/simple](https://github.com/levovix0/cble/tree/main/examples/simple) we have:
```
main.c
package.nim
```

package.nim
```nim
import cble

wrapErrorHandling:
  rebuild_the_build_and_rerun_if_changed("rebuild-build" in argv)

  with_cmd_run:
    cmd.cc
    cmd.output src"main"
    cmd.source src"main.c"
```

`Cmd` is a wrapper around string that remembers if it uses C or Nim compiler and has some procs to append to it.  
for raw string concatenation use `cmd.args.add`, for raw space-separated argument adding use `cmd.add`.

with_cmd_run will create a temporary Cmd named cmd in it's body and execute it shoutly after.

exec is more concise but less flexiable wrapper around with_cmd_run
```nim
exec cc, output(src"main"), source(src"main.c")
```

source can have more that one source
```nim
exec cc, output(src"main"), source(src"a.c", src"b.c")
```


# Path constants
`src` is current source directory, `src"file"` is `src/file`

new path constants can be created via const_path
```
const_path bin: src"bin"
const_path resources: src"resources"
createDir bin
```

make sure setCurrentDirectory is called after rebuild_the_build_and_rerun_if_changed, if you use it


# Package managing
nimble packages can be `require`d and can later be added to Cmd via cmd.useRequiredPackages

[examples/packages](https://github.com/levovix0/cble/tree/main/examples/packages)
```nim
import cble

auto_install_required_packages = "no-package-install" notin argv

wrapErrorHandling:
  require jsony
  require cligen, "1.0"  # with version

  if "list-packages" in argv:
    echo_required_packages()


  with_cmd_run:
    cmd.nimc
    cmd.add "--hints:off"
    cmd.useRequiredPackages
    cmd.output src/"main"
    cmd.source src/"main.nim"
```

`package` can be used instead of `required` for optional dependencies.
```nim
import cble

wrapErrorHandling:
  package jsony

  with_cmd_run:
    cmd.nimc
    
    if jsony.installed:
      cmd.add "-d:useJsony"
      cmd.use jsony
    else:
      cmd.add "-d:useStdJson"

    cmd.output src/"main"
    cmd.source src/"main.nim"
```

cble-based build files previusly was named `build.nim`, but to not conflict with possible build/ folder the package root, it was renamed to `package.nim`


# Running built executable
```nim
import cble

let run_args = argv.split_args(start_from = "run")

# build code ...

if "run" in argv:
  with_cmd_run:
    cmd.add "main"
    for x in run_args: cmd.add x.quoted
```


# Recipes
cble can be used like gnu/make (with timestamp-based lazy-rebuilding and stuff) with recipes

[examples/makefile](https://github.com/levovix0/cble/tree/main/examples/makefile)
```nim
import cble

act_as_makefile:
  const_path bin: "bin"
  createDir bin

  bin"main".recipe bin"main.o":
    exec cc, output(bin"main"), source(bin"main.o")

  bin"main.o".recipe "main.c":
    exec cc, "-c", output(bin"main.o"), source("main.c")

  "run".recipe bin"main":
    exec bin"main"
```
first target will be built as the default

it is not recomended to use src"" prefix for files when acting as makefile

