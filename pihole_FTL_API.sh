#!/usr/bin/env bash

# read previous history
history -r ftl_api_history

usage()
{
    echo ""
    echo "Query FTLv6's API"
    echo ""
    echo "Usage: $0 [-u <URL>] [-p <port>] [-a <path>] [-s <secret password>] "
    echo ""
    echo "To connect to FTL's API use the following options"
    echo "The whole API URL will look like http://{url}:{port}/{api}"
    echo ""
    echo " -- server <URL|IP>  		        URL or address of your Pi-hole (default: pi.hole)"
    echo " --port <port>    		        Port of your Pi-hole's API (default: 8080)"
    echo " --api <api>     			        Path where your Pi-hole's API is hosted (default: api)"
    echo " --secret <secret password>		Your Pi-hole password, required to access the API"
    echo ""
    echo "End script with Ctrl+C"
    echo ""
    echo ""
    echo "The returned data can be processed further by appending the desired command"
    echo "to the API endpoint. So things like"
    echo ""
    echo "'/stats/summary | jq .queries.blocked'"
    echo ""
    echo "will work."
    echo ""
}

secretRead() {

    # POSIX compliant function to read user-input and
    # mask every character entered by (*)
    #
    # This is challenging, because in POSIX, `read` does not support
    # `-s` option (suppressing the input) or
    # `-n` option (reading n chars)


    # This workaround changes the terminal characteristics to not echo input and later rests this option
    # credits https://stackoverflow.com/a/4316765
    # showing astrix instead of password
    # https://stackoverflow.com/a/24600839
    # https://unix.stackexchange.com/a/464963

    stty -echo # do not echo user input
    stty -icanon min 1 time 0 # disable cannonical mode https://man7.org/linux/man-pages/man3/termios.3.html

    unset password
    unset key
    unset charcount
    charcount=0
    while key=$(dd ibs=1 count=1 2>/dev/null); do #read one byte of input
        if [ "${key}" = "$(printf '\0' | tr -d '\0')" ] ; then
            # Enter - accept password
            break
        fi
        if [ "${key}" = "$(printf '\177')" ] ; then
            # Backspace
            if [ $charcount -gt 0 ] ; then
                charcount=$((charcount-1))
                printf '\b \b'
                password="${password%?}"
            fi
        else
            # any other character
            charcount=$((charcount+1))
            printf '*'
            password="$password$key"
        fi
    done

    # restore original terminal settings
    stty "${stty_orig}"
}

ConstructAPI() {
	# If no arguments were supplied set them to default
	if [ -z "${URL}" ]; then
		URL=127.0.0.1
        # when no $URL is set we assume PADD is running locally and we can get the port value from FTL directly
        PORT="$(pihole-FTL --config webserver.port)"
        PORT="${PORT%%,*}"
	fi
	if [ -z "${PORT}" ]; then
		PORT=80
	fi
	if [ -z "${APIPATH}" ]; then
		APIPATH=api
	fi
}

TestAPIAvailability() {

    availabilityResonse=$(curl -s -o /dev/null -w "%{http_code}" http://${URL}:${PORT}/${APIPATH}/auth)

    # test if http status code was 200 (OK)
    if [ "${availabilityResonse}" = 200 ] || [ "${availabilityResonse}" = 401 ]; then
        printf "%b" "API available at: http://${URL}:${PORT}/${APIPATH}\n\n"
    else
        echo "API not available at: http://${URL}:${PORT}/${APIPATH}"
        echo "Exiting."
        exit 1
    fi
}

Authenthication() {
    # Try to authenticate
    LoginAPI

    while [ "${validSession}" = false ] || [ -z "${validSession}" ] ; do
        echo "Authentication failed."

        # no password was supplied as argument
        if [ -z "${password}" ]; then
            echo "No password supplied. Please enter your password:"
        else
            echo "Wrong password supplied, please enter the correct password:"
        fi

        # secretly read the password
        secretRead

        echo ""

        # Try to authenticate again
        LoginAPI
    done

    # Loop exited, authentication was successful
    echo "Authentication successful."

}

DeleteSession() {
    # if a valid Session exists (no password required or successful authenthication) and
    # SID is not null (successful authenthication only), delete the session
    if [ "${validSession}" = true ] && [ ! "${SID}" = null ]; then
        # Try to delte the session. Omitt the output, but get the http status code
        deleteResponse=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE http://${URL}:${PORT}/${APIPATH}/auth  -H "Accept: application/json" -H "sid: ${SID}")

        case "${deleteResponse}" in
            "200") printf "%b" "\nA session that was not created cannot be deleted (e.g., empty API password).\n";;
            "401") printf "%b" "\nLogout attempt without a valid session. Unauthorized!\n";;
            "410") printf "%b" "\nSession successfully deleted.\n";;
         esac;
    fi

}

