#!/usr/bin/env sh

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
	echo " -u <URL|IP>  			URL or address of your Pi-hole (default: pi.hole)"
    echo " -p <port>    			Port of your Pi-hole's API (default: 8080)"
    echo " -a <api>     			Path where your Pi-hole's API is hosted (default: api)"
	echo " -s <secret password>		Your Pi-hole password, required to access the API"	
	echo ""
}

ConstructAPI() {
	# If no arguments were supplied, set them to default
	if [ -z "${URL}" ]; then
		URL=pi.hole
	fi
	if [ -z "${PORT}" ]; then
		PORT=8080
	fi
	if [ -z "${APIPATH}" ]; then
		APIPATH=api
	fi
}

TestAPIAvailability() {
	
	availabilityResonse=$(curl -s -o /dev/null -w "%{http_code}" http://${URL}:${PORT}/${APIPATH}/auth)

	# test if http status code was 200 (OK)
	if [ "${availabilityResonse}" = 200 ]; then
		printf "%b" "API available at: http://${URL}:${PORT}/${APIPATH}\n\n"
	else
		echo "API not available: http://${URL}:${PORT}/${APIPATH}"
		echo "Exiting."
		exit 1
	fi
}

Authenthication() {
	# Try to authenticate
	ChallengeResponse

	while [ "${validSession}" = false ]; do
		echo "Authentication failed."

		# no password was supplied as argument
		if [ -z "${password}" ]; then
			echo "No password supplied. Please enter your password:"
		else
			echo "Wrong password supplied, please enter the correct password:"
		fi
		
		# POSIX's `read` does not support `-s` option (suppressing the input)
		# this workaround changes the terminal characteristics to not echo input and later rests this option
		# credits https://stackoverflow.com/a/4316765

		stty_orig=$(stty -g)
		stty -echo
		read -r password
		stty "${stty_orig}"
		echo ""

		# Try to authenticate again
		ChallengeResponse
	done
	
	# Loop exited, authentication was successful
	echo "Authentication successful."

}

DeleteSession() {
	
	# Try to delte the session. Omitt the output, but get the http status code
	deleteResponse=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE http://${URL}:${PORT}/${APIPATH}/auth  -H "Accept: application/json" -H "sid: ${SID}")

	case "${deleteResponse}" in
        "200") printf "%b" "\nA session that was not created cannot be deleted (e.g., empty API password).\n";;
        "401") printf "%b" "\nLogout attempt without a valid session. Unauthorized!\n";;
        "410") printf "%b" "\nSession deleted.\n";;
     esac;
	
}

ChallengeResponse() {
	# Challenge-response authentication

	# Compute password hash from user password
	# Compute password hash twice to avoid rainbow table vulnerability
    hash1=$(printf "%b" "$password" | sha256sum | sed 's/\s.*$//')
    pwhash=$(printf "%b" "$hash1" | sha256sum | sed 's/\s.*$//')

		
	# Get challenge from FTL
	# Calculate response based on challenge and password hash
	# Send response & get session response
	challenge="$(curl --silent -X GET http://${URL}:${PORT}/${APIPATH}/auth | jq --raw-output .challenge)"
	response="$(printf "%b" "${challenge}:${pwhash}" | sha256sum | sed 's/\s.*$//')"
	sessionResponse="$(curl --silent -X POST http://${URL}:${PORT}/${APIPATH}/auth --data "{\"response\":\"${response}\"}" )"

	# obtain validity and session ID from session response
	validSession=$(echo "${sessionResponse}"| jq .session.valid)
	SID=$(echo "${sessionResponse}"| jq --raw-output .session.sid)
}

GetFTLData() {
	data=$(curl -sS -X GET "http://${URL}:${PORT}/${APIPATH}$1" -H "Accept: application/json" -H "sid: ${SID}" )
	echo "${data}"
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

	# restore terminal settings
    stty "${stty_orig}"

    #  Delete session from FTL server
    DeleteSession
    exit $err # exit the script with saved $?
}


################################# Main ################response
while getopts ":u:p:a:s:h" args; do
	case "${args}" in
	u)	URL="${OPTARG}" ;;
    p)	PORT="${OPTARG}" ;;
	a)	APIPATH="${OPTARG}" ;;
	s)	password="${OPTARG}" ;;
	h)	usage
		exit 0 ;;
	\?)	echo "Invalid option: -${OPTARG}"
		exit 1 ;;
	:)	echo "Option -$OPTARG requires an argument."
     	exit 1 ;;
	*)	usage
		exit 0 ;;
	esac
done

# Construct FTL's API address depending on the arguments supplied
ConstructAPI

# Test if the authentication endpoint is availabe
TestAPIAvailability

# Traps for graceful shutdown
# https://unix.stackexchange.com/a/681201
# Trap after TestAPIAvailability to avoid (unnecessary) DeleteSession
trap clean_exit EXIT
trap sig_cleanup INT QUIT TERM

# Authenticate with the server
Authenthication

while true; do
	printf "%b" "\nRequest data from API endpoint:\n"
	read -r endpoint
	GetFTLData "${endpoint}"
done

