
#==================================================================== -*-perl-*-
#
# DateTime::Event::Predict
#
# DESCRIPTION
#   Predict new dates from a set of dates
#
# AUTHORS
#   Brian Hann
#
#===============================================================================

package DateTime::Event::Predict;

use 5.006;

use strict;

use DateTime;
use Params::Validate qw(:all);
use Carp qw(carp croak confess);
use Scalar::Util;
use Data::Dumper;

use POSIX qw(ceil);

use DateTime::Event::Predict::Profile qw(:buckets);

our $VERSION = '0.01_03';


#===============================================================================#

sub new {
    my $proto = shift;
    
    my %opts = validate(@_, {
    	dates       => { type => ARRAYREF, optional => 1 },
    	profile     => { type => SCALAR | OBJECT | HASHREF, optional => 1 },
    	#stdev_limit => { type => SCALAR,          default  => 2 },
    });
    
    my $class = ref( $proto ) || $proto;
    my $self = { #Will need to allow for params passed to constructor
    	dates   		 => [],
    	distinct_buckets => {},
    	interval_buckets => {},
    	total_epoch_interval    => 0,
    	largest_epoch_interval  => 0,
    	smallest_epoch_interval => 0,
    	mean_epoch_interval     => 0,
    	
    	#Whether this data set has been trained or not
    	trained => 0,
    };
    bless($self, $class);
    
    $opts{profile} = 'default' if ! $opts{profile};
    
    $self->profile( $opts{profile} );
    
    return $self;
}

# Get or set list of dates
# ***NOTE: Should make this validate for 'can' on the DateTime methods we need and on 'isa' for DateTime
sub dates {
	my $self   = shift;
	my ($dates) = @_;
	
	validate_pos(@_, { type => ARRAYREF, optional => 1 });
	
	if (! defined $dates) {
		return wantarray ? @{$self->{dates}} : $self->{dates};
	}
	elsif (defined $dates) {
		foreach my $date (@$dates) {
			$self->_trim_date( $date );
			$self->add_date($date);
		}
	}
	
	return 1;
}

# Add a date to the list of dates
sub add_date {
	my $self   = shift;
	my ($date) = @_;
	
	validate_pos(@_, { isa => 'DateTime' }); #***Or we could attempt to parse the date, or use can( epoch() );
	
	$self->_trim_date( $date );
	
	push(@{ $self->{dates} }, $date);
	
	return 1;
}

#Get or set the profile for this predictor
sub profile {
	my $self      = shift;
	my ($profile) = @_; # $profile can be a string specifying a profile name that is provided by default, or a profile object, or options to create a new profile
	
	validate_pos(@_, { type => SCALAR | OBJECT | HASHREF, optional => 1 });
	
	# If no profile is provided, return the current profile
	if (! defined $profile || ! $profile) { return $self->{profile}; }
	
	my $new_profile;
	
	# Profile is an actual DTP::Profile object
	if (Scalar::Util::blessed($profile) && $profile->can('buckets')) {
		$new_profile = $profile;
	}
	# Profile is a hashref of options to create a new DTP::Profile object with
	elsif (ref($profile) eq 'HASH') {
		$new_profile = DateTime::Event::Predict::Profile->new(
			%$profile,
		);
	}
	# Profile is the name of a profile alias
	else {
		$new_profile = DateTime::Event::Predict::Profile->new( profile => $profile );
	}
	
	# Add the distinct buckets
    foreach my $bucket ( $new_profile->_distinct_buckets() ) {
    	$self->{distinct_buckets}->{ $bucket->name } = {
    		accessor => $bucket->accessor,
    		duration => $bucket->duration,
    		order    => $bucket->order,
    		weight   => $bucket->weight,
    		buckets  => {},
    	};
    }
    
    # Add the interval buckets
    foreach my $bucket ( $new_profile->_interval_buckets() ) {
    	$self->{interval_buckets}->{ $bucket->name } = {
    		accessor => $bucket->accessor,
    		order    => $bucket->order,
    		weight   => $bucket->weight,
    		buckets  => {},
    	};
    }
	
	$self->{profile} = $new_profile;
	
	return 1;
}

