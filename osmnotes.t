use strict;
use warnings;

use Test::More;
use Test::Exception;

my @bboxes_valid = ('23.9131,56.8792,24.3938,57.0995', '-1.38,46.86,3.15,48.85', '15.05,-15.92,17.66,-13.5');
my @bboxes_invalid = ('1,2,3', '1,2,3,4,5', 'a,b,c,d');

require_ok('osmnotes.pl');

for my $valid_bbox (@bboxes_valid) {
	ok(App::OSMNotes::validate_bbox($valid_bbox));
}

for my $invalid_bbox (@bboxes_invalid) {
	dies_ok {
		App::OSMNotes::validate_bbox($invalid_bbox)
	};
}

done_testing();
