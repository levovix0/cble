# cble - a simple single file build system for c and nim
import tables, times, strformat
export tables, strformat

when defined(nimony):
  import std/[syncio]

else:
  import std/[strutils, os, macros, sequtils]
  export os


when not defined(nimony):
  proc error*(msg: varargs[string, `$`]) =
    raise CatchableError.newException(msg.join)

  template wrapErrorHandling*(body: untyped) =
    try:
      proc main =
        body
      main()
    
    except:
      echo "\27[31mError:\27[0m ", getCurrentExceptionMsg()

else:
  var currentExceptionMsg*: string

  proc errorImpl*(msg: string) {.raises.} =
    currentExceptionMsg = msg
    raise Failure
  
  template error* {.varargs.} =
    var errmsg = ""
    for arg in unpack():
      errmsg.add $arg
    errorImpl(errmsg)
  
  template wrapErrorHandling*(body: untyped) =
    try:
      proc main {.raises.} =
        body
      main()
    
    except:
      echo "\27[31mError:\27[0m ", getCurrentExceptionMsg()
      quit(1)



when not defined(nimony):
  template src*(path = ""): string =
    bind parentDir
    let pathAfter = path
    let theDir = parentDir(instantiationInfo(index = 0, fullPaths = true).filename)
    if pathAfter == "":
      theDir
    else:
      theDir / pathAfter

else:
  ## todo


macro const_path*(name: untyped, path: static string) =
  result = quote do:
    template `name`(path = ""): string =
      bind parentDir
      let pathAfter = path
      let theDir = `path`
      if pathAfter == "":
        theDir
      else:
        theDir / path



when defined(nimony):
  proc c_system(cmd: cstring): cint {.importc: "system", header: "<stdlib.h>".}

  proc execShellCmd*(cmd: string): int =
    c_system(cmd.cstring).int



type
  CmdMode* = enum
    cmdC
    cmdNim

  Cmd* = object
    args*: string
    mode*: CmdMode
    modeCustom*: string
  
  Package* = ref object
    name*: string

    version*: string
    installed*: bool
    path*: string

    expectedVersion: string
  
  Recipe* = ref object
    outFile*: string
    inputs*: seq[string]
    build*: seq[Cmd]


var argv*: seq[string]

for i in 1..paramCount():
  argv.add paramStr(i)

var c_compiler* = "gcc"
var nim_compiler* =
  when defined(nimony): "nimony"
  else: "nim"

var log_exec* = true

var auto_install_required_packages* = true


var package_path* = @[
  getHomeDir() / ".nimble" / "pkgs2",
]

var required_packages*: seq[Package]


var recipes*: OrderedTable[string, Recipe]



proc quoted*(s: string): string =
  result.addQuoted s


proc run*(cmd: Cmd) =
  if log_exec:
    echo "\27[36mExec:\27[37m  ", cmd.args, "\27[0m"

  if (let code = execShellCmd cmd.args; code != 0):
    error "command exited with non-zero code: ", $code


proc reset*(cmd: var Cmd) =
  cmd = Cmd()


proc run_reset*(cmd: var Cmd) =
  run cmd
  reset cmd


template run_reset*(cmd: var Cmd, body: untyped) =
  body
  run cmd
  reset cmd


template with_cmd_run*(body: untyped) =
  block:
    var cmd {.inject.} = Cmd()
    body
    run cmd



proc add*(cmd: var Cmd, args: varargs[string, `$`]) =
  for arg in args:
    if cmd.args.len != 0:
      cmd.args.add " "

    cmd.args.add arg


proc cc*(cmd: var Cmd) =
  cmd.mode = cmdC
  cmd.add c_compiler


proc nim*(cmd: var Cmd) =
  cmd.mode = cmdNim
  cmd.add nim_compiler

proc nimc*(cmd: var Cmd) =
  cmd.mode = cmdNim
  cmd.add nim_compiler, "c"

proc nimcpp*(cmd: var Cmd) =
  cmd.mode = cmdNim
  cmd.add nim_compiler, "cpp"


proc source*(cmd: var Cmd, paths: varargs[string, `$`]) =
  for path in paths:
    cmd.add path.quoted


proc output*(cmd: var Cmd, path: string) =
  case cmd.mode
  of cmdC:
    cmd.add "-o", path.quoted
  of cmdNim:
    cmd.add "-o:" & path.quoted



proc rebuild_the_build_impl(source: string) =
  var cmd = Cmd()
  cmd.nimc
  cmd.add "--hints:off"
  cmd.source source
  run cmd


