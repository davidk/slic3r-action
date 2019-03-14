#!/bin/bash -l
# GitHub Actions Slic3r
# Convert .STL files to .gcode for use with 3D printers
#
# *** This action expects the following parameters AND environmental variables ***
# 
# entrypoint.sh [relative_path_to_stl] [relative_path_to_stl]
#
# GITHUB_TOKEN - A secret so that the action can add gcode to the repository
# SLICE_CFG    - Your slic3r configuration, with layer height, filament and printer settings pre-selected.
#
# *** Where to get the parameters ***
#
# SLICE_CFG - When slic3r is open (with preferred settings selected), go to File -> Export Config
# [relative_path_to_stl] - This is the path to the STL inside of your repository; ex: "kittens/large_cat_120mm.stl"
# GITHUB_TOKEN - A checkbox is available in the visual editor, but it can also be added by hand.
#
# *** Optional environmental variables that can be provided ***
#
# EXTRA_SLICER_ARGS - these are additions to the slic3r command-line; ex: --print-center 100,100
# BRANCH - the branch to operate on for queries to the API (default: master; others untested)
# UPDATE_RETRY - the number of times to retry a repository update, in case we desync between SHA grab and update
# CENTER_OF_BED - The center of the bed. This is used to figure out where to place the object.
WORKDIR="/github/workspace"

# Create a lock but wait if it is already held. 
# This and the retry system help to work around inconsistent repository operations.
# Derived from the flock(2) manual page.
echo "Launched at: $(date +%H:%M:%S:%N)"

(
flock 9 

echo "Running at: $(date +%H:%M:%S:%N)"

if [[ -z "${BRANCH}" ]]; then
	BRANCH=master
fi

if [[ -z "${UPDATE_RETRY}" ]]; then
	UPDATE_RETRY=5
fi

echo ">>> Branch: ${BRANCH}"

if [[ ! -e "${WORKDIR}/${SLICE_CFG}" || -z "${SLICE_CFG}" ]]; then
	echo -e "\n!!! ERROR: Unable to find 'SLICE_CFG: [ ${SLICE_CFG} ]' in your repository !!!"
	echo
	echo "Some possible things to look at:"
	echo "* This is a environmental variable in GitHub Actions, or 'env', and should be defined in your action like this:"
	echo -e "env = {\n"
	echo -e "\tSLICE_CFG = \"config.ini\""
	echo -e "}\n"
	echo "* The path is relative to the root of your repository: 'config.ini' or 'stls/config.ini'"
	echo

	exit 1
fi

# Attempt to determine the center of the bed, since the Slic3r CLI defaults to placing objects 
# at 100,100 (which may not be appropriate for all machines)
# Note: CENTER_OF_BED gets set to 100,100 if this fails.
if [[ -z "${CENTER_OF_BED}" ]]; then
	BEDSHAPE="$(grep bed_shape "${WORKDIR}/${SLICE_CFG}" | cut -d, -f3)"

	echo ">>> Got bed_shape from configuration file: ${BEDSHAPE}"
	# Example: 123x230
	if [[ $BEDSHAPE =~ ^[0-9]+x[0-9]+ ]]; then
		CENTER_OF_BED="$((${BEDSHAPE%x*}/2)),$((${BEDSHAPE#*x}/2))"
	fi
fi

echo ">>> Center of bed coordinates will be set to: ${CENTER_OF_BED}"

if [[ -z "${GITHUB_TOKEN}" ]]; then
	echo -e "\n!!! ERROR: Unable to find your GITHUB_TOKEN !!!"
	echo
	echo "Some possible hints on fixing this:"
	echo "This is a secret that is provided through GitHub Actions. The visual editor can provide more guidance and do this for you automatically"
	echo "To do this manually, add this line to your actions"
	echo "secret = [\"GITHUB_TOKEN\"]"
	echo

	exit 1
fi

# EXTRA_SLICER_ARGS
# This lets a user define additional arguments to Slic3r without having to fork and modify the
# command-line below. 
# These is added to the env 'EXTRA_SLICER_ARGS' in the workflow on a single line (note the lack of quoting):
# --print-center 100,100 --output-filename-format {input_filename_base}_{printer_model}.gcode_updated
if [[ ! -z "${EXTRA_SLICER_ARGS}" ]]; then
	echo -e "Adding the following arguments to Slic3r: ${EXTRA_SLICER_ARGS}"
	IFS=' ' read -r -a EXTRA_SLICER_ARGS <<< "${EXTRA_SLICER_ARGS}"
fi

echo -e "\n>>> Processing STLs $* with ${SLICE_CFG}\n"

for stl in "$@"; do
	mkdir -p "${WORKDIR}/${TMPDIR}"
	TMPDIR="$(mktemp -d)"

	echo -e "\n>>> Generating STL for ${stl} ...\n"
	if /Slic3r/slic3r-dist/slic3r \
		--no-gui \
		--load "${WORKDIR}/${SLICE_CFG}" \
		--output-filename-format '{input_filename_base}_{layer_height}mm_{filament_type[0]}_{printer_model}.gcode_updated' \
		--output "${TMPDIR}" \
		--print-center "${CENTER_OF_BED:-100,100}" \
		"${EXTRA_SLICER_ARGS[@]}" "${WORKDIR}/${stl}"; then
		echo -e "\n>>> Successfully generated gcode for STL\n"
	else
		exit_code=$?
		echo -e "\n!!! Failure generating STL  - rc: ${exit_code} !!!\n"
		exit ${exit_code}
	fi

	GENERATED_GCODE="$(basename "$(find "$TMPDIR" -name '*.gcode_updated')")"
	DEST_GCODE_FILE="${GENERATED_GCODE%.gcode_updated}.gcode"

	# Get path, including any subdirectories that the STL might belong in
	# but exclude the WORKDIR
	STL_DIR="$(dirname "${WORKDIR}/${stl}")"
	GCODE_DIR="${STL_DIR#"$WORKDIR"}"

	GCODE="${GCODE_DIR}/${DEST_GCODE_FILE}"
	GCODE="${GCODE#/}"

	echo -e "\n>>> Processing file as ${GCODE}\n"

	if [[ -e "${WORKDIR}/${GCODE}" ]]; then
		echo -e "\n>>> Updating existing file in ${WORKDIR}/${GCODE}\n"
		# This is a GraphQL call to avoid downloading the generated .gcode files (which may 403 when the file is too large)
		# Syntax used below:
		# ${GITHUB_REPOSITORY%/*} -- capture the username before the '/'
		# ${GITHUB_REPOSITORY#*/} -- capture the repository name after the '/'
		# ${GCODE#./}			  -- remove the './' prefix in front of paths if it exists

		while true; do

			if SHA="$({
				curl -f -sSL \
				-H "Authorization: bearer ${GITHUB_TOKEN}" \
				-H "User-Agent: github.com/davidk/slic3r-action" \
				"https://api.github.com/graphql" \
				-d @- <<-EOF
				{
				"query": "query {repository(owner: \"${GITHUB_REPOSITORY%/*}\", name: \"${GITHUB_REPOSITORY#*/}\") {object(expression: \"${BRANCH}:${GCODE#./}\"){ ... on Blob { oid } }}}"
				}
EOF
				} | jq -r '.data | .repository | .object | .oid')"; then
					echo -e "\n>>> Successfully retrieved sha:${SHA} from GitHub GraphQL API\n"
			else
				exit_code=$?

				echo -e "\n!!! Failed to get SHA from the GitHub GraphQL API - rc: ${exit_code} !!!\n"

				SHA=""

				echo -e "\n!!! Retry attempts: ${UPDATE_RETRY} !!!\n"

				if [[ ${UPDATE_RETRY} -le 0 ]]; then
					echo -e "!!! Ran out of retry attempts."
					exit $exit_code
				fi

			fi

			if [[ "${SHA}" == "null" ]]; then
				echo -e "\n>>> New file\n"
				break
			fi

			if curl -f -sSL \
				-X PUT "https://api.github.com/repos/${GITHUB_REPOSITORY}/contents/${GCODE}" \
				-H "Accept: application/vnd.github.v3+json" \
				-H "Authorization: token ${GITHUB_TOKEN}" \
				-H "User-Agent: github.com/davidk/slic3r-action" \
				-d @- <<-EOF
				{
				  "message": "Slic3r: updating ${GCODE}",
				  "branch": "${BRANCH}",
				  "committer": {
				    "name": "${GITHUB_ACTOR}",
				    "email": "${GITHUB_ACTOR}@example.com"
				  },
				  "content": "$(base64 < "${TMPDIR}/${GENERATED_GCODE}")",
				  "sha": "${SHA}"
				}
