ARG osrm=5.27.1
FROM ghcr.io/project-osrm/osrm-backend:v${osrm} as builder
# workdir is where everything gets created
WORKDIR /data
RUN apt-get update && apt-get install -y wget
RUN wget -O map.pbf -c http://download.geofabrik.de/europe/romania-latest.osm.pbf

ARG type=bus
COPY ${type}.lua /data/${type}.lua
COPY lib/*.lua /data/lib/

RUN osrm-extract -p $type.lua /data/map.pbf 
RUN osrm-contract /data/map.osrm 


# Building actual image from osrm data created earlier
FROM ghcr.io/project-osrm/osrm-backend:v${osrm}
ENV PORT=5000
COPY --from=builder /data/map.osrm.* /data/
COPY run.sh /usr/local/bin/run.sh
ENTRYPOINT ["run.sh"]
EXPOSE $PORT