proc rebuild_the_build_and_rerun_if_changed_impl(source: string, force: bool) =
  let bin_path = source.splitPath.head / source.splitFile.name
  const cbleFile = currentSourcePath()

  if force or (
    block:
      if not(fileExists(source) and fileExists(bin_path) and fileExists(cbleFile)):
        return  # do not rebuild if we can't
      
      let sourceT = getLastModificationTime(source)
      let cbleT = getLastModificationTime(cbleFile)
      let binT = getLastModificationTime(bin_path)

      binT < sourceT or binT < cbleT
  ):
    rebuild_the_build_impl(source)
    
    var cmd = Cmd()

    for i in 0..paramCount():
      if paramStr(i) != "rebuild-build":
        cmd.add paramStr(i).quoted

    if log_exec:
      echo "\27[36mre-Exec:\27[37m ", cmd.args, "\27[0m"
    
    quit execShellCmd cmd.args


template rebuild_the_build* =
  bind rebuild_the_build_impl
  rebuild_the_build_impl(instantiationInfo(index = 0, fullPaths = true).filename)


template rebuild_the_build_and_rerun_if_changed*(force = "rebuild-build" in argv) =
  bind rebuild_the_build_and_rerun_if_changed_impl
  rebuild_the_build_and_rerun_if_changed_impl(instantiationInfo(index = 0, fullPaths = true).filename, force)



proc find_nimble_package*(name: string, version: string = ""): seq[tuple[path: string, version: string]] =
  let query_name = name & (if version == "": "" else: "-" & version)

  for path in package_path:
    for k, p in walkDir(path, relative = false):
      if p.splitPath.tail.startsWith(query_name):
        result.add (p, p.splitPath.tail.split("-")[1])



proc `$`*(pkg: Package): string =
  result.add pkg.name
  if pkg.installed:
    result.add "-" & pkg.version
    result.add "  at `" & pkg.path & "`"
  else:
    result.add " (not installed)"


proc write_name_version*(pkg: Package) =
  if pkg.installed:
    stdout.write "\27[92m", pkg.name, "\27[0m"
  else:
    stdout.write "\27[91m", pkg.name, "\27[0m"
  
  if pkg.installed:
    stdout.write "-\27[96m", pkg.version, "\27[0m"
  else:
    stdout.write " (not installed)"


proc write_full*(pkg: Package) =
  writeNameVersion(pkg)

  if pkg.installed:
    stdout.write "  at `", pkg.path & "`"


proc echo_required_packages*(full = false) =
  echo "Required packages:"
  for pkg in required_packages:
    stdout.write "  "
    if full:
      write_full pkg
    else:
      write_name_version pkg
    stdout.write "\n"



proc query*(pkg: var Package) =
  let qpkgs = find_nimble_package(pkg.name, pkg.expectedVersion)
  
  if qpkgs.len > 0:
    let qpkg = qpkgs[qpkgs.mapIt(it.version).maxIndex]
    
    pkg.installed = true
    pkg.path = qpkg.path
    pkg.version = qpkg.version
  
  else:
    pkg.installed = false
    pkg.path = ""
    pkg.version = ""



proc query_package*(name: string, version = ""): Package =
  result = Package(
    name: name,
    expectedVersion: version,
  )
  query result


proc install_package*(name: string, version = "") =
  with_cmd_run:
    let versionedName = name & (if version == "": "" else: "@" & version)
    cmd.add "nimble", "install", versionedName.quoted


proc noNimblePath*(cmd: var Cmd) =
  cmd.add "--noNimblePath"


proc use*(cmd: var Cmd, pkg: Package) =
  cmd.add "--path:" & pkg.path.quoted


proc useRequiredPackages*(cmd: var Cmd) =
  cmd.noNimblePath
  for pkg in required_packages:
    cmd.use pkg



macro package*(name: untyped, version = "") =
  let name =
    if name.kind == nnkStrLit: name.strVal
    else: name.repr
  
  let namei = ident(name)

  result = quote do:
    var `namei` = query_package(`name`, `version`)



macro require*(name: untyped, version = "") =
  let name =
    if name.kind == nnkStrLit: name.strVal
    else: name.repr
  
  let namei = ident(name)
  let versioni = genSym(nskLet)

  result = quote do:
    let `versioni` = `version`
    var `namei` = query_package(`name`, `versioni`)
    
    if not `namei`.installed:
      if auto_install_required_packages:
        install_package(`name`, `versioni`)
        `namei` = query_package(`name`, `versioni`)
      else:
        error "required package ", `name`, (if `versioni` == "": " (any version)" else: "-" & `versioni`), " is not installed"
    
    required_packages.add `namei`


