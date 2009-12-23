#!perl

use Test::More tests => 3;

use DateTime;
use DateTime::Event::Predict;
use DateTime::Event::Predict::Profile;

my $dtp = DateTime::Event::Predict->new(
	profile => {
		distinct_buckets => [qw/ day_of_week /],
	},
);

# Add todays date
my $today = DateTime->today();
$dtp->add_date($today);

# Add the previous 14 days
for  (1 .. 14) {
	my $new_date = $today->clone->add(
		days => ($_ * -1)
	);
	
	$dtp->add_date($new_date);
}

$dtp->train();

# Make sure mean epoch interval interval is 1 day
is( $dtp->{mean_epoch_interval}, 86400, 'Mean epoch interval' );

# Predict the next date
my $predicted_date = $dtp->predict;

#use Data::Dumper; warn Dumper($dtp); exit;

ok(defined $predicted_date, 'Got a defined prediction back');

# Get tomorrow's date to test against
my $tomorrow = $today->clone->add( days => 1 );

is($predicted_date->ymd, $tomorrow->ymd, 'Predict tomorrow');
