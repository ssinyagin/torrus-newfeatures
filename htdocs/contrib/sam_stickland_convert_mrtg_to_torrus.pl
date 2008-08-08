#!/usr/bin/perl -w

use strict;
use RRDs;
use Math::BigFloat only => 'GMP,Pari';
# NB: Within this script there are many places where we modify the BigFloat's in
# place where it's not appropiate. This is on purpose - the BigFloat copy operations
# can get very expensive so we reuse them where possible
use Math::Round;
use Term::ProgressBar;
use Switch;
use XML::LibXML;
use IO::Handle;
use List::Util qw[min max];

# Define the location of rrdtool (used for rrdtool dump), and the location
# of a couple tempory files
my $rrdtool = "/usr/local/bin/rrdtool";
my $tmpxml_fn = "/tmp/tmp-rrd.xml.$$";

## Comment out the following block to use this as a rough-and-ready module
## START STANDALONE
	my $usage = "Usage: convert-to-torrus.pl mrtg.rrd torrus.rrd out.rrd";
	
	my ( $mrtgrrd, $torrusrrd, $rrdout ) = ( $ARGV[0], $ARGV[1],  $ARGV[2] );

	die "$usage\n"
		if $#ARGV != 2;
	die "ERROR: Could not find input files.\n$usage\n"
		unless $mrtgrrd and -e $mrtgrrd and $torrusrrd and -e $torrusrrd; 
	die "ERROR: Output file '$rrdout' already exists.\n$usage\n"
		if -e $rrdout;
		
	sub convert_mrtg( $$$ );
	
	convert_mrtg( $mrtgrrd, $torrusrrd, $rrdout );
## END STANDALONE

## Retrieve baisc info concerning DS names and RRAs from the output of RRDs::info
sub getBasicInfo($)
{
	my $rrdinfo = shift @_;
	my (@data_rras, @ds_names);
	
	foreach my $prop (sort keys %$rrdinfo)
	{
		my $propval = $$rrdinfo{$prop};
	 
		if( $prop =~ /^ds\[(\S+)\]\.type/ )
		{
			push( @ds_names, $1 );
		}
		elsif( $prop =~ /^rra\[(\d+)\]\.(\S+)/ )
		{
			my $rranum = $1;
			my $rraprop = $2;
	
			if( $rraprop eq 'cf' )
			{
				if( grep {$propval eq $_} qw(AVERAGE MIN MAX LAST) )
				{
					push( @data_rras, $rranum );
				}
				elsif( grep {$propval eq $_} qw(HWPREDICT SEASONAL DEVSEASONAL
																				DEVPREDICT FAILURES) )
				{
					die "Holts Winters not yet supported";
				}
			}
		}
	}
	return (\@ds_names, \@data_rras);
}

## Define the data sources
sub defineDataSources($$)
{
	my ( $rrdinfo, $ds_names ) = @_;
	
	my @DS;
  
	foreach my $ds_name ( @$ds_names )
	{
		my $type = $$rrdinfo{'ds['.$ds_name.'].type'};
		my $args = '';
	 
		if( grep {$type eq $_} qw(GAUGE COUNTER DERIVE ABSOLUTE) )
		{
			my $min = $$rrdinfo{"ds[$ds_name].min"};
			$min = 'U' unless $min ne "";
	    
			my $max = $$rrdinfo{"ds[$ds_name.'].max"};
		  $max = 'U' unless defined($max);
	    
			$args = sprintf( '%s:%s:%s',
											 $$rrdinfo{"ds[$ds_name].minimal_heartbeat"},
											 $min, $max );
		}
		elsif( $type eq 'COMPUTE' )
		{
			$args = $$rrdinfo{'ds['.$ds_name.'].cdef'};
		}
		else
		{
			die("Unknown DS type: $type");
		}
	  
		push( @DS, sprintf( 'DS:%s:%s:%s', $ds_name, $type, $args ) );
	}
	return \@DS;
}

## Define the RRAs
sub defineRRAs($$)
{
	my ($rrdinfo, $data_rras) = @_;
	
	my @RRA;
	foreach my $rranum ( @$data_rras )
	{
		push( @RRA, sprintf('RRA:%s:%e:%d:%d',
											 $$rrdinfo{'rra['.$rranum.'].cf'},
											 $$rrdinfo{'rra['.$rranum.'].xff'},
											 $$rrdinfo{'rra['.$rranum.'].pdp_per_row'},
											 $$rrdinfo{'rra['.$rranum.'].rows'} ) );
	}
	
	return \@RRA;
}

