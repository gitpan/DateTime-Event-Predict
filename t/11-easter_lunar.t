#!perl

#use Test::More tests => 4;
use Test::More skip_all => "DateTime::Event::Lunar takes too long";

use DateTime;
use DateTime::Event::Predict;
use DateTime::Event::Predict::Profile;

BEGIN {
	eval { use DateTime::Event::Lunar qw (:phases); };
		
	skip_all => "DateTime::Event::Lunar required" if $@;
	
	skip_all => "Couldn't import from DateTime::Event::Lunar" if (FULL_MOON != 180);
};

my @easter_dates = qw(
	3/30/1975
	4/18/1976
	4/10/1977
	3/26/1978
	4/15/1979
	4/6/1980
	4/19/1981
	4/11/1982
	4/3/1983
	4/22/1984
	4/7/1985
	3/30/1986
	4/19/1987
	4/3/1988
	3/26/1989
	4/15/1990
	3/31/1991
	4/19/1992
	4/11/1993
	4/3/1994
	4/16/1995
	4/7/1996
	3/30/1997
	4/12/1998
	4/4/1999
	4/23/2000
	4/15/2001
	3/31/2002
	4/20/2003
	4/11/2004
	3/27/2005
	4/16/2006
	4/8/2007
	3/23/2008
	4/12/2009
);

my $dtp = new DateTime::Event::Predict(
	profile => {
		distinct_buckets => [qw/ day_of_year day_of_week /],
	},
);

foreach my $date (@easter_dates) {
	my ($month, $day, $year) = split(m!/!, $date);
	
	my $dt = new DateTime(
		year  => $year,
		month => $month,
		day   => $day,
	);
	
	$dtp->add_date($dt);
}

#
# Test prediction for Easter with lunar cycle hooks, if module available
#
	
# Get the Vernal Equinox
my $vernal = DateTime->new( year => 2010, month => 3, day => 21 ); # March 21st

is($vernal->ymd, '2010-03-21', 'Got vernal equinox');

# Get the next full moon
my $full_moon = DateTime::Event::Lunar->lunar_phase_after(
	datetime => $vernal,
	phase    => FULL_MOON,
	on_or_after => 1
);

is($full_moon->ymd, '2010-03-30', 'Next full moon after vernal equinox is March 30th, 2010');

my $real_easter = $dtp->predict(
	callbacks => [
		# Return false if prediction is more than 7 days after the given full moon
		sub {
			my $p = shift;
			return ($p->delta_days($full_moon)->delta_days() > 7) ? 0 : 1;
		}
	]
);

ok(defined $real_easter, 'Got a prediction back for real easter');
is($real_easter->ymd, '2010-04-04', 'Predicted Easter with DateTime::Event::Lunar as: ' . $real_easter->ymd);