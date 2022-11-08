# Custom 🗺️ **transit** profile definition for OSRM

Needed dependecies to proceeed
 - osrm
 - osmium
 - docker
 - romania-latest.osm.pbf -> wget -c http://download.geofabrik.de/europe/great-britain-latest.osm.pbf (if you don't want to bother with planet extracts)


## 🤯 Generating custom map extract

1. You first need to head here and download the full planet export from Openstreet map: https://planet.openstreetmap.org/ and from here download the plannet torrent (60+ Gb of data ~ 2 hour download)

2. Then you need to define your extract area. To do it you can make use of http://bboxfinder.com fo find your bounding box coordinates. Based on osmium spec you need to specify them in *[LNG LAT LNG LAT]* format https://docs.osmcode.org/osmium/latest/osmium-extract.html.
   - my result for Romania is as follows: ```20.121460,43.524655,29.750977,48.330691```


3. Then generate osmium extract from planet exported osm:
   - using ```bounding box```:
   ```sh
   osmium extract -b 20.121460,43.524655,29.750977,48.330691 planet-221031.osm.pbf -o romania.osm.pbf
   ```
   - using ```geojson```:
   ```sh
   osmium extract -p romania.geojson planet-221031.osm.pbf romania.osm.pbf
   ```

## Extract custom routing info for OSRM
In order to extract OSRM data you need to have Docker installed. We make use of docker to run osrm tools agains the profiles we have defined here. Why?: to avoid compiling the software locally and installing dependencies that you might use only once.

- 🚊 TRAM profile
Work with osrm to create custom routing extracts
```sh
# copy osm to tram folder
cp romania.osm.pbf tram/tram.osm.pbf

# remove existing cached osrm data
rm -rf tram/tram.osrm*

# extract data
docker run -t -v "${PWD}:/data" osrm/osrm-backend osrm-extract -p /data/tram.lua /data/tram/tram.osm.pbf 
docker run -t -v "${PWD}:/data" osrm/osrm-backend osrm-contract /data/tram/tram.osrm

# run router
docker run -t -p 5000:5000 -v "${PWD}:/data" osrm/osrm-backend osrm-routed --algorithm ch /data/tram/tram.osrm
```
- 🚍 BUS profile && 🚎 TROLLEY profile
Work with osrm to create custom routing extracts
```sh
# copy osm to tram folder
cp romania.osm.pbf bus/bus.osm.pbf

# remove existing cached osrm data
rm -rf bus/bus.osrm*

# extract data
docker run -t -v "${PWD}:/data" osrm/osrm-backend osrm-extract -p /data/bus.lua /data/bus/bus.osm.pbf 
docker run -t -v "${PWD}:/data" osrm/osrm-backend osrm-contract /data/bus/bus.osrm

# run router
docker run -t -p 5000:5000 -v "${PWD}:/data" osrm/osrm-backend osrm-routed --algorithm ch /data/bus/bus.osrm
```

___
## Debugging with GUI to see how it behaves
You will need 2 containers:
 - router
 - gui


```sh
# start router container
docker run -t -p 5000:5000 -v "${PWD}:/data" osrm/osrm-backend osrm-routed --algorithm ch /data/tram/tram.osrm
# start gui for debugging
docker run -p 9966:9966 osrm/osrm-frontend
```