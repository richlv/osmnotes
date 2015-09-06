# Introduction

OpenStreetMap has notes that allow users to mark things in need for some improvement. For contributors, it is convenient to place notes on a GPS device to review them. OSM API allows to grab GPX, but the contents are not really suitable for using on a GPS device, especially if one would like to see the comments on the note. This script can be used to generate a bit better GPX files.

# Usage

General syntax is:
perl osmnotes.pl --noteid ID,ID,ID --bbox BBOX --bbox BBOX --limit LIMIT

It would connect to the OSM API and download requested individual notes and notes in specified bounding box. Any number of notes and bounding boxes can be specified. By default, the OSM limit on notes inside a bounding box is used, which is 100 at this time. It can be changed with the --limit parameter. Script output is to the standard output, save it to a file like this:

perl osmnotes.pl --noteid 13 > osm_note_13.gpx

Multiple notes can be specified as multiple parameters or as a comma-delimited list, so the following two are the same:

perl osmnotes.pl --noteid 13,14
perl osmnotes.pl --noteid 13 --noteid 14

Bounding box must follow the [OSM notes API](http://wiki.openstreetmap.org/wiki/API_v0.6#Map_Notes_API) syntax of left,bottom,right,top. Multiple bounding boxes can be supplied. If the bounding boxes overlap, notes may appear several times in the output.

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