## Collect the data from the MRTG style RRD file
## NB: This routine fetches the data via text matching, not processing the XML!
## If the output formatting of "rrdtool dump" changes this will break.
sub collectData($)
{
	my $mrtgrrd = shift @_;

	# RRDs::dump will fork and then print the output to stderr so it's difficult to capture that way
	# so we execute the command instead
	my $mrtg_dump_all = `$rrdtool dump $mrtgrrd`;
	my @mrtg_lines = split /\n/, $mrtg_dump_all;

	my ( %avg300, %avg1800, %max1800, %avg7200, %max300, %max7200, %avg86400, %max86400 );

	my $ref;
	my $mode = "AVG";
	foreach my $line (@mrtg_lines)
	{
		$mode = "MAX" if $line =~ m/MAX/; 
		
		# <!-- 2008-06-30 11:00:00 BST / 1214820000 --> <row><v> 6.4647904169e+03 </v><v> 5.9551718242e+04 </v></row>
		if( $line =~ m/<pdp_per_row> \d+ <\/pdp_per_row> <!-- (\d+) seconds -->/ )
		{
			my $step = $1;

			if($step == 300) { if ($mode eq "AVG") {$ref = \%avg300 } else {$ref = \%max300} }
			elsif($step == 1800) { if ($mode eq "AVG") {$ref = \%avg1800 } else {$ref = \%max1800} }
			elsif($step == 7200) { if ($mode eq "AVG") {$ref = \%avg7200 } else {$ref = \%max7200} }
			elsif($step == 86400) { if ($mode eq "AVG") {$ref = \%avg86400 } else {$ref = \%max86400} }
			else
			{
				die "Unsupported step value $step\n";
			}
		}
		
		if($line =~ m/<!-- \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \w+ \/ (\d+) --> <row><v> (.*) <\/v><v> (.*) <\/v><\/row>/)
		{
			my ( $timestamp, $in, $out ) = ( $1, $2, $3 );

			if( $in ne "NaN" && $out ne "NaN" )
			{
				my $in_bf = Math::BigFloat->new( $in );
				my $out_bf = Math::BigFloat->new( $out );			
				$ref->{$timestamp} = [ $in_bf, $out_bf ];
			}
		}
	}

	return (\%avg300, \%avg1800, \%max1800, \%avg7200, \%max300, \%max7200, \%avg86400, \%max86400);
}

## Takes a series of average and maximum values, and then regenerates a series of
## samples 300 seconds apart, such that the same average and maximum values will
## be recalculated by RRDtool for the given period
sub generateExtrapolatedEntries($$$$)
{
	my ( $all_samples, $avg_ref, $max_ref, $period ) = @_;
	
	my $earliest = ( sort( keys( %$all_samples ) ) )[0];
	my %new_samples;
	
	my $progress = Term::ProgressBar->new({name	 => "Processing " . scalar keys(%$avg_ref) . " $period sec samples",
																				 count => scalar keys(%$avg_ref),
																				 ETA	 => 'linear', });
	$progress->minor( 0 );
	my ($i, $next_update) = (0, 0);
	
	my $started = 0;
	foreach my $time (sort (keys( %$avg_ref ) ) )
	{
	  # Start at first sample after midnight
		if( !$started )
		{
			my @time_parts = gmtime( $time );
			$started = 1 if( $time_parts[1] == 0 && $time_parts[2] == 0);
			next;
		}
		
		last if( $time > $earliest );
		
		my ($avg_in, $avg_out, $max_in, $max_out) = ( $avg_ref->{$time}->[0],
																								  $avg_ref->{$time}->[1],
																								  $max_ref->{$time}->[0],
																								  $max_ref->{$time}->[1] );
		
		my ($faked_avg_in, $faked_avg_out, $samples_in, $samples_out);
		
		# Peak/Avg = Minimum number of samples that does not cause negative faked averages
		if( $avg_in == 0 || $max_in == 0 )
		{
			$faked_avg_in = Math::BigFloat->new( 0 );
			$samples_in = 0;
		}
		else
		{
			$samples_in = Math::BigFloat->new($max_in)->bdiv($avg_in)->bceil();
		}
		
		if($avg_out == 0 || $max_out == 0)
		{
			$faked_avg_out = Math::BigFloat->new( 0 );
			$samples_out = 0;
		}
		else
		{
			$samples_out = Math::BigFloat->new($max_out)->bdiv($avg_out)->bceil();
		}
		
		my $num_samples = max( $samples_in, $samples_out, 10 );
		my $step = $period / $num_samples;
		
		# Formula is fakeAvg = ((avg_in * num_samples) - max_in) / (num_samples - 1)
		# These statements modify avg_in in place for speed
		$faked_avg_in = $avg_in->bmul($num_samples)->bsub($max_in)->bdiv($num_samples - 1)
			if( !defined( $faked_avg_out ) );
		
		$faked_avg_out = $avg_out->bmul($num_samples)->bsub($max_out)->bdiv($num_samples - 1)
			if( !defined( $faked_avg_out ) );
		
		# Pre-multiply by the step value
		$max_in->bmul( $step );
		$max_out->bmul( $step );
		$faked_avg_in->bmul( $step );
		$faked_avg_out->bmul( $step );
		
		# Insert the peak samples
		$new_samples{$time} = [ $max_in, $max_out ];
		
		# Now insert the faked average values 
		for( my $i = 1 ; $i < $num_samples ; $i++ )
		{
			my $faked_time = round( $time - ( $i * $step ) );
			$new_samples{$faked_time} = [ $faked_avg_in, $faked_avg_out ];
		}

		$i++;
		$next_update = $progress->update( $i ) if $i > $next_update;
	}
	$progress->update( scalar keys ( %{$avg_ref} ) );
	
	# Copy the data into the new array
	my $lastest = ( sort  { $b cmp $a } ( keys( %new_samples ) ) )[0];
	foreach my $time ( sort { $b cmp $a } ( keys( %{$all_samples} ) ) )
	{
		last if( $time < $earliest );
		$new_samples{$time} = $all_samples->{$time};
	}
	return \%new_samples;
}

