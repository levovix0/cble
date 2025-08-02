import src/cble, terminal


const help =  """
usage:
  ./package [commands...]

commands:
  examples  show examples
    run     run examples
  install   install cble via nimble
"""


wrapErrorHandling:
  rebuild_the_build_and_rerun_if_changed("rebuild-build" in argv)
  
  setCurrentDir src

  if "help" in argv or "--help" in argv or "-h" in argv:
    echo help

  elif "examples" in argv:
    for example in ["simple", "packages", "makefile"]:
      styledEcho "-------- ", fgGreen, example/"package.nim", fgDefault, " --------"
      echo readFile "examples"/example/"package.nim"
      
      if "run" in argv:
        exec nimc, "--hints:off", "-r", "examples"/example/"package.nim", "run"
  
  elif "install" in argv:
    exec "nimble install"
  
  else:
    echo help
