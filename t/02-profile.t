#!perl

use Test::More tests => 15;

BEGIN { use_ok('DateTime::Event::Predict::Profile', qw(:buckets)) };

# Make sure bucket hashes exported correctly
ok(defined %DISTINCT_BUCKETS, 'Distinct buckets imported');
ok(defined %INTERVAL_BUCKETS, 'Interval buckets imported');

# Profile with preset profile name
$profile = new DateTime::Event::Predict::Profile( profile => 'default' );

isa_ok( $profile, 'DateTime::Event::Predict::Profile' );

my @buckets = $profile->buckets();

ok( @buckets, 'Buckets for preset profile are defined' );

# Profile with incorrect bucket name
TODO: {
	todo_skip "Make sure Profile fails properly with bad bucket name", 1;
	
	$profile = new DateTime::Event::Predict::Profile(
		distinct_buckets => ['years'],
	);
	
	isa_ok( $profile, 'DateTime::Event::Predict::Profile' );
};

isa_ok( $profile, 'DateTime::Event::Predict::Profile' );

# Profile with distinct buckets
$profile = new DateTime::Event::Predict::Profile(
	distinct_buckets => ['day_of_year', 'day_of_week', 'day_of_month'],
);

isa_ok( $profile, 'DateTime::Event::Predict::Profile' );

@buckets = $profile->buckets();

ok( @buckets, 'Buckets for custom profile with distinct buckets are defined' );


# Make sure we got the right number of buckets
is( scalar @buckets, 3, 'Right number of buckets' );

# Make sure we got the right buckets
subtest 'Correct buckets' => sub {
  	my %buckets_to_check = (
		'day_of_year'  => 0,
		'day_of_week'  => 0,
		'day_of_month' => 0,
	);
	
	my $tested = 0;
	foreach my $bucket (@buckets) {
		if (exists $buckets_to_check{ $bucket->name }) {
			pass('Bucket ' . $bucket->name . ' expected' );
			$buckets_to_check{ $bucket->name } = 1;
		}
		else {
			fail('Bucket ' . $bucket->name . ' not expected');
		}
		
		$tested++;
	}
	
	while (my ($bucketname, $found) = each %buckets_to_check) {
		is($found, 1, 'Bucket ' . $bucketname . ' was found in the profile');
	}
	
	done_testing( $tested + 3 );
};

# Profile with interval buckets
$profile = new DateTime::Event::Predict::Profile(
	interval_buckets => ['years'],
);

isa_ok( $profile, 'DateTime::Event::Predict::Profile' );

@buckets = $profile->buckets();

ok( @buckets, 'Buckets for custom profile with interval buckets are defined' );

# Both interval and distinct buckets
$profile = new DateTime::Event::Predict::Profile(
	distinct_buckets => ['day_of_year'],
	interval_buckets => ['years'],
);

isa_ok( $profile, 'DateTime::Event::Predict::Profile' );

@buckets = $profile->buckets();

ok( @buckets, 'Buckets for custom profile with both distinct and interval buckets are defined' );

# Make sure bad bucket names result in error