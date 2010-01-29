#!perl

# Predict a date using callbacks

use Test::More skip_all => "Not yet implemented";

use DateTime;
use DateTime::Event::Predict;

my $dtp = DateTime::Event::Predict->new(
	profile => {
		distinct_buckets => [qw/ day_of_week /],
	},
);