## Changes the last_ds value in RRD XML tree, for two given DS's
sub updateLastDS( $$$$$ )
{
	my ( $root, $in_ds_name, $out_ds_name, $in_last_ds, $out_last_ds ) = @_;
	
	foreach my $ds ( $root->findnodes( 'ds' ) )
	{
		my $ds_name = $ds->findvalue( 'name' );
		if( $ds_name =~ m/$in_ds_name/ )
		{
			my $lastds_node = ( $ds->findnodes( 'last_ds' ) ) [0];
			$lastds_node->firstChild()->setData( $in_last_ds );
		}
		elsif( $ds_name =~ m/$out_ds_name/ )
		{
			my $lastds_node = ( $ds->findnodes( 'last_ds' ) ) [0];
			$lastds_node->firstChild()->setData( $out_last_ds );
		}
	}
}

sub writeXMLtoRRD($$)
{
	my ( $xmlroot, $rrdfile ) = @_;
	# Write the XML to a tempory file file and then restore it back into the
	# original RRD file
	my $newrrd_xml = $xmlroot->toString();
	
	open( TMPXML, ">$tmpxml_fn" )
		or die "Could not create temporary file $tmpxml_fn\n";
	print TMPXML $newrrd_xml;
	close( TMPXML );
	
	RRDs::restore( "-f", $tmpxml_fn, $rrdfile );

	unlink( $tmpxml_fn );

	my $ERR=RRDs::error;
	die "ERROR while creating $rrdfile: $ERR\n" if $ERR;	
}

