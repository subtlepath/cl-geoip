cl-geoip
========

Basic support for MaxMind's IP geolocation databases.

Tested with the [free GeoLite City](http://dev.maxmind.com/geoip/install/city)
database.

Currently supports loading the database and basic querying.

Installing
----------

`git clone git://github.com/subtlepath/cl-geoip.git` somewhere on your
ASDF load path such as ~/quicklisp/local-projects/

For my local Lisp systems I like to create a file
`~/.config/common-lisp/source-registry.conf.d/home-lisp.conf` containing
the following line, and put things in there:

    (:tree "/home/new/lisp/")


Example
-------

The GeoLiteCity.dat file must be uncompressed first.

    (ql:quickload :cl-geoip)

    (let ((db (geoip:load-db "/path/to/GeoLiteCity.dat)))
      (geoip:get-record db "8.8.8.8"))

License
-------

Simplified BSD License. See `COPYING`.
