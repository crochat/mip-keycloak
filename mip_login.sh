#!/bin/bash

source http_lib


#USER_AGENT="openstacksdk/0.46.0 keystoneauthl/4.0.0 python-requests/2.22.0 CPython/3.8.5 osc-lib/2.0.0"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:86.0) Gecko/20100101 Firefox/86.0"
CONTENT_TYPE="application/json"

START_URL="https://mip.humanbrainproject.eu"

#USERNAME=""
#PASSWORD=""



positional=()
verbose_level=0
verbose_string=""
while [[ $# -gt 0 ]]; do
	case $1 in
		-+(v))
			verbose_string="$1"
			verbose_level=$(echo "$1" | cut -c2- | awk -F 'v' '{print NF-1}')
			shift
			;;
		*)
			positional+=("$1")
			shift
			;;
	esac
done
set -- "${positional[@]}"

base_url=""
if [[ "$1" != "" ]]; then
	base_url="$1"
else
	base_url="$START_URL"
fi

nb_sep=$(echo "$base_url" | awk -F '://' '{print $2}' | awk -F '/' '{print NF-1}')
if [[ "$(echo "$base_url" | rev | cut -c1)" = "/" ]]; then
	nb_sep=$(expr $nb_sep - 1)
fi

url=$base_url
if [[ $nb_sep -eq 0 ]]; then
	if [[ "$(echo "$base_url" | rev | cut -c1)" != "/" ]]; then
		base_url+='/'
		url=$base_url
	fi
	url+='services/sso/login'		# < 6.4: local MIP only; >= 6.4: local and federated MIP
fi

username=$USERNAME
password=$PASSWORD


result_headers=""
result_html=""
locations=""
codes=""
code=""

form_url=""
form_params_list=""
links=""
form_alt_link=""
form_alt_text=""

echo -n "Testing headers on URL: $url..."
check_response_code=$(curl -sIL $url | grep -Ei '^http' | tail -1 | awk '{print $2}')
if [[ $check_response_code -ne 200 ]]; then
	echo "ko"
	if [[ "$base_url" != "$url" ]]; then		# Maybe it failed for automatic trial with the main login URL, so we will try an old federated MIP login on HBP
		url=$base_url
		url+='services/login/hbp'

		echo "Failed to connect on the previous URL, as it was automatically completed to match a >= 6.4 or local MIP login. Now trying with an old federated MIP login URL scheme on HBP"
		echo -n "Testing headers on URL: $url..."
		check_response_code=$(curl -sIL $url | grep -Ei '^http' | tail -1 | awk '{print $2}')
		if [[ $check_response_code -ne 200 ]]; then
			echo "ko"
			echo "No luck! It seems that we won't be able to connect on this URL. Exiting!"
			exit 1
		else
			echo "ok"
		fi
	fi
else
	echo "ok"
fi

echo
echo "Connecting to the MIP"
echo "	Sending HTTP GET to $url"
browse ${verbose_string} --follow \
	--return-headers-var 'result_headers' \
	--return-html-var 'result_html' \
	--return-locations-var 'locations' \
	--return-codes-var 'codes' \
	--return-code-var 'code' \
	--return-form-url-var 'form_url' \
	--return-form-method-var 'form_method' \
	--return-form-params-var 'form_params_list' \
	--return-links-var 'links' \
	--effective-urls \
	--cookie-file "cookie" \
	--url "$url"

#echo "$result_headers"
#echo "$result_html"

print_http_response_resume "$codes" "$locations"

if [[ $code -eq 200 ]]; then
	if [[ "$locations" != "" ]]; then
		first_redirect=$(echo "$locations" | cut -d' ' -f1)
		first_redirect=$(url_extract $first_redirect)
		args=$(echo "$first_redirect" | jq -r .args)
		if [[ "$args" != "" ]]; then
			args=$(url2json "$args")
			redirect_url=$(echo "$args" | jq -r .redirect_uri 2>/dev/null)
			if [[ "$redirect_url" != "" ]]; then
				echo "Analyzing redirect_uri..."
				redirect_url=$(rawurldecode "$redirect_url")
				redirect_url=$(url_extract $redirect_url)

				first_url=$(url_extract $url)
			fi
		fi

		if [[ "$first_url" != "" && "$redirect_url" != "" ]]; then
			first_url_full_url=$(echo $first_url | jq -r .full_url)
			first_url_proto=$(echo $first_url | jq -r .proto)
			first_url_host=$(echo $first_url | jq -r .host)
			first_url_port=$(echo $first_url | jq -r .port)
			first_url_path=$(echo $first_url | jq -r .parentpath)
			first_url_filename=$(echo $first_url | jq -r .filename)

			redirect_url_full_url=$(echo $redirect_url | jq -r .full_url)
			redirect_url_proto=$(echo $redirect_url | jq -r .proto)
			redirect_url_host=$(echo $redirect_url | jq -r .host)
			redirect_url_port=$(echo $redirect_url | jq -r .port)
			redirect_url_path=$(echo $redirect_url | jq -r .parentpath)
			redirect_url_filename=$(echo $redirect_url | jq -r .filename)
			if [[ "$first_url_full_url" != "$redirect_url_full_url" ]]; then
				echo "WARNING: The redirect_uri parameter points to a different URL than the first one. It may fail when it has to go back to the MIP."
				differences='URL (start vs redirect) : '$first_url_full_url' <> '$redirect_url_full_url
				if [[ "$first_url_proto" != "$redirect_url_proto" ]]; then
					differences+='
