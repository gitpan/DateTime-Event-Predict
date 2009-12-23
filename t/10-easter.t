#!perl

use Test::More tests => 2;

use DateTime;
use DateTime::Event::Predict;
use DateTime::Event::Predict::Profile;

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

#
# Test prediction for Easter with no hooks
#

my $dtp = new DateTime::Event::Predict(
	profile => {
		distinct_buckets => [qw/ day_of_year day_of_week /],
	},
);

#use Data::Dumper;
#warn Dumper($dtp); exit;

foreach my $date (@easter_dates) {
	my ($month, $day, $year) = split(m!/!, $date);
	
	my $dt = new DateTime(
		year  => $year,
		month => $month,
		day   => $day,
	);
	
	$dtp->add_date($dt);
}

my $easter = $dtp->predict(
	max_predictions => 10,
	stdev_limit => 2,
);

ok(defined $easter, 'Easter prediction defined?');
ok($easter->ymd eq '2010-04-11', 'Predicted ' . $easter->ymd . ' for easter with no callbacks, should be 2010-04-11');