proc split_args*(argv: var seq[string], start_from: string): seq[string] =
  runnableExamples:
    var argv = @["aa", "bb", "run", "cc"]
    let run_args = argv.split_args("run")
    assert argv == @["aa", "bb"]
    assert run_args == @["cc"]

  if start_from in argv:
    let i = argv.find(start_from)
    result = argv[i + 1 .. ^1]
    argv = argv[0..i]


proc pop*(argv: var seq[string], arg: string): bool =
  let i = argv.find arg
  if i == -1: return false
  else:
    argv.delete i
    return true


template withCd*(dir: string, body: untyped) =
  bind getCurrentDir, setCurrentDir
  let oldDir = getCurrentDir()
  setCurrentDir(dir)
  body
  setCurrentDir(oldDir)



proc allFilesRec*(dir: string, relative = false): seq[string] =
  for p in walkDirRec(dir, relative = relative):
    result.add p



proc add_recipe*(recipe: Recipe) =
  recipes[recipe.outFile] = recipe

proc add_recipe*(outFile: string, inputs: seq[string], build: seq[Cmd]) =
  recipes[outFile] = Recipe(outFile: outFile, inputs: inputs, build: build)


proc rebuild_with_deps*(recipe: Recipe, if_needed = true) =
  # todo: parallel

  for dep in recipe.inputs:
    if dep in recipes:
      rebuild_with_deps recipes[dep], if_needed
  
  if fileExists(recipe.outFile):
    block unmodified:
      if not if_needed: break unmodified

      let moddate = getLastModificationTime(recipe.outFile)
      for dep in recipe.inputs:
        if fileExists(dep):
          let depmodd = getLastModificationTime(dep)
          if depmodd > moddate: break unmodified
        else: break unmodified
      
      return
  
  for cmd in recipe.build:
    run cmd


macro recipe*(outFilePath: string, inputs: varargs[string], body: untyped) =
  let add_recipe = bindSym("add_recipe")
  let fmt = bindSym("fmt")
  let strip = bindSym("strip")
  let cmds = genSym(nskVar, "cmds")

  let inputsSeq =
    if inputs.kind == nnkBracket: nnkPrefix.newTree(ident("@"), nnkBracket.newTree(inputs[0..^1]))
    else: inputs
  
  var body = body
  if body.kind == nnkTripleStrLit or body.kind == nnkStmtList and body[0].kind == nnkTripleStrLit:
    body = quote do:
      `cmds`.add Cmd(args: `strip`(`fmt`(`body`)))

  quote do:
    block:
      var `cmds`: seq[Cmd]
      var deps = `inputsSeq`
      var outFile = `outFilePath`

      template with_cmd_run(body2: untyped) =
        block:
          var cmd {.inject.} = Cmd()
          body2
          `cmds`.add cmd
      
      `body`

      `add_recipe`(outFile, deps, `cmds`)



proc build_cmd_aux(body: NimNode, cmd: NimNode): NimNode =
  if body.kind == nnkStmtList:
    for x in body:
      result = newStmtList()
      result.add build_cmd_aux(x, cmd)
    
  elif body.kind == nnkCall or body.kind == nnkCommand:
    result = body.kind.newTree(@[body[0], cmd] & body[1..^1])
  
  elif body.kind == nnkIdent:
    result = newCall(body, cmd)

    result = nnkWhenStmt.newTree(
      nnkElifBranch.newTree(newCall(ident("compiles"), result), result),
      nnkElse.newTree(newCall(ident("add"), cmd, body))
    )
  
  elif body.kind == nnkBlockStmt:
    result = body
  
  else:
    result = newCall(ident("add"), cmd, body)


macro exec*(body: varargs[untyped]) =
  result = newStmtList()
  
  for x in body:
    result.add build_cmd_aux(x, ident("cmd"))
  
  result = newCall(ident("with_cmd_run"), result)


macro build_cmd*(cmd: var Cmd, body: varargs[untyped]) =
  result = newStmtList()
  
  for x in body:
    result.add build_cmd_aux(x, cmd)


template act_as_makefile*(path: string, body: untyped) =
  rebuild_the_build_and_rerun_if_changed("rebuild-build" in argv)

  setCurrentDir path

  let if_needed = "force" notin argv

  if "rebuild-build" in argv: argv.delete argv.find("rebuild-build")
  if "force" in argv: argv.delete argv.find("force")

  body


  wrapErrorHandling:
    if argv.len == 0:
      for v in values(recipes):
        rebuild_with_deps v, if_needed
        break
    
    else:
      let recipe =
        try: recipes[argv[0]]
        except KeyError:
          echo "no recipe found for: ", argv[0]
          nil
      if recipe != nil:
        rebuild_with_deps recipe, if_needed


template act_as_makefile*(body: untyped) =
  act_as_makefile(parentDir(instantiationInfo(index = 0, fullPaths = true).filename), body)

