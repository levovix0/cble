import ../../src/cble

auto_install_required_packages = "no-package-install" notin argv

wrapErrorHandling:
  rebuild_the_build_and_rerun_if_changed("rebuild-build" in argv)


  require jsony

  if "list-packages" in argv:
    echo_required_packages()


  with_cmd_run:
    cmd.nimc
    cmd.add "--hints:off"
    cmd.useRequiredPackages
    cmd.output src/"main"
    cmd.source src/"main.nim"


  if "run" in argv:
    with_cmd_run:
      cmd.add src/"main"
