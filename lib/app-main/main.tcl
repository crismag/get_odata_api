#!/bin/sh
# ---------------------------------------------------------------------------------------
# Description:
# Stripped down version for demonstration only.
# Odata connector for commandline local odata consumers.
# Non odata packages removed.
#
# ---------------------------------------------------------------------------------------
# Developer : Cris Magalang
# Date : 2020-12-11
# ---------------------------------------------------------------------------------------
# Revision History:
#
# ---------------------------------------------------------------------------------------
# the next line restarts using tclsh \
exec /APP1/Tcl/`uname -s`-`uname -m | sed 's/\/.*//'`/ActiveTcl8.5.17.0/bin/tclsh8.5 "$0" "$@"

package provide csm_to40ws_main 1.1

package require cmdline
package require base64
package require Itcl
package require TclCurl
package require tdom 0.9.2
package require gproxyrc
package require getHeroData
package require GFAWSConfig
package require csm_msvcs_call

namespace eval csm_to40ws_main {
	variable main
	array set main {}

	set main(appVer) 1.0
	set main(developer)    "cris.magalang@somedomain.com"
	set main(email_notify) [join [list \
		some.email@example.com \
		] ","]
	set main(USER) $::env(USER)
	set main(applist) {
		csmsvc
		odata
		help
    }

	regexp {([^\.]*)} [info hostname] main(currentHost)
	regexp {([^\.]*)} [file tail [info nameofexecutable]] main(appName)

	namespace ensemble create -map {
		csmsvc ::csm_msvcs_call::main_cmdline
		post ::csm_msvcs_call::main_cmdline
		odata  ::getHeroData::cmdline-main
		help   get_Help
    }

}

proc csm_to40ws_main::main {} {
	global argv
	variable main

	switch -nocase -exact -- [lindex $argv 0] {
		"" - -h - -help - --help - -usage -
		--usage {
			[namespace current]::get_Help
	    }
	    rest {
            if {[catch {::csm_to40ws_main csmsvc {*}[lrange $argv 1 end]} result]} {
            	return -code error $result
            }
	    }
	    od -
	    odata -
	    getOdata -
	    getdata -
	    gd {
            if {[catch {::csm_to40ws_main odata {*}[lrange $argv 1 end]} result]} {
            	return -code error $result
            }
	    }
	    default {
	    	if {[string length [lsearch -nocase -inline $main(applist) [lindex $argv 0]]]>0} {
	    		if {[catch {::csm_to40ws_main {*}$argv} result]} {
	    			return -code error $result
	    		}
	    		return
			} else {
	    		[namespace current]::get_Help
	    		return
	    	}
			
	    }
    }

    #----------------------------------------------------------
}


proc csm_to40ws_main::get_csmSvc-main {} {
	puts get_csmSvc-main
}

proc csm_to40ws_main::get_Odata-main {} {
	puts get-Odata-main
}

proc csm_to40ws_main::get_Help {} {
	puts "For more info, use: /csm/bin/Linux/csm_gethodata odata -help"
}

csm_to40ws_main::main
