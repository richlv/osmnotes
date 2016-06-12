use strict;
use warnings;

package App::OSMNotes;

use LWP::Simple;
use XML::LibXML;
#use Data::Dumper;
use JSON::XS;
use Getopt::Long qw(GetOptions);
use List::Util 'first';
use Scalar::Util qw(looks_like_number);

run() unless caller;

sub parse_note {
	my ($note) = @_;
	my %osmnote;
	$osmnote{lon}           = $note->{geometry}->{coordinates}[0];
	$osmnote{lat}           = $note->{geometry}->{coordinates}[1];
	$osmnote{parsed_noteid} = $note->{properties}->{id};
	$osmnote{status}        = $note->{properties}->{status};
	foreach my $comment (@{$note->{properties}{comments}}) {
		# OSM usernames have minimum length limit of 3, this should not trip on 0
		my $comment_user = $comment->{user} || 'Anon';
		$osmnote{desc} .= "$comment->{date} ";
		$osmnote{desc} .= "[$comment->{action}] $comment_user: ";
		$osmnote{desc} .= "$comment->{text}\n";
	}
	return \%osmnote;
}

sub validate_bbox {
	my ($bbox_to_validate) = @_;
	my @bboxvalues = split(/,/,$bbox_to_validate);
	my $bboxvalue_count = @bboxvalues;
	if ($bboxvalue_count != '4') {
		die "Bounding box '$bbox_to_validate' does not seem to have four comma-delimited parts\n";
	}
	foreach my $bboxvalue (@bboxvalues) {
		if ($bboxvalue !~ /^[+-]?\d+\.?\d*\z/) {
			die "$bboxvalue does not look like a proper decimal number\n";
		}
	}
	return 1;
}

sub add_waypoint {
	my $osmnote = shift;
	my $final_gpx = shift;
	my $gpxroot = shift;

	my $new_wpt = $final_gpx->createElement('wpt');
	$new_wpt->addChild($final_gpx->createAttribute(lat => $osmnote->{lat}));
	$new_wpt->addChild($final_gpx->createAttribute(lon => $osmnote->{lon}));
	my $note_name = "OSM note $osmnote->{parsed_noteid}";
	$new_wpt->appendTextChild('name', $note_name);
	# garmin oregon 650 does not support 'desc', only 'cmt'
	$new_wpt->appendTextChild('cmt', $osmnote->{desc});
	$new_wpt = $gpxroot->appendChild($new_wpt);
}

