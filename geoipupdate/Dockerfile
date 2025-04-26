FROM maxmindinc/geoipupdate
RUN sed -i '/\/usr\/bin\/geoipupdate/ a   cp -v $GEOIPUPDATE_DB_DIR/*.mmdb /nginx/' /usr/bin/entry.sh