EOF
			then
				echo -e "\n>>> Successfully updated ${GCODE} using the GitHub API\n"
				break
			else
				exit_code=$?
				echo "!!! Couldn't update ${GCODE} with SHA ${SHA} using the GitHub API - rc: ${exit_code} !!!"
				echo "!!! Possible reasons for this error !!!"
				echo "!!! * GitHub API is down (see the return code) !!!"
				echo "!!! * Two actions are trying to update the repository at the same time (409 conflict) !!!"
				echo "!!! Workaround: Make actions depend on each other with the 'needs' keyword            !!!"
				echo "!!! Retry attempts: ${UPDATE_RETRY} !!!"

				if [[ ${UPDATE_RETRY} -le 0 ]]; then
					echo -e "!!! Ran out of retry attempts."
					exit $exit_code
				fi
			fi

			if [[ ${UPDATE_RETRY} -gt 0 ]]; then
				sleep ${UPDATE_RETRY}
				echo -e "!!! Retrying due to errors. !!!"
			fi

			((UPDATE_RETRY--))
		done
	else

		echo -e "\n>>> Committing new file ${GCODE}\n"

		if curl -f -sSL \
		-X PUT "https://api.github.com/repos/${GITHUB_REPOSITORY}/contents/${GCODE}" \
		-H "Accept: application/vnd.github.v3+json" \
		-H "Authorization: token ${GITHUB_TOKEN}" \
		-H "User-Agent: github.com/davidk/slic3r-action" \
		-d @- <<-EOF
		{
		  "message": "Slic3r: adding ${GCODE}",
		  "branch": "${BRANCH}",
		  "committer": {
		    "name": "${GITHUB_ACTOR}",
		    "email": "${GITHUB_ACTOR}@example.com"
		  },
		  "content": "$(base64 < "${TMPDIR}/${GENERATED_GCODE}")"
		}
EOF
		then
			echo -e "\n>>> Successfully added a new file (${GCODE}) using the GitHub API\n"
		else
			exit_code=$?
			echo -e "!!! Unable to upload ${GCODE} using the GitHub API - rc: ${exit_code} !!!"
			exit $exit_code
		fi
	fi

	echo -e "\n>>> Finished processing file\n"

	rm -rf "${TMPDIR}"
done
) 9>"$WORKDIR/slice.lock"

echo "Completed at: $(date +%H:%M:%S:%N)"
