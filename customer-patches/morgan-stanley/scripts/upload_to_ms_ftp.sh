#!/usr/bin/env bash

ensureNoSlash() {
	local input="${1}"

	local len=${#input}
	local lastChar=${input:len-1:1}

	if [ "${lastChar}" != "/" ]; then
		echo "${input}"
	else
		echo "${input:0:len-1}"
	fi
}

uploadToFtp() {
	local file="${1}"
	local ftpHostWithUsernamePassword="${2}"
	local ftpPath
	ftpPath="$(ensureNoSlash "${3}")"

	curl --retry 10 --retry-delay 5 --no-epsv --ftp-create-dirs --upload-file "${file}" "${ftpHostWithUsernamePassword}/${ftpPath}/"
	return
}

computeSha256() {
	local file="${1}"
	sha256sum "${file}" >"${file}.sha256"
	return
}

downloadFromFtp() {
	local file="${1}"
	local ftpHostWithUsernamePassword="${2}"
	local ftpPath
	ftpPath="$(ensureNoSlash "${3}")"

	curl --retry 10 --retry-delay 5 --no-epsv -o "${file}" "${ftpHostWithUsernamePassword}/${ftpPath}/${file}"
	return
}

verifySha256() {
	local file="${1}"
	sha256sum --check "${file}.sha256"
	return
}

push-to-ms-ftp() {
	local file="${1}"
	local hostWithUsernamePassword="${2}"
	local ftpPath="${3}"

	computeSha256 "${file}"
	uploadToFtp "${file}" "${hostWithUsernamePassword}" "${ftpPath}"
	uploadToFtp "${file}.sha256" "${hostWithUsernamePassword}" "${ftpPath}"

	mkdir downloads
	pushd downloads || exit
	{
		downloadFromFtp "${file}" "${hostWithUsernamePassword}" "${ftpPath}"
		downloadFromFtp "${file}.sha256" "${hostWithUsernamePassword}" "${ftpPath}"
		verifySha256 "${file}"
	}
	popd || exit
	return
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
	set -e
	push-to-ms-ftp "$@"
fi