Protocol (start vs redirect) : '$first_url_proto' <> '$redirect_url_proto
				fi
				if [[ "$first_url_host" != "$redirect_url_host" ]]; then
					differences+='
Host (start vs redirect) : '$first_url_host' <> '$redirect_url_host
				fi
				if [[ "$first_url_port" != "$redirect_url_port" ]]; then
					differences+='
Port (start vs redirect) : '$first_url_port' <> '$redirect_url_port
				fi
				if [[ "$first_url_path" != "$redirect_url_path" ]]; then
					differences+='
Path (start vs redirect) : '$first_url_path' <> '$redirect_url_path
				fi
				if [[ "$first_url_filename" != "$redirect_url_filename" ]]; then
					differences+='
Filename (start vs redirect) : '$first_url_filename' <> '$redirect_url_filename
				fi
			fi
		fi

		column -t <<< "$differences"
		echo
		echo -n "Continue? [y/n] "
		read answer
		if [[ "$answer" != "y" ]]; then
			exit 0
		fi
	fi

	if [[ "$links" != "" ]]; then
		links=$(echo "$links" | cut -d'+' -f1)
		link_href=$(echo "$links" | cut -d, -f1)
		link_text=$(echo "$links" | cut -d, -f2)
		if [[ "$link_href" != "" && "$link_text" != "" ]]; then
			form_alt_link=$link_href
			form_alt_text=$link_text
		fi
	fi
fi

if [[ "$form_params_list" != "" ]]; then
	if [[ "$(echo "$form_params_list" | grep -F 'kc-login')" != "" ]]; then
		echo
		echo "Got a KeyCloak login form!"
		if [[ "$form_alt_link" != "" ]]; then
			echo "Apparently, there's also a link to an alternate login form ($form_alt_text), through an Identity Provider."
			echo -n "Would you like to use it instead? [y/n] "
			read answer
			echo
			if [[ "$answer" != "y" ]]; then
				form_alt_link=""
				form_alt_text=""
			fi
		fi
	fi
fi

if [[ "$form_alt_link" != "" ]]; then
	result_headers=""
	result_html=""
	locations=""
	codes=""
	code=""

	form_url=""
	form_method=""
	form_params_list=""
	form_params=""
	links=""

	echo
	echo "Following link to Identity Provider"
	echo "	Sending HTTP GET to $form_alt_link"
	browse ${verbose_string} --follow \
		--return-headers-var 'result_headers' \
		--return-html-var 'result_html' \
		--return-locations-var 'locations' \
		--return-codes-var 'codes' \
		--return-code-var 'code' \
		--return-form-url-var 'form_url' \
		--return-form-method-var 'form_method' \
		--return-form-params-var 'form_params_list' \
		--return-links-var 'links' \
		--effective-urls \
		--cookie-file "cookie" \
		--url "$form_alt_link"

	#echo "$result_headers"
	#echo "$result_html"

	print_http_response_resume "$codes" "$locations"

	if [[ $code -eq 200 && "$(echo "$form_params_list" | grep -F 'kc-login')" != "" ]]; then
		echo
		echo "Got the final KeyCloak login form!"
	fi
fi




if [[ $code -eq 200 ]]; then
	if [[ "$form_url" != "" && "$form_params_list" != "" && "$form_params" = "" ]]; then
		prepare_form --params "$form_params_list" --return-form-params-var 'form_params'
	fi
fi

location=""
if [[ "$form_url" != "" && "$form_params" != "" ]]; then
	result_headers=""
	result_html=""
	locations=""
	codes=""
	code=""

	echo
	echo "Posting the KeyCloak form with provided credentials."
	echo "	Sending HTTP POST to $form_url"
	browse ${verbose_string} \
		--return-headers-var 'result_headers' \
		--return-html-var 'result_html' \
		--return-locations-var 'locations' \
		--return-codes-var 'codes' \
		--return-code-var 'code' \
		--content-type 'application/x-www-form-urlencoded' \
		--cookie-file "cookie" \
		--params "$form_params" \
		--method "POST" \
		--url "$form_url"

	#echo "$result_headers"
	#echo "$result_html"

	print_http_response_resume "$codes" "$locations"

	if [[ $code -eq 302 ]]; then
		echo
		echo "Received an HTTP 302 from KeyCloak's identity provider, but I intercepted the call, because HTTP RFC says that with 302,"
		echo "we're supposed to follow the new location with the same method used previously, which was POST. But here, GET is expected..."
		location=$(echo "$locations" | awk '{print $NF}')
	fi
fi




if [[ "$location" != "" ]]; then
	result_headers=""
	result_html=""
	locations=""
	codes=""
	code=""

	echo "	Sending HTTP GET to <$location>"
	browse ${verbose_string} --follow \
		--return-headers-var 'result_headers' \
		--return-html-var 'result_html' \
		--return-locations-var 'locations' \
		--return-codes-var 'codes' \
		--return-code-var 'code' \
		--cookie-file "cookie" \
		--url "$location"

	#echo "$result_headers"
	#echo "$result_html"

	print_http_response_resume "$codes" "$locations"
fi

if [[ $code -eq 200 && "$result_html" != "" ]]; then
	result_html=$(echo "$result_html" | tidy -q -wrap -clean -ashtml -indent 2>/dev/null)
	if [[ $verbose_level -ge 1 ]]; then
		echo
		echo "$result_html"
	fi
fi
