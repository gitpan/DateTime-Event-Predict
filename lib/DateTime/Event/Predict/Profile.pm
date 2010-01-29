
#==================================================================== -*-perl-*-
#
# DateTime::Event::Predict::Profile
#
# DESCRIPTION
#   Provides default profiles and mechanisms for creating custom profiles
#
# AUTHORS
#   Brian Hann
#
#===============================================================================

package DateTime::Event::Predict::Profile;

use Carp qw( croak confess );
use Params::Validate qw(:all);
use List::MoreUtils qw(uniq);

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(%DISTINCT_BUCKETS %INTERVAL_BUCKETS);
our %EXPORT_TAGS = (buckets => [qw(%DISTINCT_BUCKETS %INTERVAL_BUCKETS)]);


our %PROFILES = (
	default => {
		distinct_buckets => [
			'day_of_week',
			'day_of_month',
			'day_of_year',
		],
	},
	holiday => {
		distinct_buckets => [
			'day_of_year',
			'day_of_week',
		],
	},
	daily => {
		distinct_buckets => [
			'day_of_year'
		],
	},
);

our %DISTINCT_BUCKETS = (
	nanosecond => DateTime::Event::Predict::Profile::Bucket->new(
		name      => 'nanosecond',
		type      => 'distinct',
		accessor  => 'nanosecond',
		duration  => 'nanoseconds',
		trimmable => 1,
		order     => 1,
	),
	#microsecond => DateTime::Event::Predict::Profile::Bucket->new(
	#	name     => 'microsecond',
	#	accessor => 'microsecond',
	#	duration => 'microseconds',
	#	order    => 2,
	#),
	#millisecond => DateTime::Event::Predict::Profile::Bucket->new(
	#	name	 => 'millisecond',
	#	accessor => 'millisecond',
	#	duration => 'milliseconds',
	#	order    => 3,
	#),
    second => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'second',
    	type      => 'distinct',
    	accessor  => 'second',
    	duration  => 'seconds',
    	trimmable => 1,
    	order     => 4,
    ),
    #fractional_second => DateTime::Event::Predict::Profile::Bucket->new(
	#	accessor => 'fractional_second',
	#	order    => 5,
	#),
    minute => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'minute',
    	type      => 'distinct',
    	accessor  => 'minute',
    	duration  => 'minutes',
    	trimmable => 1,
    	order     => 6,
   	),
    hour => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'hour',
    	type      => 'distinct',
    	accessor  => 'hour',
    	duration  => 'hours',
    	trimmable => 1,
    	order     => 7,
    ),
    day_of_week => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'day_of_week',
    	type      => 'distinct',
    	accessor  => 'day_of_week',
    	duration  => 'days',
    	trimmable => 0,
    	order     => 8,
    ),
    day_of_month => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'day_of_month',
    	type      => 'distinct',
    	accessor  => 'day',
    	duration  => 'days',
    	trimmable => 1,
    	order     => 9,
    ),
    day_of_quarter => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'day_of_quarter',
    	type      => 'distinct',
    	accessor  => 'day_of_quarter',
    	duration  => 'days',
    	trimmable => 0,
    	order     => 10,
    ),
    weekday_of_month => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'weekday',
    	type      => 'distinct',
    	accessor  => 'weekday', #Returns a number from 1..5 indicating which week day of the month this is. For example, June 9, 2003 is the second Monday of the month, and so this method returns 2 for that day.
    	duration  => 'days',
    	trimmable => 0,
    	order     => 11,
    ),
    week_of_month => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'week_of_month',
    	type      => 'distinct',
    	accessor  => 'week_of_month',
    	duration  => 'weeks',
    	trimmable => 0,
    	order     => 12,
    ),
    day_of_year => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'day_of_year',
    	type      => 'distinct',
    	accessor  => 'day_of_year',
    	duration  => 'days',
    	trimmable => 0,
    	order     => 13,
    ),
    week_number => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'week_number',
    	type      => 'distinct',
    	accessor  => 'week_number',
    	duration  => 'weeks',
    	trimmable => 0,
    	order     => 14,
    ),
    month_of_year => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'month_of_year',
    	type      => 'distinct',
    	accessor  => 'month',
    	duration  => 'months',
    	trimmable => 1,
    	order     => 15,
    ),
    quarter_of_year => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'quarter_of_year',
    	type      => 'distinct',
    	accessor  => 'quarter',
    	duration  => 'quarters', #I don't think this duration exists
    	trimmable => 0,
    	order     => 16,
    ),
    year => DateTime::Event::Predict::Profile::Bucket->new(
    	name	  => 'year',
    	type      => 'distinct',
    	accessor  => 'year',
    	duration  => 'years', #I don't think this duration exists
    	trimmable => 0,
    	order     => 17,
    ),
);

