import ../../src/cble


act_as_makefile:
  const_path bin: "bin"
  createDir bin


  bin"main".recipe( bin"main.o" ):
    exec cc, output(bin"main"), source(bin"main.o")

  bin"main.o".recipe( "main.c" ):
    exec cc, "-c", output(bin"main.o"), source("main.c")

  "run".recipe( bin"main" ):
    exec bin"main"
