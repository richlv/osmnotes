# Introduction

OpenStreetMap has notes that allow users to mark things in need for some improvement. For contributors, it is convenient to place notes on a GPS device to review them. OSM API allows to grab GPX, but the contents are not really suitable for using on a GPS device, especially if one would like to see the comments on the note. This script can be used to generate a bit better GPX files.

# Usage

General syntax:
```
perl osmnotes.pl --noteid ID,ID,ID --noteid ID
perl osmnotes.pl --noteid ID,ID,ID --bbox BBOX --bbox BBOX --limit LIMIT --closed CLOSED --topleft "TOPLEFT_MAPURL" --bottomright "BOTTOMRIGHT_MAPURL" --region REGION
```

It would connect to the OSM API and download requested individual notes and notes in specified bounding box. Any number of notes and bounding boxes can be specified. By default, the OSM limit on notes inside a bounding box is used, which is 100 at this time. It can be changed with the `--limit` parameter. Script output is to the standard output, save it to a file like this:
```
perl osmnotes.pl --noteid 13 > osm_note_13.gpx
```

Multiple notes can be specified as multiple parameters or as a comma-delimited list, so the following two are the same:
```
perl osmnotes.pl --noteid 13,14
perl osmnotes.pl --noteid 13 --noteid 14
```

Specifying top left and bottom right corners can be done by passing nearly any OSM URL. An easy way to obtain those is to centre the map in the browser on the desired top left or bottom right corner and copy the URL. An example invocation:
```
perl --topleft "http://www.openstreetmap.org/#map=12/56.9885/24.0940" --bottomright "http://www.openstreetmap.org/#map=12/56.8738/24.3890"
```

"Closed" specifies for how many days a note may be closed to still show it. OSM API default is 7. Setting it to 0 will not include closed notes. Setting it to -1 will include all notes, no matter how long ago they were closed. Setting it to 'only' will return closed notes only.

Bounding box must follow the [OSM notes API](http://wiki.openstreetmap.org/wiki/API_v0.6#Map_Notes_API) syntax of left,bottom,right,top. Multiple bounding boxes can be supplied. If the bounding boxes overlap, notes may appear several times in the output.

Regions are predefined name:bbox pairs, read from a JSON file. Instead of remembering a bbox or specifying topleft and bottomright, one could just do:
```
perl osmnotes.pl --region latvia:riga
```
to get all notes in a region, associated with that name.

# Dependencies

Perl module dependencies:

* LWP::Simple
* XML::LibXML
* JSON::XS
* Getopt::Long
* List::Util

# Quality

This is the first ever thing the author has written in Perl from the scratch. Quality is expected to be terrible, so please, do comment and suggest improvements :)

# Other projects

Other projects like this exist, for example, https://github.com/SomeoneElseOSM/Notes01 in Java. It offers more functionality, but Java seemed to be a bit of an overkill for something like this. Plus the chance to try and write something in Perl, see the "Quality" section above :)
