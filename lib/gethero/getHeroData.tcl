#
# Script Info:
#    Get Heroku data - Odata Retriever
#
# Developer :
#    Cris Magalang
#
# Notes:
#    Uses TCLcurl, check version used on same dir.
#    Uses modified json library.
#    Mocked-up user agent
#    SSL Bypassed host verification to avoid certificate errors
#    SSL Bypassed peer verification to avoid certificate errors
#
# Last revision:
#    0.0.1 - xxx                   | Early releases
#    1.0.2 Release for 9-Jan-2023  | Odata query tracking file Logger permission fix update.
#

package require cmdline
package require base64
package require Itcl
package require TclCurl
package require tdom 0.9.2
package require json


# Released version
package provide getHeroData 1.1

itcl::class getHeroData {

    public variable url ""
    public variable query_filter ""
    public variable tcl_curl_config ""
    public variable response
    public variable CVAR {}

    variable herodata_config
    variable direct 0
    variable debug 0
    variable verbose 0
    variable map
    variable alphanumeric
    variable init_once 0
    variable curlHandle
    variable nextLink  ""
    variable nextToken ""
    variable nextLinkLoop 1
    variable response_body_node

    constructor {{_opts {}}} {
        set margs $_opts
        herodata_init $margs
    }

    private method cvar_init {} {
        variable CVAR
        variable response_body_node
        dict set CVAR script version 1.0.2
        dict set CVAR script developer name {Cristopher S. Magalang}
        dict set CVAR script developer email cristopher.magalang@example.com
        dict set CVAR dir log /automation/cadauto_dev/workdir/
        dict set CVAR curlConfig dir /automation/config/services
        dict set CVAR defaultCurlConfig {
            -httpheader {{User-Agent: Apache-HttpClient/4.1.1 (java 1.5)} {cache-control: no-cache} {Content-Type: application/json}}
            -failonerror 1
            -timeout 300
            -verbose 0
        }
        dict set CVAR defaultProxy {
            -proxy gtoproxy.tapeout.cso:4567
            -proxyauth basic
        }
        set newdoc [dom createDocument Result]
        set response_body_node [$newdoc documentElement]
    }

    private method herodata_init {margs} {
        variable debug
        variable verbose
        variable direct
        variable herodata_config
        variable CVAR
        putdebug "DATA_INIT - Started"
        array set opts $margs
        cvar_init
        init_encoding

        if {[info exists opts(debug)] && $opts(debug) == 1} {
            set herodata_config(-verbose) 1
            set debug 1
        }
        if {[info exists opts(verbose)] && $opts(verbose) == 1} {
            set herodata_config(-verbose) 1
            set verbose 1
        }
        if {[info exists opts(direct)] && $opts(direct) == 1} {
            set direct 1
        }
        # User specified odata query filter
        if {[info exists opts(env)] && [string length $opts(env)]>=3} {
            switch -nocase -exact -- $opts(env) {
                dev - devel -
                development {
                    set opts(env) dev
                    dict set CVAR environment dev
                    dict set CVAR db_alloc development
                }
                uat - t - tst - test -
                testing {
                    set opts(env) test
                    dict set CVAR environment test
                    dict set CVAR db_alloc test
                }
                prd - prod - prod2008 -
                production {
                    set opts(env) prod
                    dict set CVAR environment prod
                    dict set CVAR db_alloc production
                }
                "default" {
                    set opts(env) prod
                    dict set CVAR environment prod
                    dict set CVAR db_alloc production
                }
            }
        }
        putdebug "ENVIRONMENT=$opts(env)"
        # Specify Curl Config from source
        if {[info exists opts(odata_source)] && [string length $opts(odata_source)] > 1} {
            set config_dir [dict get $CVAR curlConfig dir]
            set opts(config_file) [file normalize \
                [file join $config_dir odata.${opts(env)}+${opts(odata_source)}.config]]

            set found_error 0
            set error_message {}
            if {![file exists $opts(config_file)]} {
                append error_message "Config file $opts(config_file) not found."
                set found_error 1
            } else {
                putdebug "config_file=<$opts(config_file)>-OK"
            }
            # Specify Curl Config table source
            if {[info exists opts(source_obj)] && [string length $opts(source_obj)] > 1} {
                putdebug "source_obj=$opts(source_obj)"
            } else {
                append error_message "\nOption: 'source_obj' is required when 'odata_source' is defined."
                set found_error 2
            }
            if {$found_error} {
                putdebug $error_message
                return -code error "Input error: $error_message"
            }
            set herodata_config(odata_source) $opts(odata_source)
            set herodata_config(source_obj) $opts(source_obj)
            set herodata_config(config_file) $opts(config_file)
        }

        # User specified URL overrride
        if {[info exists opts(url)] && [string length $opts(url)] > 1} {
            set herodata_config(-url) $opts(url)
            putdebug "user_defined_url=$opts(url)"
        }

        # User specified Remote URL credentials - Basic Authentication user:pwd
        if {[info exists opts(userpwd)] && [string length $opts(userpwd)]>=3} {
            set herodata_config(-userpwd) $opts(userpwd)
            putdebug "user_defined_-userpwd=...."
        }

        # User specified Proxy host - Proxy host:port
        if {[info exists opts(proxy)] && [string length $opts(proxy)]>=3} {
            set herodata_config(-proxy) $opts(proxy)
            putdebug "user_defined_-proxy=$opts(proxy)"
        }
        # User specified Proxy login credentials - Proxy Basic Authentication user:pwd
        if {[info exists opts(proxyuserpwd)] && [string length $opts(proxyuserpwd)]>=3} {
            set herodata_config(-proxyuserpwd) $opts(proxyuserpwd)
            putdebug "user_defined_-proxyuserpwd=...."
        }

        # Override timeout
        if {[info exists opts(timeout)] && $opts(timeout)>3} {
            set herodata_config(-timeout) $opts(timeout)
            putdebug "user_defined_-timeout=...."
        }

        # User specified odata query filter
        if {[info exists opts(query_filter)] && [string length $opts(query_filter)]>=3} {
            # do something
            putdebug "user_defined_query_filter_on_config=$opts(query_filter)"
        }
        tclcurl_prepare_config
        putdebug "DATA_INIT - Done"
    }


    method tclcurl_prepare_config {} {
        variable debug
        variable verbose
        variable herodata_config
        variable CVAR

        putdebug "CURL_CONFIG - Started"
        if {[info exists herodata_config(config_file)]} {
            if {![file exists $herodata_config(config_file)]} {
                error "ERROR: Unable to find <$herodata_config(config_file)>."
            }
            if {[catch {set FIN [open $herodata_config(config_file) r]} errmsg]} {
                puts $data
                exit
                #error "ERROR:$errmsg"
            }
            set data [read $FIN]
            close $FIN
            if {[catch {dict get $data curlConfig ${herodata_config(odata_source)},common} common_curl_config]} {
                error "Error: unable to find data <curlConfig ${herodata_config(odata_source)},common common_curl_config>"
            }
            if {[catch {dict get $data curlConfig ${herodata_config(odata_source)},${herodata_config(source_obj)}} sel_curl_config]} {
                if {[catch {dict get $data curlConfig ${herodata_config(odata_source)},GENERIC_PATH_PREFIX} sel_curl_config]} {
                    error "Error: unable to find data <curlConfig ${herodata_config(odata_source)},${herodata_config(source_obj)}>"
                } else {
                    regsub "##STR_REPLACE_MATCH_DB_OBJ##" [dict get $sel_curl_config -url] $herodata_config(source_obj) tmpurl
                    dict set sel_curl_config -url $tmpurl
                }
            }
            #putdebug common_curl_config=<$common_curl_config>
            ##putdebug sel_curl_config=$sel_curl_config
            set newconfig [dict merge $common_curl_config $sel_curl_config]
        } else {
            set newconfig [dict get $CVAR defaultCurlConfig]
            puts "# Development Version. Inprogress -- work in progress"

        }

        if {$verbose || $debug} {
            dict set newconfig -verbose 1
        }
        dict set newconfig -bodyvar response(bodyvar)
        dict set newconfig -headervar response(headervar)
        dict set newconfig -errorbuffer response(err_buff)
        dict set newconfig -failonerror 1
        dict set newconfig -proxyuserpwd something:password12345
        dict set newconfig -sslverifyhost 0
        dict set newconfig -sslverifypeer 0
        putdebug loaded_config=<$newconfig>
        dict set CVAR curl_config $newconfig
        putdebug "CURL_CONFIG - Done"
        return -code ok
    }


    method odata_select {fnargs} {
        variable herodata_config
        variable CVAR
        variable nextLink
        variable nextToken
        array set params $fnargs
        set ofilter ""
        set oselect ""
        set encode  1
        set urle ""
        if {[info exists params(ofilter)]} {set ofilter $params(ofilter)}
        if {[info exists params(oselect)]} {set oselect $params(oselect)}
        if {[info exists params(encode)]} {set encode $params(encode)}
        if {[info exists params(urle)]} {set urle $params(urle)}
        putdebug "CURL_BUILD_SELECT - Start"
        array set tclCurlConfig [dict get $CVAR curl_config]

        if {[string length $nextLink]>0} {
            set tclCurlConfig(-url) $nextLink
            set separator "&"
            putdebug "LinkChanged:<$nextLink>"
        }

        if [regexp {\?} $tclCurlConfig(-url)] {
           set separator "&"
        } else {
           set separator "?"
        }

        if {[string length $ofilter] == 0 && [info exists herodata_config(query_filter)]} {
            set ofilter $herodata_config(query_filter)
        }

        if {[string length $ofilter]>4} {
            if {$encode} {
                set ofilter [url-encode $ofilter]
            }
            append tclCurlConfig(-url) "$separator\$filter=$ofilter"
            set separator "&"
        }

        if {[string length $oselect]>1} {
            append tclCurlConfig(-url) "$separator\$select=$oselect"
        }

        if {[string length $urle]>0} {
            append tclCurlConfig(-url) "$urle"
        }

        putdebug "CURL_BUILD_SELECT tclCurlConfig=<[array get tclCurlConfig]> "
        putdebug "CURL_BUILD_SELECT - Done"
        odata_send [array get tclCurlConfig]
    }

    method odata_send {cfg} {
        variable init_once
        variable curlHandle
        variable response
        variable verbose
        variable herodata_config
        variable CVAR
        array set response ""
        set url [dict get $CVAR curl_config "-url"]
        set environment [dict get $CVAR environment]
        putdebug "odata_send - Start"
        #if {$init_once == 0} {
            catch {$curlHandle reset} errsmg
            catch {$curlHandle cleanup} errmsg
            set curlHandle [curl::init]
        #    set init_once 1
        #}

        #putdebug "odata_send - curlHandle Initiated = $init_once"
        set ncode [$curlHandle configure {*}$cfg]
        putdebug "odata_send - curlHandle configure {*}$cfg NCODE=<$ncode>"
        if {[catch { $curlHandle perform } curlErrorNumber]} {
            puts "Error: [curl::easystrerror $curlErrorNumber]"
            dict set cfg -failonerror 0
            catch {$curlHandle reset} errsmg
            catch {$curlHandle cleanup} errmsg
            set curlHandle [curl::init]
            set ncode [$curlHandle configure {*}$cfg]
            $curlHandle perform
            puts "Error: buffer=<$response(err_buff)>"
            puts "Error: response=<$response(bodyvar)>"
            testLog "$environment" "ERROR" "$curlErrorNumber,[curl::easystrerror $curlErrorNumber],$response(bodyvar)|$url"
            exit $curlErrorNumber
        } else {
            putdebug "odata_send - perfom_exit_code=<$curlErrorNumber>"
            testLog "$environment" "INFO" "$curlErrorNumber|$url"
        }
        putdebug "odata_send - Done"
    }

    method init_encoding {} {
        variable map
        variable alphanumeric a-zA-Z0-9
        for {set i 0} {$i <= 256} {incr i} {
            set c [format %c $i]
            if {![string match \[$alphanumeric\] $c]} {
                set map($c) %[format %.2x $i]
            }
        }
        # These are handled specially
        array set map { " " + \n %0d%0a }
    }

    method url-encode {string} {
        variable map
        variable alphanumeric
        variable herodata_config
        variable CVAR

        putdebug "url-encode-string:"
        putdebug "    original=<$string>"
        regsub -all \[^$alphanumeric\] $string {$map(&)} string
        regsub -all {[][{})\\]\)} $string {\\&} string
        putdebug "    url-encoded=<[subst -nocommand $string]>"
        return [subst -nocommand $string]
    }

    method getNextLink {root} {
        variable nextLink
        variable nextToken
        variable nextLinkLoop
        set nextLink ""
        set nextToken ""
        set cnodes [$root childNodes]
        set nNodeLink ""
        foreach child $cnodes {
            set xpath [$child toXPath]
            if {[regexp -nocase {odata.nextLink} $xpath]} {
                set nNodeLink $child
                break
            }
        }
        if {$nNodeLink eq ""} {
            set nextLinkLoop 0
            return
        }
        if {[regexp -nocase {%24skiptoken=} [$nNodeLink asText]]} {
            set nextLink [$nNodeLink asText]
            regexp -nocase {%24(skiptoken=\d+)} [$nNodeLink asText] -> nextToken
            incr nextLinkLoop
            return
        }
    }

    method json2xml {root {xpath {}}}  {
        if {[string length $xpath] > 0} {
            set newdoc [dom createDocument Result]
            set nroot [$newdoc documentElement]
            foreach cnodes [$root selectNodes $xpath] {
                $nroot appendChild $cnodes
            }
            return [$newdoc asXML]
        }
        return [$root asXML]
    }

    method json2json {root {xpath {}}}  {
        if {[string length $xpath] > 0} {
            set newdoc [dom createDocument Result]
            set nroot [$newdoc documentElement]
            foreach cnodes [$root selectNodes $xpath] {
                $nroot appendChild $cnodes
            }
            return [$newdoc asJSON]
        }
        puts [$root asJSON]
        exit
        return [$root asJSON]
    }

    method json2dict {root {xpath {}}}  {
        set result ""
        if {[string length $xpath] > 0} {
            set newdoc [dom createDocument Result]
            set nroot [$newdoc documentElement]
            foreach cnodes [$root selectNodes $xpath] {
                set nname  [$cnodes nodeName]
                dict lappend result $nname [json::json2dict [$cnodes asJSON]]
            }
            return $result
        }
        return [::json::many-json2dict [$root asJSON]]
    }

    method get_response {} {
        variable response(bodyvar)
        return [array get response]
    }

    method get_response_body {format} {
        variable response
        variable response_body_node
        if {![info exists response(bodyvar)] } {
            parray response
            puts Error:NO_RESPONSE_BODY
            exit 1
        }
        putdebug raw_response=<$response(bodyvar)>
        set document [dom parse  -keepCDATA -keepEmpties -json -jsonroot XMLODATAROOT -- $response(bodyvar)]
        #if {$format eq "json"} {
        #    set document [dom parse -json -jsonroot XMLODATAROOT -- $response(bodyvar)]
        #} elseif {$format eq "xml"} {
        #    set document [dom parse  -keepCDATA -keepEmpties -json -jsonroot XMLODATAROOT -- $response(bodyvar)]
        #} elseif {$format eq "dict"} {
        #    set document [dom parse -json -jsonroot XMLODATAROOT -- $response(bodyvar)]
        #}
        #set document [dom parse -json -jsonroot Result -- $response(bodyvar)]
        set root     [$document documentElement]
        getNextLink  $root
        set exitstatus [catch {$root selectNodes //value/objectcontainer} objectnodes]
        if {$objectnodes eq ""} {
            set objectnodes [$root selectNodes //results/objectcontainer]
        }
        if {$exitstatus == 0 } {
            foreach cnodes $objectnodes {
                $response_body_node appendChild $cnodes
            }
        }
    }

    method set_response_format {{format {json}} {xpath {}}} {
        variable response_body_node

        if {$format eq "json"} {
            return [json2json $response_body_node $xpath]
        } elseif {$format eq "xml"} {
            return [json2xml $response_body_node $xpath]
        } elseif {$format eq "dict"} {
            return [json2dict $response_body_node $xpath]
        } else {
            return -code error "get_response_body - UNKNOWN FORMAT REQUESTED format=$format"
        }
    }


    method get_response_header {} {
        variable response
        if {[info exists response(headervar)]} {
            return $response(headervar)
        }
    }


    method putdebug {msg} {
        variable debug
        set dtime [clock format [clock seconds] -format {%Y-%m-%d_%H:%M:%S} ]
        if {$debug} {
            puts "$dtime \[DEBUG\]: $msg"
        }
    }


    method getNewLink {} {
        variable nextLink
        variable nextToken
        variable nextLinkLoop
        return [list $nextLinkLoop $nextLink $nextToken]
    }

    proc testLog {env type msg} {
        set dtime [clock format [clock seconds] -format {%Y-%m-%d_%H:%M:%S}]
        set yy [clock format [clock seconds] -format {%Y}]
        set mm [clock format [clock seconds] -format {%m}]
        if {$env eq "prod"} {
            set tws_base /gtofilesystem/tws
        } else {
            set tws_base /gtofilesystem/tws_test
        }
        set logdir $tws_base/.tmp/$yy
        file mkdir $logdir
        catch {file attributes $logdir -permissions 777} ignore_err

        set logdir $tws_base/.tmp/$yy/$mm
        file mkdir $logdir
        catch {file attributes $logdir -permissions 777} ignore_err

        set FIN [open $logdir/odata_conn.log a]

        puts $FIN "$dtime,$::env(USER),[string toupper $type],$msg"
        close $FIN

        catch {file attributes $logdir/odata_conn.log -permissions 777} errmsg
    }

    proc cmdline-main {args} {
        set options {
            {env.arg "test" "Run env : test or prod"}
            {odata_source.arg "salesforce" "ODATA Source: e.g. 'salesforce' , default: 'salesforce'"}
            {source_obj.arg "" {Source Table Object: e.g.
                    to_ftrf_form__c,to_ftrf_mask_layer__c,
                    to_ftrf_mask_layer_transactional_data__c,
                    to_ftrf_tapeout_service_form__c,
                    to_ftrf_chip__c,to_ftrf_contact_reviewer__c,
                    to_ftrf_contact_rev_transactional_data__c, ...}
                }
            {url.secret "" "User specified URL."}
            {userpwd.secret "" "Access credentials for user defined URL. Format : 'user:password'."}
            {proxy.secret   "" "Specify alternate proxy configuration."}
            {proxyuserpwd.secret "" "Specify proxy login credentials, Format: 'user:password'"}
            {timeout.secret "300" "Adjust connection timeout parameters. unit=Seconds"}
            {query_filter.arg "" "odata based query filter"}
            {netrc "Use netrc defined access credentials on user run directory."}
            {verbose "Use verbose mode for debugging."}
            {debug "Print debug information for debugging."}
            {direct "Directly connect query to remote host, as against storing to managed service."}
            {xml "Output results as XML"}
            {dict "Output results as tcl dict"}
            {ftrf_name.arg "" "FILTER with FTRF name"}
            {cust.arg "" "FILTER with customer shortname."}
            {mst.arg "" "FILTER with by maskset title."}
            {xpath.arg "" "Return only specified path"}
            {fab.arg "" "FILTER with Fab"}
            {sel.arg "" "FILTER odata fields"}
            {get_parts.arg "" "Get response parts list"}
            {urle.arg "" "Append additional strings at end of url"}
        }

        set usage "\\> getHeroData \[options\]"
        set cmdusage [::cmdline::usage $options $usage]
        if {[catch {array set params [::cmdline::getoptions args $options $usage]} error]} {
            puts ERROR:$error
            return
        }
        set common_config [array get params]
        set oobj [getHeroData %ODATA_obj $common_config]

        set oselect ""
        if {[string length $params(sel)] > 0} {
            set oselect "[string trim ${params(sel)}]"
        }

        set filter {}
        if {[string length $params(ftrf_name)]>1} {lappend filter "name eq '$params(ftrf_name)'" }
        if {[string length $params(cust)]>1} {lappend filter  "customer_short_name__c eq '$params(cust)'" }
        if {[string length $params(mst)]>1} {lappend filter  "mask_set_title__c eq '$params(mst)'" }
        if {[string length $params(fab)]>1} {lappend filter  "fab__c eq '$params(fab)'" }
        if {[string length $params(query_filter)] > 3} {
            lappend filter $params(query_filter)
        }
        set filter [join $filter " and "]
        set osargs [list]

        if {[string length $params(urle)]>1} {
            dict set osargs urle $params(urle)
        }

        if {[string length $filter]>1} {
            dict set osargs ofilter $filter
        }
        if {[string length $oselect]>1} {
            dict set osargs oselect $oselect
        }

        if {$params(xml)} {
            set format xml
        } elseif {$params(dict)} {
            set format dict
        } else {
            set format json
        }
        lassign [$oobj getNewLink] loopCounter nextLink nextToken

        while {$loopCounter} {
            $oobj odata_select $osargs
            $oobj get_response_body $format
            lassign [$oobj getNewLink] loopCounter nextLink nextToken
            dict set osargs nextLink $nextLink
            dict set osargs nextToken $nextToken
        }

        set response [$oobj set_response_format $format $params(xpath)]
        puts $response

        return -code ok
    }
}

