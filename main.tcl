#!/bin/sh
#
# the next line restarts using tclsh \
exec /APP1/Tcl/`uname -s`-`uname -m | sed 's/\/.*//'`/ActiveTcl8.6.4.0/bin/base-tk8.6-thread-linux-x86_64 "$0" "$@"
package require starkit
starkit::startup

#Find below in the folder app-main/main.tcl
package require csm_to40ws_main