sub run {
	my $single_note_url = 'http://api.openstreetmap.org/api/0.6/notes/';
	my $bbox_url        = 'http://api.openstreetmap.org/api/0.6/notes.json?bbox=';
	my $regionfile      = 'regions.json';
	my $finalgpxversion = '1.0';
	my $usage = <<"USAGE";
$0 --noteid ID,ID,ID --noteid ID
$0 --noteid ID,ID,ID --bbox BBOX --bbox BBOX --limit LIMIT --closed CLOSED --topleft "TOPLEFT_MAPURL" --bottomright "BOTTOMRIGHT_MAPURL" --region REGION
  * bbox: bounding box using format left,bottom,right,top
  * limit: maximum number of notes. OSM default - 100
  * closed: for how long a note may be closed to still include it. OSM default - 7. 0 - do not include closed notes. -1 - inlude all closed notes. "only" - include only closed notes
  * topleft, bottomright: OSM URL of the top left and bottom right corner of the desired bounding box, correspondingly
  * region: a predefined region from $regionfile
USAGE

	my $parsed_note_json;
	my $bboxnotes;
	my $limitstring = '';
	my $closedstring = '';

	# osm API default is 100, not specified here
	my @note_ids;
	my @bboxes;
	my @regions;
	my ($limit, $closed);
	my ($topleft, $bottomright);
	my $help;
	# the default osm limit - should be maintained and should match the actual limit on the API side
	my $osmlimit = 100;
	GetOptions(
		'noteid|n=s'    => \@note_ids,
		'bbox|b=s'      => \@bboxes,
		'limit|l=i'     => \$limit,
		'closed|c=s'    => \$closed,
		'topleft=s'     => \$topleft,
		'bottomright=s' => \$bottomright,
		'region|r=s'    => \@regions,
		'help'          => \$help,
	) or die "Usage:\n$usage";

	if ($help) {
		die "Usage:\n$usage";
	}

	@note_ids = split(/,/,join(',',@note_ids));

	if ($topleft xor $bottomright) {
		die "If either --topleft or --bottomright is specified, the other must be as well\n";
	}
	if ($topleft and $bottomright) {
		# from osm urls, generate and add a bounding box
		my ($top, $left, $bottom, $right);
		($top = $topleft) =~ s/.*#map=[0-9]+\/([0-9]+(\.[0-9]+)?).*/$1/;
		($left = $topleft) =~ s/.*#map=[0-9]+\/[0-9]+(?:\.[0-9]+)?\/(-*[0-9]+(\.[0-9]+)?).*/$1/;
		($bottom = $bottomright) =~ s/.*#map=[0-9]+\/([0-9]+(\.[0-9]+)?).*/$1/;
		($right = $bottomright) =~ s/.*#map=[0-9]+\/[0-9]+(?:\.[0-9]+)?\/(-*[0-9]+(\.[0-9]+)?).*/$1/;
		push @bboxes, "$left,$bottom,$right,$top";
	}

	if (not @note_ids and not @bboxes and not @regions) {
		die "Specify some note IDs and/or bounding boxes. Usage:\n$usage";
	}

	if ($limit and not @bboxes) {
		die "Limit specified, but no bounding boxes - only use --limit with at least one --bbox\n";
	}

	if ($closed and not @bboxes) {
		die "Parameter 'closed' specified, but no bounding boxes - only use --closed with at least one --bbox\n";
	}

	my $non_integer_noteid = first {/\D/} @note_ids;
	if ($non_integer_noteid) {
		die "Non-numeric note ID passed: '$non_integer_noteid'\n";
	}

	my $final_gpx = XML::LibXML::Document->createDocument($finalgpxversion);
	my $gpxroot   = $final_gpx->createElement('gpx');
	$gpxroot->addChild($final_gpx->createAttribute(version => '1.1'));
	$gpxroot->addChild($final_gpx->createAttribute(creator => 'osmnotes.pl'));
	$gpxroot->addChild($final_gpx->createAttribute(xmlns => 'http://www.topografix.com/GPX/1/1'));
	$gpxroot->setNamespace('http://www.w3.org/2001/XMLSchema-instance', 'xsi', 0);
	$gpxroot->setAttributeNS('http://www.w3.org/2001/XMLSchema-instance', 'schemaLocation', 'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd');

	foreach my $note_id (@note_ids) {
		$parsed_note_json = decode_json(get($single_note_url . $note_id . ".json"));
		if ($parsed_note_json->{type} ne 'Feature') {
			die "ERROR: Incoming JSON type not 'FeatureCollection', stopping\n";
		}
		my $osmnote = parse_note($parsed_note_json);
		add_waypoint($osmnote, $final_gpx, $gpxroot);
	}

	if (@regions) {
		my $fh;
		open($fh, '<:raw', $regionfile) or die "Region specified, but can't open $regionfile";
		my $known_regions = do { local $/; decode_json(<$fh>); };
		close $fh;
		foreach my $region (@regions) {
			my @matched_region = split(/\|/,$known_regions->{$region});
			print scalar @matched_region."\n";
			if (@matched_region) {
				push @bboxes, @matched_region;
			}
			else {
				die "Region \"$region\" not found in file \"$regionfile\"\n";
			}
		}
	}

	if (defined $limit) {
		$limitstring = "&limit=$limit";
	}

	if (defined $closed) {
		if (looks_like_number($closed)) {
			if ($closed != int($closed) or $closed < -1) {
				die "Numeric parameter 'closed' passed that's not an integer or is smaller than -1\n";
			}
			else {
				$closedstring = "&closed=$closed";
			}
		}
		else {
			unless ($closed eq 'only') {
				die "Non-numeric parameter 'closed' passed that is not 'only'\n";
			}
		}
	}

	foreach my $bbox (@bboxes) {
		validate_bbox($bbox);
		my $bboxfinalurl = $bbox_url . $bbox . $limitstring . $closedstring;
		$parsed_note_json = decode_json(get($bboxfinalurl));
		if ($parsed_note_json->{type} ne 'FeatureCollection') {
			die "ERROR: Incoming JSON type not 'FeatureCollection', stopping\n";
		}
		# both direct bbox and topleft/lowerright will end up here
		# they both could have hit the specified or osm default limit - check it here and warn user if so
		# we don't guard against getting more notes than expected - should we ?
		my $received_note_count = scalar(@{$parsed_note_json->{features}});
		if ($limit) {
			if ($received_note_count == $limit) {
				print STDERR "WARNING: received a limit of $limit issues - some issues probably not downloaded\n";
			}
		}
		else {
			if ($received_note_count == $osmlimit) {
				print STDERR "WARNING: received a limit of the default $osmlimit issues - some issues probably not downloaded\n";
			}
		}
		foreach my $note (@{$parsed_note_json->{features}}) {
			my $osmnote = parse_note($note);
			unless ($closed eq 'only' and $osmnote->{status} eq 'open') {
				add_waypoint($osmnote, $final_gpx, $gpxroot);
			}
		}
	}

	$gpxroot = $final_gpx->addChild($gpxroot);
	print $final_gpx->toString(1);
}