sub convert_mrtg( $$$ )
{
	my ( $mrtgrrd, $torrusrrd, $rrdout ) = @_;

	die "ERROR: Could not find input files.\n"
		unless $mrtgrrd and -e $mrtgrrd and $torrusrrd and -e $torrusrrd;
	die "ERROR: Output file '$rrdout' already exists.\n"
		if -e $rrdout;

	print "Examining Torrus RRD file... ";
	my $torrusrrd_info = RRDs::info $torrusrrd;
	
	my ( $ds_names, $data_rras ) = getBasicInfo( $torrusrrd_info );
	my $DS = defineDataSources( $torrusrrd_info, $ds_names );
	my $RRA = defineRRAs( $torrusrrd_info, $data_rras );
	
	my $in_ds;
	my $out_ds;
	my $limit;
	# Determine which DS's we will populate
	if( defined $$torrusrrd_info{'ds[ifHCInOctets].type'} )
	{
		print "found 64 bit counters\n";
		$in_ds = "ifHCInOctets";
		$out_ds = "ifHCOutOctets";
		$limit = Math::BigFloat->new(2)->bpow(64);
	}
	elsif( defined $$torrusrrd_info{'ds[ifInOctets].type'} )
	{
		die " 32 bit counters not supported\n";
		# $in_ds = "ifInOctets";
		# $out_ds = "ifOutOctets";
		# $limit = Math::BigFloat->new(2)->bpow(32);
	}
	else
	{
		die "Could not find ifHCInOctets or ifInOctets in $torrusrrd\n";
	}
	
	# Now collect all the DSes for the create/clone operation for the fresh RRD file
	print "Collecting data from MRTG RRD...\n";
	my ($avg300, $avg1800,
			$max1800, $avg7200,
			$max300, $max7200,
			$avg86400, $max86400
		) = collectData( $mrtgrrd );
	
	my $all_samples = {};
	
	# Add in the most recent entries that have not yet been averaged
  my $started = 0;
	foreach my $time ( sort ( keys ( %{$avg300} ) ) )
	{
	  # Start at first sample after midnight
		if( !$started )
		{
			my @time_parts = gmtime( $time );
			$started = 1 if( $time_parts[1] == 0 && $time_parts[2] == 0);
			next;
		}
		
		my $avg_in = $avg300->{$time}->[0];
		my $avg_out = $avg300->{$time}->[1];
		$all_samples->{$time} = [ $avg_in->bmul( 300 ), $avg_out->bmul( 300 ) ];
	}
	
	print "Extrapolating data so peaks are preserved\n";
	# Because of the way we extrapolate the entries we must ensure that the ranges are not allowed to overlap
	# so we add the most detailed to the hash first
	$all_samples = generateExtrapolatedEntries( $all_samples, $avg1800, $max1800,
		1800 ); # 30 mins
	$all_samples = generateExtrapolatedEntries( $all_samples, $avg7200, $max7200,
		7200 ); # 2 hours
	$all_samples = generateExtrapolatedEntries( $all_samples, $avg86400, $max86400,
		86400 ); # 1 day

	# Calculate the start time, minus one samples worth of space
	my $start = ( ( sort keys( %{$all_samples} ) ) [0] ) - 300;
	print "Start time in MRTG file is " . gmtime($start) . "\n";
	
	# Grab the last DS values from the Torrus file (we re-insert these into the new RRD
	# file later)
	my $last_total_in =
		Math::BigFloat->new( $torrusrrd_info->{"ds[$in_ds].last_ds"} );
	my $last_total_out =
		Math::BigFloat->new( $torrusrrd_info->{"ds[$out_ds].last_ds"} );
	
	print "Last recorded SNMP counters in Torrus file: $last_total_in bytes in, $last_total_out bytes out\n";
	
	#######	 Create the new RRD file #######
	print "Creating new rrd file: $rrdout\n";
	my @cmdarg = ( '--start=' . $start,
								 '--step=' . $$torrusrrd_info{'step'},
								 @$DS, @$RRA );
	RRDs::create( $rrdout, @cmdarg );
	
	my $ERR=RRDs::error;
	die "ERROR while creating $rrdout: $ERR\n" if $ERR;
	
	# Tune down the heartbeat values to allow sparser samples to be added
	RRDs::tune( $rrdout, "-h", "$in_ds:86400", "-h", "$out_ds:86400" );
	
	my $totalIn = Math::BigFloat->new( 0 );
	my $totalOut = Math::BigFloat->new( 0 );
	
	my $progress = Term::ProgressBar->new(
		{ name	 => "Updating RRD (" . scalar keys( %{$all_samples} ) .
							" data points to add)",
			count => scalar keys( %{$all_samples} ),
		  ETA	 => 'linear' } );
	$progress->minor( 0 );
	
	my ( $i, $next_update ) = ( 0, 0 );
	my $errors = "";
	
	foreach my $time ( sort ( keys( %{$all_samples} ) ) )
	{   
		$totalIn->badd( $all_samples->{$time}->[0] );
		$totalOut->badd( $all_samples->{$time}->[1] );
		
		# Fake SNMP counter wraps
		if( $totalIn > $limit )
		{
			print "In wrapped!\n";
			$totalIn->bsub( $limit );
		}
		
    if( $totalOut > $limit )
		{
			 print "Out wrapped!\n";
			 $totalOut->bsub( $limit );
		}
		
		@cmdarg = ("--template",
							 "$in_ds:$out_ds",
							 "$time\@" . $totalIn->bfloor() . ":" . $totalOut->bfloor());
		RRDs::update( $rrdout, @cmdarg );
		# I often seem to collect some errors relating to daylight savings periods,
		# but since I am using timestamps I don't understand why. These are harmless
		# for my purpose, so I collect then, but don't stop on them.
		$ERR=RRDs::error;
		$errors .= "ERROR while updating $rrdout: $ERR\n" if $ERR;
		# print "ERROR while updating $rrdout: $ERR\n" if $ERR;
	
		$i++;
		$next_update = $progress->update( $i ) if $i > $next_update;
	}
	
	$progress->update( scalar keys( %{$all_samples} ) );
	
	print "The following errors were encountered when updating the file\n$errors" if $errors ne "";
	
	# Reset the minimal heartbeat values back to their normal values
	RRDs::tune( $rrdout, "-h",
							"$in_ds:" . $$torrusrrd_info{'ds['.$in_ds.'].minimal_heartbeat'},
							"$out_ds:" . $$torrusrrd_info{'ds['.$out_ds.'].minimal_heartbeat'});
	
	print "Extracting new RRD file to insert correct \"last ds\" values...\n";
	# Only need to change a couple of values, so we do this properly using LibXML
	my $parser = XML::LibXML->new();

	my $rrd_xml = `$rrdtool dump $rrdout`;
	my $tree = $parser->parse_string( $rrd_xml );
	my $root = $tree->getDocumentElement;
	
	updateLastDS( $root, $in_ds, $out_ds, $last_total_in, $last_total_out );
	writeXMLtoRRD( $root, $rrdout );
	
	print "Done.\n";
}