# Gather statistics about the dates
sub train {
	my $self = shift;
	
	# Sort the dates chronologically
	my @dates = sort { $a->hires_epoch() <=> $b->hires_epoch() } @{ $self->{dates} }; #*** Need to convert this to DateTime->compare($dt1, $dt2)
	
	# Last and first dates
	$self->{last_date} = $dates[$#dates];
	$self->{first_date} = $dates[0];
	
	# Clear out anything already in the the buckets
	foreach my $bucket (values %{$self->{distinct_buckets}}, values %{$self->{interval_buckets}} ) {
		$bucket->{buckets} = {};
	}
	
	my $prev_date;
	foreach my $index (0 .. $#{ $self->{dates} }) {
		# The date to work on
		my $date = $dates[ $index ];
		
		# Get which dates were before and after the date we're working on
		my ($before, $after);
		if ($index > 0) { $before = $dates[ $index - 1 ]; }
		if ($index < $#{ $self->{dates} }) { $after = $dates[ $index + 1 ]; }
		
		# Increment the date-part buckets
		while (my ($name, $dbucket) = each %{ $self->{distinct_buckets} }) {
			# Get the accessor method by using can()
			my $cref = $date->can( $dbucket->{accessor} );
				croak "Can't call accessor '" . $dbucket->{accessor} . "' on " . ref($date) . " object" unless $cref;
				
			# Increment the number of instances for the value given when we use this bucket's accessor on $date
			$dbucket->{buckets}->{ &$cref($date) }++;
		}
		
		# If this is the first date we have nothing to diff, so we'll skip on to the next one
		if (! $prev_date) { $prev_date = $date; next; }
		
		# Get a DateTime::Duration object representing the diff between the dates
		my $dur = $date->subtract_datetime( $prev_date );
		
		# Increment the interval buckets
		# Intervals: here we default to the largest interval that we can see. So, for instance, if
		#   there is a difference of months we will not increment anything smaller than that.
		while (my ($name, $bucket) = each %{ $self->{interval_buckets} }) {
			my $cref = $dur->can( $bucket->{accessor} );
				croak "Can't call accessor '" . $bucket->{accessor} . "' on " . ref($dur) . " object" unless $cref;
			my $interval = &$cref($dur);
			$bucket->{buckets}->{ $interval }++;
		}
		
		# Add the difference between dates in epoch seconds
		my $epoch_interval = $date->hires_epoch() - $prev_date->hires_epoch();
		
		### Epoch interval: $epoch_interval
		
		$self->{total_epoch_interval} += $epoch_interval;
		
		# Set the current date to this date
		$prev_date = $date;
	}
	
	# Average interval between dates in epoch seconds
	$self->{mean_epoch_interval} = $self->{total_epoch_interval} / (scalar @dates - 1); #Divide total interval by number of intervals
	
	# Mark this object as being trained
	$self->{trained}++;
}

sub predict {
	my $self = shift;
	
	my %opts = validate(@_, {
		max_predictions => { type => SCALAR,     optional => 1 }, # How many predictions to return
		stdev_limit     => { type => SCALAR,     default  => 2 }, # Number of standard deviations to search through, default to 2
		min_date		=> { isa  => 'DateTime', optional => 1 }, # If set, make no prediction before 'min_date'
		callbacks       => { type => ARRAYREF,   optional => 1 }, # Arrayref of coderefs to call when making predictions
	});
	
	# Force max predictions to one if we were called in scalar context
	if (! defined $opts{'max_predictions'}) {
		$opts{'max_predictions'} = 1 if ! wantarray;
	}
	
	# Train this set of dates if they're not already trained
	$self->train if ! $self->_is_trained;
	
	# Make a copy of the distinct and interval bucket hashes so we can mess with them
	my %distinct_buckets = %{ $self->{distinct_buckets} };
	my %interval_buckets = %{ $self->{interval_buckets} };
	
	# Figure the mean, variance, and standard deviation for each bucket
	foreach my $bucket (values %distinct_buckets, values %interval_buckets) {
		my ($mean, $variance, $stdev) = $self->_bucket_statistics($bucket);
		
		$bucket->{mean}     = $mean;
		$bucket->{variance} = $variance;
		$bucket->{stdev}    = $stdev;
	}
	
	# Get the most recent of the provided dates by sorting them by their epoch seconds
	my $most_recent_date = (sort { $b->hires_epoch() <=> $a->hires_epoch() } @{ $self->{dates} })[0];
	
	# Make a starting search date that has been moved ahead by the average interval beteween dates (in epoch seconds)
	my $duration = new DateTime::Duration(
		seconds => $self->{mean_epoch_interval}, # **Might need to round off hires second info here?
	);
	my $start_date = $most_recent_date + $duration;
	
	# A hash of predictions, dates are keyed by their hires_epoch() value
	my %predictions = ();
	
	# Start with using the distinct buckets to make predictions
	if (%distinct_buckets) {
		# Get a list of buckets after sorting the buckets from largest date part to smallest (i.e. year->month->day->hour ... microsecond, etc)
		my @distinct_bucket_keys = sort { $self->{distinct_buckets}->{ $b }->{order} <=> $self->{distinct_buckets}->{ $a }->{order} } keys %distinct_buckets;
		
		# Get the first bucket name 
		my $first_bucket_name = shift @distinct_bucket_keys;
		
		# Start recursively descending down into the various date parts, searching in each one
		$self->_date_descend_distinct(
			%opts,
			
			date        	 	 => $start_date,
			most_recent_date 	 => $most_recent_date,
			bucket_name 	 	 => $first_bucket_name,
			distinct_buckets 	 => \%distinct_buckets,
			distinct_bucket_keys => \@distinct_bucket_keys,
			predictions 	 	 => \%predictions,
		);
		
		# Now that we (hopefully) have some predictions, put them each through _interval_check to check
		# the predictiosn against the interval bucket statistics
		if (%interval_buckets) {
			while (my ($hires, $prediction) = each %predictions) {
				# Delete the date from the predictions hash if it's not good according to the interval statistics
				if (! $self->_interval_check( $prediction )) {
					delete $predictions{ $hires };
				}
			}
		}
	}
	# No distinct buckets, just interval buckets
	elsif (%interval_buckets) {
		# Get a list of buckets after sorting the buckets from largest interval to smallest (i.e. years->months->days->hours, etc)
		my @interval_bucket_keys = sort { $self->{interval_buckets}->{ $b }->{order} <=> $self->{interval_buckets}->{ $a }->{order} } keys %interval_buckets;
		
		# Get the first bucket name 
		my $first_bucket_name = shift @interval_bucket_keys;
		
		# Start recursively descending down into the date interval types, searching in each one
		$self->_date_descend_interval(
			%opts,
			
			date        	 	 => $start_date,
			most_recent_date 	 => $most_recent_date,
			bucket_name 	 	 => $first_bucket_name,
			interval_buckets 	 => \%interval_buckets,
			interval_bucket_keys => \@interval_bucket_keys,
			predictions 	 	 => \%predictions,
		);
	}
	# WTF, no buckets. That's bad!
	else {
		croak("No buckets supplied!");
	}
	
	# Sort the predictions by their total deviation
	my @predictions = sort { $a->{_dtp_deviation} <=> $b->{_dtp_deviation} } values %predictions;
	
	return wantarray ? @predictions : $predictions[0];
}

# Descend down into the distinct date parts, looking for predictions
sub _date_descend_distinct {
	my $self = shift;
	#my %opts = @_;
	
	# Validate the options
	my %opts = validate(@_, {
		date        	 	 => { isa => 'DateTime' },				 # The date to start searching in
		most_recent_date 	 => { isa => 'DateTime' },               # The most recent date of the dates provided
		bucket_name 	 	 => { type => SCALAR },					 # The bucket (date-part) to start searching in
		distinct_buckets 	 => { type => HASHREF },				 # A hashref of all buckets to use when looking for good predictions
		distinct_bucket_keys => { type => ARRAYREF },				 # A list of bucket names that we shift out of to get the next bucket to use
		stdev_limit 	 	 => { type => SCALAR },					 # The limit of how many standard deviations to search through
		predictions 	 	 => { type => HASHREF },				 # A hashref of predictions we find
		max_predictions  	 => { type => SCALAR,     optional => 1 }, # The maxmimum number of predictions to return (prevents overly long searches)
		min_date		 	 => { isa  => 'DateTime', optional => 1 }, # If set, make no prediction before 'min_date'
		callbacks 	     	 => { type => ARRAYREF,   optional => 1 }, # A list of custom coderefs that are called on each possible prediction
	});	
	
	# Copy the options over into simple scalars so it's easier on my eyes
	my $date 				 = delete $opts{'date'};        # Delete these ones out as we'll be overwriting them below
	my $bucket_name 		 = delete $opts{'bucket_name'};
	my $distinct_buckets 	 = $opts{'distinct_buckets'};
	my $distinct_bucket_keys = $opts{'distinct_bucket_keys'};
	my $stdev_limit 		 = $opts{'stdev_limit'};
	my $predictions 		 = $opts{'predictions'};
	my $max_predictions 	 = $opts{'max_predictions'};
	my $callbacks       	 = $opts{'callbacks'};
	
	# We've reached our max number of predictions, return
	return 1 if defined $max_predictions && (scalar keys %$predictions) >= $max_predictions;
	
	# Get the actual bucket hash for this bucket name
	my $bucket = $distinct_buckets->{ $bucket_name };
	
	# The search range is the standard deviation multiplied by the number of standard deviations to search through
	my $search_range = ceil( $bucket->{stdev} * $stdev_limit );
	
	#The next bucket to search down into
	my $next_bucket_name = "";
	if (scalar @$distinct_bucket_keys > 0) {
		$next_bucket_name = shift @$distinct_bucket_keys;
	}
	
	foreach my $search_inc ( 0 .. $search_range ) {
		# Make an inverted search increment so we can search backwards
		my $neg_search_inc = $search_inc * -1;
		
		# Put forwards and backwards in the searches
		my @searches = ($search_inc, $neg_search_inc);
		
		# Make sure we only search on 0 once (i.e. 0 * -1 == 0)
		@searches = (0) if $search_inc == 0;
		
		foreach my $increment (@searches) {
			# We've reached our max number of predictions, return
			return 1 if defined $max_predictions && (scalar keys %$predictions) >= $max_predictions;
			
			# Make a duration object using the accessor for this bucket
			my $duration_increment = new DateTime::Duration( $bucket->{duration} => $increment );
			
			# Get the new date
			my $new_date = $date + $duration_increment;
			
			# Trim the date down to just the date parts we care about
			$self->_trim_date( $new_date );
			
			# Skip this date if it's before or on the most recent date
			if (DateTime->compare( $new_date, $opts{'most_recent_date'} ) <= 0) { # New date is before the most recent one, or is same as most recent one
				next;
			}
			
			# Skip this date if the "min_date" option is set, and it's before or on that date
			if ($opts{'min_date'} && DateTime->compare($new_date, $opts{'min_date'}) <= 0) {
				next;
			}
			
			# If we have no more buckets to search into, determine if this date is a good prediction
			if (! $next_bucket_name) {
				if ($self->_distinct_check( %opts, date => $new_date )) {
					$predictions->{ $new_date->hires_epoch() } = $new_date;
				}
			}
			#If we're not at the smallest bucket, keep searching!
			else {
				$self->_date_descend_distinct(
					%opts,
					date        => $new_date,
					bucket_name => $next_bucket_name,
				);
			}
		}
	}
	
	return 1;
}

# Descend down into the date intervals, looking for predictions
sub _date_descend_interval {
	my $self = shift;
	
	# Validate the options
	my %opts = validate(@_, {
		date        	 	 => { isa => 'DateTime' },				 # The date to start searching in
		most_recent_date 	 => { isa => 'DateTime' },               # The most recent date of the dates provided
		bucket_name 	 	 => { type => SCALAR },					 # The bucket (date-part) to start searching in
		interval_buckets 	 => { type => HASHREF },				 # A hashref of all buckets to use when looking for good predictions
		interval_bucket_keys => { type => ARRAYREF },				 # A list of bucket names that we shift out of to get the next bucket to use
		stdev_limit 	 	 => { type => SCALAR },					 # The limit of how many standard deviations to search through
		predictions 	 	 => { type => HASHREF },				 # A hashref of predictions we find
		max_predictions  	 => { type => SCALAR,     optional => 1 }, # The maxmimum number of predictions to return (prevents overly long searches)
		min_date		 	 => { isa  => 'DateTime', optional => 1 }, # If set, make no prediction before 'min_date'
		callbacks 	     	 => { type => ARRAYREF,   optional => 1 }, # A list of custom coderefs that are called on each possible prediction
	});	
	
	# Copy the options over into simple scalars so it's easier on my eyes
	my $date 				 = delete $opts{'date'};        # Delete these ones out as we'll be overwriting them below
	my $bucket_name 		 = delete $opts{'bucket_name'};
	my $interval_buckets 	 = $opts{'interval_buckets'};
	my $interval_bucket_keys = $opts{'interval_bucket_keys'};
	my $stdev_limit 		 = $opts{'stdev_limit'};
	my $predictions 		 = $opts{'predictions'};
	my $max_predictions 	 = $opts{'max_predictions'};
	my $callbacks       	 = $opts{'callbacks'};
	
	# We've reached our max number of predictions, return
	return 1 if defined $max_predictions && (scalar keys %$predictions) >= $max_predictions;
	
	# Get the actual bucket hash for this bucket name
	my $bucket = $interval_buckets->{ $bucket_name };
	
	# The search range is the standard deviation multiplied by the number of standard deviations to search through
	my $search_range = ceil( $bucket->{stdev} * $stdev_limit );
	
	#The next bucket to search down into
	my $next_bucket_name = "";
	if (scalar @$interval_bucket_keys > 0) {
		$next_bucket_name = shift @$interval_bucket_keys;
	}
	
	foreach my $search_inc ( 0 .. $search_range ) {
		# Make an inverted search increment so we can search backwards
		my $neg_search_inc = $search_inc * -1;
		
		# Put forwards and backwards in the searches
		my @searches = ($search_inc, $neg_search_inc);
		
		# Make sure we only search on 0 once (i.e. 0 * -1 == 0)
		@searches = (0) if $search_inc == 0;
		
		foreach my $increment (@searches) {
			# We've reached our max number of predictions, return
			return 1 if defined $max_predictions && (scalar keys %$predictions) >= $max_predictions;
			
			# Make a duration object using the accessor for this bucket
			my $duration_increment = new DateTime::Duration( $bucket->{accessor} => $increment );
			
			# Get the new date
			my $new_date = $date + $duration_increment;
			
			# Trim the date down to just the date parts we care about
			$self->_trim_date( $new_date );
			
			# Skip this date if it's before or on the most recent date
			if (DateTime->compare( $new_date, $opts{'most_recent_date'} ) <= 0) { # New date is before the most recent one, or is same as most recent one
				next;
			}
			
			# Skip this date if the "min_date" option is set, and it's before or on that date
			if ($opts{'min_date'} && DateTime->compare($new_date, $opts{'min_date'}) <= 0) {
				next;
			}
			
			# If we have no more buckets to search into, determine if this date is a good prediction
			if (! $next_bucket_name) {
				if ($self->_interval_check( %opts, date => $new_date )) {
					$predictions->{ $new_date->hires_epoch() } = $new_date;
				}
			}
			#If we're not at the smallest bucket, keep searching!
			else {
				$self->_date_descend_interval(
					%opts,
					date        => $new_date,
					bucket_name => $next_bucket_name,
				);
			}
		}
	}
	
	return 1;
}

# Check to see if a given date is good according to the supplied distinct buckets by going through each bucket
# and comparing this date's deviation from that bucket's mean. If it is within the standard deviation for
# each bucket then consider it a good match.
sub _distinct_check {
	my $self = shift;
	
	# Temporarily allow extra options
	validation_options( allow_extra => 1 );
	my %opts = validate(@_, {
		date        	 	 => { isa => 'DateTime' },				   # The date to check
		distinct_buckets 	 => { type => HASHREF },				   # List of enabled buckets
		callbacks 	     	 => { type => ARRAYREF,   optional => 1 }, # A list of custom coderefs that are called on each possible prediction
	});
	validation_options( allow_extra => 0 );
	
	my $date             = $opts{'date'};
	my $distinct_buckets = $opts{'distinct_buckets'};
	my $callbacks        = $opts{'callbacks'};
	
	my $good = 1;
	my $date_deviation = 0;
	foreach my $bucket (values %$distinct_buckets) {
		# Get the value for this bucket's access for the $new_date
		my $cref = $date->can( $bucket->{accessor} );
		my $datepart_val = &$cref($date);
		
		# If the deviation of this datepart from the mean is within the standard deviation, 
		# this date ain't good.
		
		my $deviation = abs($datepart_val - $bucket->{mean});
		$date_deviation += $deviation;
		
		if ($deviation > $bucket->{stdev} )  {
			$good = 0;
			last;
		}
	}
	
	# All the dateparts were within their standard deviations, check for callbacks and push this date into the set of predictions
	if ($good == 1) {
		# Stick the date's total deviation into the object so it can be used for sorting in predict()
		$date->{_dtp_deviation} += $date_deviation;
		
		# Run each hook we were passed
		foreach my $callback (@$callbacks) {
			# If any hook returns false, this date is a no-go and we can stop processing it
			if (! &$callback($date)) {
				$good = 0;
				last;
			}
		}
		
		# If the date is still considered good, return true
		if ($good == 1) {
			return 1;
		}
		# Otherwise return false
		else {
			return 0;
		}
	}
}

# Check to see if a given date is good according to the supplied interval buckets by going through each bucket
# and comparing this date's deviation from that bucket's mean. If it is within the standard deviation for
# each bucket then consider it a good match.
sub _interval_check {
	my $self = shift;
	
	# Temporarily allow extra options
	validation_options( allow_extra => 1 );
	my %opts = validate(@_, {
		date        	 	 => { isa => 'DateTime' },				   # The date prediction to check
		most_recent_date 	 => { isa => 'DateTime' },                 # The most recent date of the dates provided
		interval_buckets 	 => { type => HASHREF },				   # List of enabled interval buckets
		callbacks 	     	 => { type => ARRAYREF,   optional => 1 }, # A list of custom coderefs that are called on each possible prediction
	});
	validation_options( allow_extra => 0 );
	
	my $date             = $opts{'date'};
	my $most_recent_date = $opts{'most_recent_date'};
	my $interval_buckets = $opts{'interval_buckets'};
	my $callbacks        = $opts{'callbacks'};
	
	# Flag specifying whether the predicted date is "good" (within the standard deviation) or not
	my $good = 1;
	
	# Total deviation of the predicted date from each of the bucket standard deviations
	my $date_deviation = 0;
	
	# Get a duration object for the span between the most recent date supplied and the predicted date
	my $dur = $date->subtract_datetime( $most_recent_date );
	
	foreach my $bucket (values %$interval_buckets) {
		my $cref = $dur->can( $bucket->{accessor} );
			croak "Can't call accessor '" . $bucket->{accessor} . "' on " . ref($dur) . " object" unless $cref;
		my $interval = &$cref($dur);
		
		my $deviation = abs($interval - $bucket->{mean});
		$date_deviation += $deviation;
		
		if ($deviation > $bucket->{stdev} )  {
			$good = 0;
			last;
		}
	}
	
	# All the dateparts were within their standard deviations, check for callbacks and push this date into the set of predictions
	if ($good == 1) {
		# Stick the date's total deviation into the object so it can be used for sorting in predict()
		$date->{_dtp_deviation} += $date_deviation;
		
		# Run each hook we were passed
		foreach my $callback (@$callbacks) {
			# If any hook returns false, this date is a no-go and we can stop processing it
			if (! &$callback($date)) {
				$good = 0;
				last;
			}
		}
		
		# If the date is still considered good, return true
		if ($good == 1) {
			return 1;
		}
		# Otherwise return false
		else {
			return 0;
		}
	}
}

# Get the mean, variance, and standard deviation for a bucket
sub _bucket_statistics {
	my $self   = shift;
	my $bucket = shift;
	
	my $total = 0;
	my $count = 0;
	while (my ($value, $occurances) = each %{ $bucket->{buckets} }) {
		# Gotta loop for each time the value has been found, incrementing the total by the value
		for (1 .. $occurances) {
			$total += $value;
			$count++;
		}
	}
	
	my $mean = $total / $count;
	
	# Get the variance
	my $total_variance = 0;
	while (my ($value, $occurances) = each %{ $bucket->{buckets} }) {
		# Gotta loop for each time the value has been found
		my $this_variance = ($value - $mean) ** 2;
		
		$total_variance += $this_variance * $occurances;
	}
	
	my $variance = $total_variance / $count;
	my $stdev = sqrt($variance);
	
	return ($mean, $variance, $stdev);
}

# Whether this instance has been trained by train() or not
sub _is_trained {
	my $self = shift;
	
	return ($self->{trained} > 0) ? 1 : 0;
}  

# Utility method to print out the dates added to this instance
sub _print_dates {
	my $self = shift;
	
	foreach my $date (sort { $a->hires_epoch() <=> $b->hires_epoch() } @{ $self->{dates} }) {
		print $date->mdy('/') . ' ' . $date->hms . "\n";
	}
}

# Trim the date parts that are smaller than the smallest one we care about. If we only care about
# the year, month, and day, and during the initial search create an offset date that has an hour
# or minute that is off from the most recent given date, then when we do a comparison to see if
# we're predicting a date we've already been given it's possible that we could have that same
# date, just with the hour and second set forward a bit.
sub _trim_dates {
	my $self    = shift;
	my (@dates) = @_;
	
	# Get the smallest bucket we have turned on
	my @buckets = (sort { $a->order <=> $b->order } grep { $_->on && $_->trimmable } $self->profile->buckets)[0];
	my $smallest_bucket = $buckets[0];
	
	return if ! defined $smallest_bucket || ! $smallest_bucket || ! @buckets;
	
	foreach my $date (@dates) {
		confess "Can't trim a non-DateTime value" unless $date->isa( 'DateTime' );
		
		#foreach my $bucket (grep { $_->trimmable && ($_->order < $smallest_bucket->order) } values %DateTime::Event::Predict::Profile::BUCKETS) {
		foreach my $bucket (grep { $_->order < $smallest_bucket->order } values %DISTINCT_BUCKETS) {
			# Clone the date so we don't modify anything we shouldn't
			$date->clone->truncate( to => $smallest_bucket->accessor );
		}
	}
}

# Useless syntactic sugar
sub _trim_date { return &_trim_dates(@_); }

1; # End of DateTime::Event::Predict
    
__END__
    
=pod
    
=head1 NAME

DateTime::Event::Predict - Predict new dates from a set of dates

=head1 SYNOPSIS

Given a set of dates this module will predict the next date or dates to follow.

  use DateTime::Event::Predict;

  my $dtp = DateTime::Event::Predict->new(
      profile => {
          buckets => ['day_of_week'],
      },
  );

  # Add today's date: 2009-12-17
  my $date = new DateTime->today();
  $dtp->add_date($date);

  # Add the previous 14 days
  for  (1 .. 14) {
      my $new_date = $date->clone->add(
          days => ($_ * -1),
      );

      $dtp->add_date($new_date);
  }

  # Predict the next date
  my $predicted_date = $dtp->predict;

  print $predicted_date->ymd;

  # 2009-12-18

Here we create a new C<DateTime> object with today's date (it being December 17th, 2009 currently). We
then use L<add_date|add_date> to add it onto the list of dates that C<DateTime::Event::Predict> (DTP)
will use to make the prediction.

Then we take the 14 previous days (December 16-2) and them on to same list one by one. This gives us a
good set to make a prediction out of.

Finally we call L<predict|predict> which returns a C<DateTime> object representing the date that DTP has
calculated will come next.

=head1 HOW IT WORKS

Predicting the future is not easy, as anyone except, perhaps, Nostradamus will tell you. Events can occur
with perplexing randomness and discerning any pattern in the noise is nigh unpossible.

However, if you have a set of data to work with that you know for certain contains some sort of
regularity, and you have enough information to discover that regularity, then making predictions from
that set can be possible. The main issue with our example above is the tuning we did with this sort
of information.

When you configure your instance of DTP, you will have to tell what sorts of date-parts to keep
track of so that it has a good way of making a prediction. Date-parts can be things like
"day of the week", "day of the year", "is a weekend day", "week on month", "month of year", differences
between dates counted by "week", or "month", etc. Dtpredict will collect these identifiers from all the
provided dates into "buckets" for processing later on.



=head1 EXAMPLES

=over 4

=item Predicting Easter

=item Predicting 

=back

=head1 METHODS

=head2 new

Constructor

	my $dtp = DateTime::Event::Predict->new();

=head2 dates

Arguments: none | \@dates

Return value: \@dates

Called with no argument this method will return an arrayref to the list of the dates currently in the instance.

Called with an arrayref to a list of L<DateTime|DateTime> objects (C<\@dates>) this method will set the dates for this instance to C<\@dates>.

=head2 add_date

Arguments: $date

Return value: 

Adds a date on to the list of dates in the instance, where C<$date> is a L<DateTime|DateTime> object.

=head2 profile

Arguments: $profile

Set the profile for which date-parts will be 

  # Pass in preset profile by its alias
  $dtp->profile( profile => 'default' );
  $dtp->profile( profile => 'holiday' );

  # Create a new profile
  my $profile = new DateTime::Event::Predict::Profile(
      buckets => [qw/ minute hour day_of_week day_of_month /],
  );

  $dtp->profile( profile => $profile );

=head3 Provided profiles

The following profiles are provided for use by-name:

=head2 predict

Arguments: %options

Return Value: $next_date | @next_dates

Predict the next date(s) from the dates supplied.

  my $predicted_date = $dtp->predict();
  
If list context C<predict> returns a list of all the predictions, sorted by their probability:

  my @predicted_dates = $dtp->predict();
  
The number of prediction can be limited with the C<max_predictions> option.
	
Possible options

  $dtp->predict(
      max_predictions => 4, # Once 4 predictions are found, return back
      callbacks => [
          sub { return ($_->second % 4) ? 0 : 1 } # Only predict dates with second values that are divisible by four.
      ],
  );
  
=over 4

=item max_predictions

Maximum number of predictions to find.

=item callbacks

Arrayref of subroutine callbacks. If any of them return a false value the date will not be returned as a prediction.

=back

=head2 train

Train this instance of DTP

=head1 TODO

=over 4

=item *

It would be be cool if you could pass your own buckets in with a certain type, so you could, say, look for recurrence based
on intervals of 6 seconds, or 18 days, whatever.

=item *

We need to be able to handle recording more than one interval per diff. If the dates are all offset from each other by 1 day 6 hours (May 1, 3:00; May 2, 6:00),
we can't be predicting a new date that's exactly 1 day after the most recent one.
  ^ The best way to do this is probably to record intervals as epoch seconds, so everything is taken into account. Maybe record epoch seconds in addition
    to whole regular intervals like days & hours.

=back
 
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

L<DateTime>, L<DateTime::Event::Predict::Profile>

=cut
