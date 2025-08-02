import ../../src/cble


wrapErrorHandling:
  rebuild_the_build_and_rerun_if_changed("rebuild-build" in argv)


  with_cmd_run:
    cmd.cc
    cmd.output src/"main"
    cmd.source src/"main.c"