#Aliases
$DISTINCT_BUCKETS{'second_of_minute'} = $DISTINCT_BUCKETS{'second'};
$DISTINCT_BUCKETS{'minute_of_hour'}   = $DISTINCT_BUCKETS{'minute'};
$DISTINCT_BUCKETS{'hour_of_day'}   	  = $DISTINCT_BUCKETS{'hour'};
$DISTINCT_BUCKETS{'day'}     		  = $DISTINCT_BUCKETS{'day_of_month'};
$DISTINCT_BUCKETS{'week_of_year'}     = $DISTINCT_BUCKETS{'week_number'};

#***We'll need an order of precedence here, so that when we find a difference in months we don't increment any of the differences smaller
#   than that (weeks, days). *OR do we want to increment the difference but leave the weight so small that it has a smaller effect? I can't see why that
#   would be useful

# Interval buckets
our %INTERVAL_BUCKETS = (
	nanoseconds => DateTime::Event::Predict::Profile::Bucket->new(
		name       => 'nanoseconds',
		type	   => 'interval',
		accessor   => 'nanoseconds', # Accessor in the DateTime::Duration object that we use to get the difference
		order      => 0,             # Order of precedence of this bucket (larger means it takes precedence)
    ),
    seconds => DateTime::Event::Predict::Profile::Bucket->new(
		name       => 'seconds',
		type	   => 'interval',
		accessor   => 'seconds',
		order      => 1,
    ),
	minutes => DateTime::Event::Predict::Profile::Bucket->new(
		name       => 'minutes',
		type	   => 'interval',
		accessor   => 'minutes',
		order      => 2,
    ),
    hours => DateTime::Event::Predict::Profile::Bucket->new(
    	name       => 'hours',
    	type	   => 'interval',
		accessor   => 'hours',
		order      => 3,
    ),
    days => DateTime::Event::Predict::Profile::Bucket->new(
    	name       => 'days',
    	type	   => 'interval',
		accessor   => 'days',
		order      => 4,
    ),
    weeks => DateTime::Event::Predict::Profile::Bucket->new(
    	name       => 'weeks',
    	type	   => 'interval',
		accessor   => 'weeks',
		order      => 5,
    ),
    months => DateTime::Event::Predict::Profile::Bucket->new(
    	name       => 'months',
    	type	   => 'interval',
		accessor   => 'months',
		order      => 6,
    ),
    years => DateTime::Event::Predict::Profile::Bucket->new(
    	name       => 'years',
    	type	   => 'interval',
		accessor   => 'years',
		order      => 7,
    ),
);

# Make a list of all the accessors so we can check for them 
our @distinct_bucket_accessors = map { $_->{accessor} } values %DISTINCT_BUCKETS;
our @interval_bucket_accessors = map { $_->{accessor} } values %INTERVAL_BUCKETS;

# Condense the accessors down to the unique values
our @all_accessors = uniq (@distinct_bucket_accessors, @interval_bucket_accessors);

#===============================================================================#

sub new {
    my $proto = shift;
    my %opts  = @_;
    
    validate(@_, {
    	profile          => { type => SCALAR,   optional => 1 }, # Preset profile alias
    	distinct_buckets => { type => ARRAYREF, optional => 1 }, # Custom distinct bucket definitions
    	interval_buckets => { type => ARRAYREF, optional => 1 }, # Custom interval bucket definitions
    });
    
    my $class = ref( $proto ) || $proto;
    
    my $self = {};
    
    $self->{buckets} = {};
    $self->{interval_buckets} = {};
    $self->{distinct_buckets} = {};
    
    # Make sure we either have a preset profile alias, or one of the bucket options set
    if ( $opts{'profile'} ) {
    	if ( exists $PROFILES{ $opts{'profile'} } ) {
    		$opts{'distinct_buckets'} = $PROFILES{ $opts{'profile'} }->{distinct_buckets};
    		$opts{'interval_buckets'} = $PROFILES{ $opts{'profile'} }->{interval_buckets};
    	}
    	else {
    		confess("Undefined profile: '" . $opts{profile} . "' provided");
    	}
    }
    elsif ( ! $opts{'distinct_buckets'} && ! $opts{'interval_buckets'}) {
    	confess("Must specify either a profile or a custom set of buckets");
    }
    
    # Insert a bucket object into the bucket lists for the specified distinct buckets
    foreach my $bucket_name (@{ $opts{'distinct_buckets'} }) {
		my $bucket = $DISTINCT_BUCKETS{ $bucket_name }->clone;
		
		# Put this bucket in the full bucket list and the distinct bucket list
		$self->{buckets}->{ $bucket_name } = $bucket;
		$self->{distinct_buckets}->{ $bucket_name } = $bucket;
	}
	
	# Insert a bucket object into the bucket lists for the specified interval buckets
	foreach my $bucket_name (@{ $opts{'interval_buckets'} }) {
		my $bucket = $INTERVAL_BUCKETS{ $bucket_name }->clone;
		
		# Put this bucket in the full bucket list and the interval bucket list
		$self->{buckets}->{ $bucket_name } = $bucket;
		$self->{interval_buckets}->{ $bucket_name } = $bucket;
	}
    
    bless($self, $class);
    
    return $self;
}

