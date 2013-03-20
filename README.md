cl-geoip
========

Basic support for MaxMind's IP geolocation databases.

Tested with the [free GeoLite City](http://dev.maxmind.com/geoip/install/city)
database.

Currently supports loading the database and basic querying.

Example
-------

The GeoLiteCity.dat file must be uncompressed first.

    (ql:quickload :cl-geoip)

    (let ((db (geoip:load-db "/path/to/GeoLiteCity.dat)))
      (geoip:get-record db "8.8.8.8"))

License
-------

Simplified BSD License. See `COPYING`.
