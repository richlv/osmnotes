use strict;
use warnings;

use LWP::Simple;
use XML::LibXML;
#use Data::Dumper;
use JSON::XS;
use Getopt::Long qw(GetOptions);
use List::Util 'first';

my $single_note_url = 'http://api.openstreetmap.org/api/0.6/notes/';
my $bbox_url        = 'http://api.openstreetmap.org/api/0.6/notes.json?bbox=';
my $regionfile      = 'regions.json';
my $finalgpxversion = '1.0';
my $usage = <<"USAGE";
$0 --noteid ID,ID,ID --noteid ID
$0 --noteid ID,ID,ID --bbox BBOX --bbox BBOX --limit LIMIT --closed CLOSED --topleft "TOPLEFT_MAPURL" --bottomright "BOTTOMRIGHT_MAPURL"
  * bbox: bounding box using format left,bottom,right,top
  * limit: maximum number of notes. OSM default - 100
  * closed: for how long a note may be closed to still include it. OSM default - 7. 0 - do not include closed notes. -1 - inlude all closed notes
  * topleft, bottomright: OSM URL of the top left and bottom right corner of the besired bounding box, correspondingly
USAGE

my $parsed_note_json;
my $bboxnotes;
my $limitstring = '';
my $closedstring = '';

# osm api default is 100, not specified here
my @note_ids;
my @bboxes;
my @regions;
my ($limit, $closed);
my ($topleft, $bottomright);
GetOptions(
    'noteid|n=s'    => \@note_ids,
    'bbox|b=s'      => \@bboxes,
    'limit|l=i'     => \$limit,
    'closed|c=i'    => \$closed,
    'topleft=s'     => \$topleft,
    'bottomright=s' => \$bottomright,
    'region|r=s'    => \@regions,
) or die "Usage:\n$usage";

@note_ids = split(/,/,join(',',@note_ids));

if ($topleft xor $bottomright) {
	print "If either --topleft or --bottomright is specified, the other must be as well\n";
	die;
}

if ($topleft and $bottomright) {
	# from osm urls, generate and add a bounding box
	my ($top, $left, $bottom, $right);
	($top = $topleft) =~ s/.*#map=[0-9]+\/([0-9]+(\.[0-9]+)?).*/$1/;
	($left = $topleft) =~ s/.*#map=[0-9]+\/[0-9]+(?:\.[0-9]+)?\/([0-9]+(\.[0-9]+)?).*/$1/;
	($bottom = $bottomright) =~ s/.*#map=[0-9]+\/([0-9]+(\.[0-9]+)?).*/$1/;
	($right = $bottomright) =~ s/.*#map=[0-9]+\/[0-9]+(?:\.[0-9]+)?\/([0-9]+(\.[0-9]+)?).*/$1/;
	push @bboxes, "$left,$bottom,$right,$top";
}

if (not @note_ids and not @bboxes) {
	print "Specify some note IDs and/or bounding boxes. Usage:\n$usage";
	die;
}

if ($limit and not @bboxes) {
	print "Limit specified, but no bounding boxes - only use --limit with at least one --bbox\n";
	die;
}

if ($closed and not @bboxes) {
	print "Parameter 'closed' specified, but no bounding boxes - only use --closed with at least one --bbox\n";
	die;
}

my $non_integer = first {/\D/} @note_ids;
if ($non_integer) {
	print "Non-numeric node ID passed: '$non_integer'\n";
	die;
}

my $final_gpx = XML::LibXML::Document->createDocument($finalgpxversion);
my $gpxroot   = $final_gpx->createElement('gpx');
$gpxroot->addChild($final_gpx->createAttribute(version => '1.1'));
$gpxroot->addChild($final_gpx->createAttribute(creator => 'osmnotes.pl'));
$gpxroot->addChild($final_gpx->createAttribute(xmlns => 'http://www.topografix.com/GPX/1/1'));