# Return a bucket by its name
sub bucket {
	my $self   = shift;
	my $bucket = shift;
	
	validate_pos(@_, { type => SCALAR, optional => 1 });
	
	if (! defined $self->{buckets}->{ $bucket } || ! $self->{buckets}->{ $bucket }) {
		return;
	}
	
	return $self->{buckets}->{ $bucket };
}

# Return either the full bucket list or a slice of the buckets according to a list of names
# sent in
sub buckets {
	my $self    = shift;
	my @buckets = @_;
	
	my @to_return = ();
	if (@buckets) {
		@to_return = @{ $self->{buckets} }{ @buckets };
	}
	else {
		@to_return = values %{$self->{buckets}};
	}
	
	return wantarray ? @to_return : \@to_return;
}

# Return either the full list of the distinct buckets or a slice of the buckets according to a list of names
# sent in
sub _distinct_buckets {
	my $self    = shift;
	my @buckets = @_;
	
	my @to_return = ();
	if (@buckets) {
		@to_return = @{ $self->{distinct_buckets} }{ @buckets };
	}
	else {
		@to_return = values %{$self->{distinct_buckets}};
	}
	
	return wantarray ? @to_return : \@to_return;
}

# Return either the full list of the interval buckets or a slice of the buckets according to a list of names
# sent in
sub _interval_buckets {
	my $self    = shift;
	my @buckets = @_;
	
	my @to_return = ();
	if (@buckets) {
		@to_return = @{ $self->{interval_buckets} }{ @buckets };
	}
	else {
		@to_return = values %{$self->{interval_buckets}};
	}
	
	return wantarray ? @to_return : \@to_return;
}

1;

package DateTime::Event::Predict::Profile::Bucket;

use Params::Validate qw(:all);
use Carp qw( croak confess );

sub new {
    my $proto = shift;
    my %opts  = @_;
    
    %opts = validate(@_, {
    	name      => { type => SCALAR },
    	type      => { type => SCALAR },
    	order     => { type => SCALAR }, 
    	accessor  => { type => SCALAR },
    	duration  => { type => SCALAR, optional => 1 }, # Interval buckets don't have durations
    	trimmable => { type => SCALAR, optional => 1 },
    	on        => { type => SCALAR, default  => 1 },
    });
    
    my $class = ref( $proto ) || $proto;
    
    #unless (exists $BUCKETS{ $opts{'name'} }) {
	#	confess("Undefined bucket: '" . $opts{'name'} . "' provided");
	#}
    
    my $self = \%opts;
    
    #$self->{bucket} = $BUCKETS{ $opts{'name'} };
	$self->{weight} = ""; #Not used yet
    
    bless($self, $class);
    
    return $self;
}

sub name {
	my $self = shift;
	
	return $self->{name};
}

sub type {
	my $self = shift;
	
	return $self->{type};
}

sub accessor {
	my $self = shift;
	
	return $self->{accessor};
}

sub order {
	my $self = shift;
	
	return $self->{order};
}

sub duration {
	my $self = shift;
	
	return $self->{duration};
}

sub trimmable {
	my $self = shift;
	
	return $self->{trimmable};
}

sub weight {
	my $self = shift;
	
	return $self->{weight};
}

#Get or set whether this bucket is on or not
sub on {
	my $self = shift;
	my ($on) = @_;
	
	if (defined $on) {
		$self->{on} = ($on) ? 1 : 0;
	}
	else {
		return ($self->{on}) ? 1 : 0;
	}
}

#Reverse of on()
sub off {
	my $self = shift;
	my ($off) = @_;
	
	if (defined $off) {
		$self->{on} = ($off) ? 0 : 1;
	}
	else {
		return ($self->{on}) ? 0 : 1;
	}
}

sub clone { bless { %{ $_[0] } }, ref $_[0] }

1;

__END__

=pod

=head1 NAME

DateTime::Event::Predict::Profile - Provides default profiles for use with DateTime::Event::Predict,
and mechanisms for making custom profiles.

