FROM keyglitch/docker-slic3r-prusa3d:1.41.3

LABEL "name"="Slic3r gcode Action"
LABEL "maintainer"="davidk <kdavid+slic3r+action@gmail.com>"
LABEL "version"="1.0.0"

LABEL "com.github.actions.name"="Slic3r Gcode Action"
LABEL "com.github.actions.description"="Calls Prusa3d's Slic3r fork to generate gcode from STLs"
LABEL "com.github.actions.icon"="package"
LABEL "com.github.actions.color"="blue"

COPY entrypoint.sh /entrypoint.sh
COPY LICENSE-slic3r /

USER root

RUN apt-get update && apt-get install -y jq curl

ENTRYPOINT ["/entrypoint.sh"]