LoginAPI() {
    sessionResponse="$(curl --silent -X POST http://${URL}:${PORT}/${APIPATH}/auth --data "{\"password\":\"${password}\"}" )"

    if [ -z "${sessionResponse}" ]; then
        echo "No response from FTL server. Please check connectivity and use the options to set the API URL"
        echo "Usage: $0 [--server <URL>] [--port <port>] [--api <path>] "
    exit 1
  fi

	# obtain validity and session ID from session response
	validSession=$(echo "${sessionResponse}"| jq .session.valid 2>/dev/null)
	SID=$(echo "${sessionResponse}"| jq --raw-output .session.sid 2>/dev/null)
}

GetFTLData() {
    local response
    # get the data from querying the API as well as the http status code
	response=$(curl -s -w "%{http_code}" -X GET "http://${URL}:${PORT}/${APIPATH}$1" -H "Accept: application/json" -H "sid: ${SID}" )

    # status are the last 3 characters
    status=$(printf %s "${response#"${response%???}"}")
    # data is everything from repsonse without the last 3 characters
    data=$(printf %s "${response%???}")

    if [ "${status}" = 200 ]; then
        echo "${data}"
    elif [ "${status}" = 000 ]; then
        # connection lost
        echo "000"
    elif [ "${status}" = 401 ]; then
        # unauthorized
        echo "401"
    fi
}

# Called on signals INT QUIT TERM
sig_cleanup() {
    # save error code (130 for SIGINT, 143 for SIGTERM, 131 for SIGQUIT)
    err=$?

    # some shells will call EXIT after the INT signal
    # causing EXIT trap to be executed, so we trap EXIT after INT
    trap '' EXIT

    # write history to file
    history -w ftl_api_history

    (exit $err) # execute in a subshell just to pass $? to clean_exit()
    clean_exit
}

# Called on signal EXIT, or indirectly on INT QUIT TERM
clean_exit() {
    # save the return code of the script
    err=$?

    # reset trap for all signals to not interrupt clean_tempfiles() on any next signal
    trap '' EXIT INT QUIT TERM

    # restore terminal settings if they have been changed (e.g. user cancled script while at password  input prompt)
    if [ "$(stty -g)" != "${stty_orig}" ]; then
        stty "${stty_orig}"
    fi

    #  Delete session from FTL server
    DeleteSession
    exit $err # exit the script with saved $?
}

QueryAPI() {
    while true; do
        local input endpoint the_rest data
        printf "%b" "\nRequest data from API endpoint:\n"

        # read the input and split it into $endpoint and $the_rest after the first space
        read -r -e input
        IFS=' ' read -r endpoint the_rest <<< "$input"

        # save last input to history
        history -s "$input"

        data=$(GetFTLData "${endpoint}")

        # check if connection to FTL was lost
        # GetFTLData() will return "000"
        if [ "${data}" = 000 ]; then
            printf "%b" "\nConection to FTL lost! Please re-establish connection.\n"
        elif [ "${data}" = 401 ]; then
            # check if a new authentication is required (e.g. after connection to FTL has re-established)
            # GetFTLData() will return "401" if a 401 http status code is returned
            # as $password should be set already, it should automatically re-authenticate
            ChallengeResponse
            printf "%b" "\nNeeded to re-authenticate. Please request endpoint again.\n"
        else
            # Data was returned

            # if there was any command supplied run it on the returned data
            if [ -n "${the_rest}" ]; then
                eval 'echo ${data}' "${the_rest}"
            else
                # only print the API response
                echo "${data}"
            fi
        fi
    done
}


################################# Main ################
# Process all options (if present)
while [ "$#" -gt 0 ]; do
  case "$1" in
    "-h" | "--help"     ) usage; exit 0;;
    "--server"          ) URL="$2"; shift;;
    "--port"            ) PORT="$2"; shift;;
    "--api"             ) APIPATH="$2"; shift;;
    "--secret"          ) password="$2"; shift;;
    *                   ) DisplayHelp; exit 1;;
  esac
  shift
done

# Save current terminal settings (needed for later restore after password prompt)
stty_orig=$(stty -g)

# Traps for graceful shutdown
# https://unix.stackexchange.com/a/681201
trap clean_exit EXIT
trap sig_cleanup INT QUIT TERM

# Construct FTL's API address depending on the arguments supplied
ConstructAPI

# Test if the authentication endpoint is availabe
TestAPIAvailability

# Authenticate with the server
Authenthication

# Query the API
QueryAPI