=head1 SYNOPSIS

	use DateTime::Event::Predict::Profile;

	my $profile = new DateTime::Event::Predict::Profile(
		distinct_buckets => [qw/ day_of_month /],
	);

	$profile->bucket('day_of_month')->off(1);

=head1 METHODS

=head2 new

Constructor

	# Pre-made profile
	my $profile = DateTime::Event::Predict::Profile->new(
		profile => 'holiday'
	);

	# Custom profile with the buckets you want
	my $profile = DateTime::Event::Predict::Profile->new(
		distinct_buckets => ['year'],
		interval_buckets => ['years']
	);

	# Define profile when creating DTP object
	my $dtp = DateTime::Event::Predict::Profile->new(
		profile => {
			profile => 'holiday',
		},
	);

	my $dtp = DateTime::Event::Predict::Profile->new(
		profile => {
			distinct_buckets => ['month'],
		},
	);

A profile tells DTP how to make predictions, that is, which parts of dates to look at in gathering statistics about them. 

=head3 Buckets

A bucket, for lack of better name, is a collection of date-parts. Take any distinct part of a date, say the seconds, or
the hours, or the quarter of the year, or even whether it's a weekday or not. A bucket in DTP is way of gathering data
regarding any certain date part from the list of dates you supply to it. If you provide a profile that has the 'year'
bucket enabled, then for every date you supply DTP will make a note of the year of every supplied date and use the
statistics of how the years relate in order to make predictions. If the 'year' bucket is turned off then the year of
the supplied dates will be ignored! DTP only pays attention to the buckets you enable.

In addition to buckets that record distinct date parts like years and months, which we call "distinct buckets," there are
"interval buckets," or buckets that define how each date in the list of supplied dates relates to the date preceding and
following it. If you turn on the 'months' interval bucket, DTP will look at how many months there are in the interval
between each date and the date before and after it, then use that for predictions. For instance, if every date you supply
is exactly 3 months after the one before it, DTP won't make a prediction that isn't also exactly 3 months after the
latest date you supplied.

=head3 Available Buckets

	# Distinct buckets
	year
	quarter                  # Alias: quarter_of_year
	month                    # Alias: month_of_year
	week_number              # Alias: week_of_year (Weak of year, from 1..53)
	day_of_year
	week_of_month            
	weekday
	day_of_quarter
	day_of_month             # Alias: day
	day_of_week
	hour                     # Hour of day
	minute                   # Alias: minute_of_hour
	second                   # Alias: second_of_minute
	nanosecond               
	
	# Interval buckets
	years
	months
	weeks
	days
	hours
	minutes
	seconds
	nanoseconds
	
If you look closely you'll notice that these buckets are the same as the accessors to get information out of a
DateTime or a DateTime::Duration object. Well that's exactly what they are.

=head2 bucket

Arguments: $bucket_name

	# Retrieve bucket
	my $bucket = $profile->bucket('day_of_month');

	# Use bucket accessor methods
	$bucket->off(1);
	$profile->bucket('day_of_month')->off(1);

Return value: DateTime::Event::Predict::Bucket

Retrieve a bucket object by its name. If no bucket name is provided or the bucket is not currently enabled in the profile C<bucket()> will return undef.

=head2 buckets

Arguments: @bucket_names

	# All buckets
	my @buckets = $profile->buckets();

	# Some buckets
	my @buckets = $profile->buckets('day_of_month', 'year');
	
	foreach my $bucket (@buckets) {
		$bucket->on(0);
	}
	
Fetches back a list of buckets by their names. If no names are provided all buckets are returned.

=head1 BUCKET METHODS

Methods that you can use on profile buckets

=head2 on

Arguments: 1 | 0

Tell whether a bucket is enabled or not (on or off), or optionall turn the bucket on or off.

	# Is it on or off?
	if ( $bucket->on ) {
		print "It's on!";
	}
	
	# Turn it on
	$bucket->on(1);
	
	# Turn it off
	$bucket->on(0);
	
=head2 off

Arguments: 1 | 0

This is just an inversion of C<on()>.

	# Is it on or off?
	if ( $bucket->off ) {
		print "It's off!";
	}

	# Turn it off
	$bucket->off(1);
	
	# Turn it on
	$bucket->off(0);

=head1 AUTHOR

Brian Hann, C<< <brian.hann at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-datetime-event-predict at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DateTime-Event-Predict>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DateTime::Event::Predict


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=DateTime-Event-Predict>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/DateTime-Event-Predict>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/DateTime-Event-Predict>

=item * Search CPAN

L<http://search.cpan.org/dist/DateTime-Event-Predict/>

=back


=head1 COPYRIGHT & LICENSE

Copyright 2009 Brian Hann, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<DateTime::Event::Predict>, L<DateTime>

=cut