sub parse_note {
	my ($note) = @_;
	my $desc;
	my $lon                = $note->{geometry}->{coordinates}[0];
	my $lat                = $note->{geometry}->{coordinates}[1];
	my $parsed_nodeid      = $note->{properties}->{id};
	my $date_created       = $note->{properties}->{date_created};
	my $note_comments      = $note->{properties}->{comments};
	my $note_comment_count = @$note_comments;
	foreach (my $commentid = 0; $commentid <$note_comment_count; $commentid++ ) {
		my $comment_date   = $note->{properties}->{comments}[$commentid]->{date};
		my $comment_user   = $note->{properties}->{comments}[$commentid]->{user};
		my $comment_text   = $note->{properties}->{comments}[$commentid]->{text};
		my $comment_action = $note->{properties}->{comments}[$commentid]->{action};
		if (! $comment_user) {
			$comment_user = 'Anon';
		}
		$desc .= "$comment_date ";
		$desc .= "[$comment_action] $comment_user: ";
		$desc .= "$comment_text\n";
	}
	my $new_wpt = $final_gpx->createElement('wpt');
	$new_wpt->addChild($final_gpx->createAttribute(lat => "$lat"));
	$new_wpt->addChild($final_gpx->createAttribute(lon => "$lon"));
	my $note_name = "OSM note $parsed_nodeid";
	$new_wpt->appendTextChild('name', $note_name);
#	garmin oregon 650 does not support 'desc', only 'cmt'
	$new_wpt->appendTextChild('cmt', $desc);
	$new_wpt = $gpxroot->appendChild($new_wpt);
}

sub validate_bbox {
	my ($bbox_to_validate) = @_;
	my @bboxvalues = split(/,/,$bbox_to_validate);
	my $bboxvalue_count = @bboxvalues;
	if ($bboxvalue_count != '4') {
		print "Bounding box '$bbox_to_validate' does not seem to have four comma-delimited parts";
		die;
	}
	foreach my $bboxvalue (@bboxvalues) {
		if ($bboxvalue !~ /^[+-]?\d+\.?\d*\z/) {
			print "$bboxvalue does not look like a proper decimal number\n";
			die;
		}
	}
}

foreach my $note_id (@note_ids) {
	$parsed_note_json = decode_json(get($single_note_url . $note_id . ".json"));
#	print Dumper($parsed_note_json);
	if ($parsed_note_json->{type} ne 'Feature') {
		print "ERROR: Incoming JSON type not 'FeatureCollection', stopping\n";
		die;
	}
	parse_note($parsed_note_json);
}

if (@regions) {
	my $fh;
	open($fh, '<:raw', $regionfile) or die "Region specified, but can't open $regionfile";
	my $known_regions = do { local $/; decode_json(<$fh>); };
	close $fh;
	foreach my $region (@regions) {
		# TODO: look up region name in the list, add to bboxes if found, error out if not
	}
}

if (defined $limit) {
	$limitstring = "&limit=$limit";
}

if (defined $closed) {
	$closedstring = "&closed=$closed";
}

foreach my $bbox (@bboxes) {
	validate_bbox($bbox);
	my $bboxfinalurl = $bbox_url . $bbox . $limitstring . $closedstring;
	$parsed_note_json = decode_json(get($bboxfinalurl));
	if ($parsed_note_json->{type} ne 'FeatureCollection') {
		print "ERROR: Incoming JSON type not 'FeatureCollection', stopping\n";
		die;
	}
	my $feature_ref   = $parsed_note_json->{features};
	my $feature_count = @$feature_ref;
#	print "found $feature_count features/notes\n";
	foreach (my $featureid = 0; $featureid < $feature_count; $featureid++ ) {
		my $note = $parsed_note_json->{features}[$featureid];
		parse_note($note);
	}
}

$gpxroot = $final_gpx->addChild($gpxroot);
print $final_gpx->toString(1);
