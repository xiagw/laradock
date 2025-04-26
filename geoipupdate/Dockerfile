FROM maxmindinc/geoipupdate
RUN sed -i '/\/usr\/bin\/geoipupdate/ a   cp $GEOIPUPDATE_DB_DIR/*.mmdb /nginx/' /usr/bin/entry.sh
