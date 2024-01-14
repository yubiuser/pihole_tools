#!/usr/bin/env bash
set -e

DisplayHelp()
{
    echo ""
    echo "Pi-hole Sync"
    echo ""
    echo "Sync your main Pi-hole to a secondary Pi-hole using the v6 API"
    echo ""
    echo "This script will requst the teleporter backup from the main Pi-hole, download it and"
    echo "upload it to the secondary Pi-hole."
    echo ""
    echo "Options"
    echo ""
    echo " --main <DOMAIN|IP>  		            Mandatory. Domain or IP address of your main Pi-hole"
    echo " --secondary <DOMAIN|IP>  		    Mandatory. Domain or IP address of your secondary Pi-hole"
    echo " --secret_main <secret password>	    Optional. Your Pi-hole password for the main server"
    echo " --secret_secondary <secret password> Optional. Your Pi-hole password for the secondary server"
    echo " --save                               Optional. Keep your teleporter file"
    echo ""
    echo "Abort script with Ctrl+C"
    echo ""
    echo ""
}

secretRead() {

    local key charcount password

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
                printf '\b \b' >&2
                password="${password%?}"
            fi
        else
            # any other character
            charcount=$((charcount+1))
            printf '*' >&2
            password="$password$key"
        fi
    done

    # restore original terminal settings
    stty "${stty_orig}"

    echo "${password}"
}

GetAPI() {

    local chaos_api_list availabilityResonse cmdResult digReturnCode
    local SERVER
    local API_URL

    SERVER=$1

    # Query the API URLs from FTL using CHAOS TXT
    # The result is a space-separated enumeration of full URLs
    # e.g., "http://localhost:80/api" or "https://domain.com:443/api"
    if [ -z "${SERVER}" ] || [ "${SERVER}" = "localhost" ] || [ "${SERVER}" = "127.0.0.1" ]; then
        # --server was not set or set to local, assuming we're running locally
        cmdResult="$(dig +short chaos txt local.api.ftl @localhost 2>&1; echo $?)"
    else
        # --server was set, try to get response from there
        cmdResult="$(dig +short chaos txt domain.api.ftl @"${SERVER}" 2>&1; echo $?)"
    fi

    # Gets the return code of the dig command (last line)
    # We can't use${cmdResult##*$'\n'*} here as $'..' is not POSIX
    digReturnCode="$(echo "${cmdResult}" | tail -n 1)"

    if [ ! "${digReturnCode}" = "0" ]; then
        # If the query was not successful
        echo "API not available at ${SERVER}. Please check server address and connectivity"  >&2
        exit 1
    else
      # Dig returned 0 (success), so get the actual response (first line)
      chaos_api_list="$(echo "${cmdResult}" | head -n 1)"
    fi

    # Iterate over space-separated list of URLs
    while [ -n "${chaos_api_list}" ]; do
        # Get the first URL
        API_URL="${chaos_api_list%% *}"
        # Strip leading and trailing quotes
        API_URL="${API_URL%\"}"
        API_URL="${API_URL#\"}"

        # Test if the API is available at this URL
        availabilityResonse=$(curl -skS -o /dev/null -w "%{http_code}" "${API_URL}auth")

        # Test if http status code was 200 (OK) or 401 (authentication required)
        if [ ! "${availabilityResonse}" = 200 ] && [ ! "${availabilityResonse}" = 401 ]; then
            # API is not available at this port/protocol combination
            API_PORT=""
        else
            # API is available at this URL combination
            echo "${API_URL}"
            break
        fi

        # Remove the first URL from the list
        local last_api_list
        last_api_list="${chaos_api_list}"
        chaos_api_list="${chaos_api_list#* }"

        # If the list did not change, we are at the last element
        if [ "${last_api_list}" = "${chaos_api_list}" ]; then
            # Remove the last element
            chaos_api_list=""
        fi
    done

    # if API_PORT is empty, no working API port was found
    if [ -n "${API_PORT}" ]; then
        echo "API not available at: ${API_URL}" >&2
        echo "Exiting."
        exit 1
    fi
}

Authenthication() {

    local current_API current_pwd SID validSession SID
    current_API=$1
    current_pwd=$2

    # Try to authenticate
    sessionResponse=$(LoginAPI "${current_API}" "${current_pwd}")

    # obtain validity and session ID from session response
	validSession=$(echo "${sessionResponse}"| jq .session.valid 2>/dev/null)
	SID=$(echo "${sessionResponse}"| jq --raw-output .session.sid 2>/dev/null)

    while [ "${validSession}" = false ] || [ -z "${validSession}" ] ; do
        echo "Authentication failed at ${current_API}" >&2

        # no password was supplied as argument
        if [ -z "${current_pwd}" ]; then
            echo "No password supplied for ${current_API}  Please enter your password:" >&2
        else
            echo "Wrong password supplied for ${current_API} Please enter the correct password:" >&2
        fi

        # secretly read the password
        current_pwd=$(secretRead)

        echo "" >&2

        # Try to authenticate again
        sessionResponse=$(LoginAPI "${current_API}" "${current_pwd}")

        # obtain validity and session ID from session response
	    validSession=$(echo "${sessionResponse}"| jq .session.valid 2>/dev/null)
	    SID=$(echo "${sessionResponse}"| jq --raw-output .session.sid 2>/dev/null)
    done

    # Loop exited, authentication was successful
    echo "Authentication successful at ${current_API}" >&2

    echo "${SID}"

}

LoginAPI() {
    local sessionResponse API_URL password
    API_URL=$1
    password=$2

    sessionResponse="$(curl -skS -X POST "${API_URL}auth" --data "{\"password\":\"${password}\"}" )"

    if [ -z "${sessionResponse}" ]; then
        echo "No response from FTL server. Please check connectivity and use the options to set the server domain/IP" >&2
        exit 1
    fi

    echo "${sessionResponse}"
}

DeleteSession() {

    local SID API_URL deleteResponse
    API_URL=$1
    SID=$2

    # SID is not null (successful authenthication only), delete the session
    if [ ! "${SID}" = null ]; then
        # Try to delte the session. Omitt the output, but get the http status code
        deleteResponse=$(curl -skS -o /dev/null -w "%{http_code}" -X DELETE "${API_URL}auth"  -H "Accept: application/json" -H "sid: ${SID}")

        case "${deleteResponse}" in
            "204") printf "%b" "Session successfully deleted at ${API_URL} \n";;
            "401") printf "%b" "Logout attempt without a valid session at ${API_URL} Unauthorized!\n";;
         esac;
    fi

}

DownloadTeleporter() {

    local response API_URL SID

    API_URL=$1
    SID=$2

    # get the teleporter data from the API as well as the http status code
	response=$(curl -skS -w "%{http_code}" -o teleporter.zip -X GET "${API_URL}teleporter" -H "Accept: application/json" -H "sid: ${SID}")

    if [ "${response}" = 200 ]; then
        echo "Download successful"
    elif [ "${response}" = 000 ]; then
        # connection lost
        echo "Connection lost to ${API_URL}" >&2
        exit 1
    elif [ "${response}" = 401 ]; then
        # unauthorized
        echo "Unauthorized at ${API_URL}" >&2
        exit 1
    fi

}

UploadTeleporter() {

    local response API_URL SID

    API_URL=$1
    SID=$2

    # get the teleporter data from the API as well as the http status code
	response=$(curl -skS -w "%{http_code}" -F file=@teleporter.zip -X POST "${API_URL}teleporter" -H "Accept: application/json" -H "sid: ${SID}")

    if [ "${response}" = 200 ]; then
        echo "Upload successful"
    elif [ "${response}" = 000 ]; then
        # connection lost
        echo "Connection lost to ${API_URL}" >&2
        exit 1
    elif [ "${response}" = 401 ]; then
        # unauthorized
        echo "Unauthorized at ${API_URL}" >&2
        exit 1
    fi

}

# Called on signals INT QUIT TERM
sig_cleanup() {
    # save error code (130 for SIGINT, 143 for SIGTERM, 131 for SIGQUIT)
    err=$?

    # some shells will call EXIT after the INT signal
    # causing EXIT trap to be executed, so we trap EXIT after INT
    trap '' EXIT

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

    #  Delete sessions from FTL servers
    DeleteSession "${main_API}" "${main_SID}"
    DeleteSession "${secondary_API}" "${secondary_SID}"

    exit $err # exit the script with saved $?
}


################################# Main ################
# Process all options (if present)
while [ "$#" -gt 0 ]; do
  case "$1" in
    "-h" | "--help"         ) DisplayHelp; exit 0;;
    "--main"                ) main_pihole="$2"; shift;;
    "--secret_main"         ) password_main="$2"; shift;;
    "--secondary"           ) secondary_pihole="$2"; shift;;
    "--secret_secondary"    ) password_secondary="$2"; shift;;
    "--save"                ) save_teleporter=true;;
    *                       ) DisplayHelp; exit 1;;
  esac
  shift
done

# Save current terminal settings (needed for later restore after password prompt)
stty_orig=$(stty -g)

# Traps for graceful shutdown
# https://unix.stackexchange.com/a/681201
trap clean_exit EXIT
trap sig_cleanup INT QUIT TERM

# Test if the authentication endpoints are availabe
main_API=$(GetAPI "${main_pihole}")
secondary_API=$(GetAPI "${secondary_pihole}")

# Authenticate with the servers
main_SID=$(Authenthication "${main_API}" "${password_main}")
secondary_SID=$(Authenthication "${secondary_API}" "${password_secondary}")

# Download Teleporter archive
DownloadTeleporter "${main_API}" "${main_SID}"

# Upload Teleporter archive
UploadTeleporter "${secondary_API}" "${secondary_SID}"

# Remove Teleporter archive if not requested otherwise
if [ -z "${save_teleporter}" ]; then
     rm teleporter.zip
fi

# with set -e set, script will exit here and sessions will be deleted
