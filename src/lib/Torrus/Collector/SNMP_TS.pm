#  Copyright (C) 2018  Stanislav Sinyagin
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Stanislav Sinyagin <ssinyagin@k-open.com>

# Collector module for time series data in SNMP tables.
# Each row is indexed with a timestamp of a measurement, and we need to
# find the latest row before collecting the results.
# We use "reference OID" to retrieve the values of all available timestamps
# and find the latest one. Reference OID should be from the same SNMP table
# as the data OID.

package Torrus::Collector::SNMP_TS;

use strict;
use warnings;

use Torrus::Collector::SNMP_TS_Params;
use Torrus::ConfigTree;
use Torrus::Collector::SNMP;
use Torrus::Log;
use Net::SNMP qw(:snmp);


# Register the collector type
$Torrus::Collector::collectorTypes{'snmp-ts'} = 1;


# This is first executed per target

$Torrus::Collector::initTarget{'snmp-ts'} = \&initTarget;

sub initTarget
{
    my $collector = shift;
    my $token = shift;

    my $tref = $collector->tokenData( $token );
    my $cref = $collector->collectorData( 'snmp-ts' );

    $collector->registerDeleteCallback( $token, \&deleteTarget );

    my $hosthash =
        Torrus::Collector::SNMP::getHostHash( $collector, $token );
    if( not defined( $hosthash ) )
    {
        $collector->deleteTarget($token);
        return 0;
    }
    $tref->{'hosthash'} = $hosthash;

    return initTargetAttributes( $collector, $token );
}




sub initTargetAttributes
{
    my $collector = shift;
    my $token = shift;

    my $tref = $collector->tokenData($token);
    my $cref = $collector->collectorData('snmp-ts');
    my $hosthash = $tref->{'hosthash'};

    if( Torrus::Collector::SNMP::isHostDead( $collector, $hosthash ) )
    {
        return 0;
    }

    if( not Torrus::Collector::SNMP::checkUnreachableRetry
        ( $collector, $hosthash ) )
    {
        $cref->{'needsRemapping'}{$token} = 1;
        return 1;
    }

    my $oid = $collector->param($token, 'snmp-ts-column-oid');
    $oid = Torrus::Collector::SNMP::expandOidMappings
        ( $collector, $token, $hosthash, $oid );

    if( not $oid )
    {
        # we return OK status, to let the storage initiate
        $cref->{'needsRemapping'}{$token} = 1;
        return 1;
    }
    elsif( $oid eq 'notfound' )
    {
        return 0;
    }

    $cref->{'targets'}{$hosthash}{$oid}{$token} = 1;
    $cref->{'activehosts'}{$hosthash} = 1;

    $tref->{'oid'} = $oid;

    my $refoid = $collector->param($token, 'snmp-ts-ref-oid');
    if( not defined($cref->{'refoid_expanded'}{$hosthash}{$refoid}) )
    {
        my $orig_refoid = $refoid;
        $refoid = Torrus::Collector::SNMP::expandOidMappings
            ( $collector, $token, $hosthash, $refoid );

        if( not $refoid )
        {
            # we return OK status, to let the storage initiate
            $cref->{'needsRemapping'}{$token} = 1;
            return 1;
        }
        elsif( $oid eq 'notfound' )
        {
            return 0;
        }

        $cref->{'refoid_expanded'}{$hosthash}{$orig_refoid} = $refoid;
    }

    if( not defined($cref->{'refoid_scale'}{$hosthash}{$refoid}) )
    {
        my $scale = $collector->param($token, 'snmp-ts-unit-scale');
        $scale = 1 unless defined($scale);
        $cref->{'refoid_scale'}{$hosthash}{$refoid} = $scale;
    }

    $cref->{'token_refoid'}{$hosthash}{$token} = $refoid;
    $cref->{'refoid_token'}{$hosthash}{$refoid}{$token} = 1;
    $cref->{'oid_refoid'}{$hosthash}{$oid} = $refoid;

    $cref->{'oids_per_pdu'}{$hosthash} =
        $collector->param($token, 'snmp-oids-per-pdu');

    if( $collector->paramEnabled($token, 'snmp-ignore-mib-errors') )
    {
        $cref->{'ignoremiberrors'}{$hosthash}{$oid} = 1;
    }
    
    return 1;
}


# Main collector cycle

$Torrus::Collector::runCollector{'snmp-ts'} = \&runCollector;

sub runCollector
{
    my $collector = shift;
    my $cref = shift;

    $cref->{'refoid_outdated'} = {};
    $cref->{'prev_last_ts'} = $cref->{'last_ts'};
    $cref->{'last_ts'} = {};
    
    # representative token for each hosthash
    my %reptoken;

    # First, find the latest timestamp for every refoid
    my $maxsessions =
        $Torrus::Collector::SNMP::maxSessionsPerDispatcher;

    my @hosts = keys %{$cref->{'activehosts'}};

    while( scalar(@hosts) > 0 )
    {
        my @batch = ();
        while( (scalar(@batch) < $maxsessions) and scalar(@hosts) > 0 )
        {
            push( @batch, pop( @hosts ) );
        }

        my @sessions;

        foreach my $hosthash ( @batch )
        {
            my @refoids = sort keys %{$cref->{'refoid_token'}{$hosthash}};
            if( scalar( @refoids ) == 0 )
            {
                next;
            }

            # Find one representative token for the host
            my @reptokens = keys %{$cref->{'token_refoid'}{$hosthash}};
            if( scalar( @reptokens ) == 0 )
            {
                next;
            }
            my $reptoken = $reptoken{$hosthash} = $reptokens[0];

            my $session =
                Torrus::Collector::SNMP::openNonblockingSession
                ( $collector, $reptoken, $hosthash );

            if( not defined($session) )
            {
                next;
            }
            else
            {
                push( @sessions, $session );
            }

            $cref->{'refoid_tstamps'}{$hosthash} = {};
            $cref->{'refoid_collected_time'}{$hosthash} = {};

            foreach my $refoid ( @refoids )
            {
                my @arg = ( -baseoid => $refoid,
                            -callback => [\&refOidWalkCallback,
                                          $collector, $hosthash, $refoid] );

                if( $session->version() > 0 )
                {
                    my $maxrepetitions =
                        $collector->param($reptoken, 'snmp-maxrepetitions');
                    push( @arg, '-maxrepetitions',  $maxrepetitions );
                }

                $session->get_table(@arg);
            }
        }

        # retrieve all reference tables in the batch
        snmp_dispatcher();

        # process the timestamps
        foreach my $hosthash ( @batch )
        {
            foreach my $refoid (keys %{$cref->{'refoid_token'}{$hosthash}})
            {
                my $timestamps = $cref->{'refoid_tstamps'}{$hosthash}{$refoid};
                if( not defined($timestamps) )
                {
                    $cref->{'refoid_outdated'}{$hosthash}{$refoid} = 1;
                    next;
                }

                # latest goes first
                my @ts_sorted = sort {$b <=> $a} keys %{$timestamps};
                if( scalar(@ts_sorted) == 0 )
                {
                    $cref->{'refoid_outdated'}{$hosthash}{$refoid} = 1;
                    next;
                }

                my $ts = $ts_sorted[0];
                $cref->{'last_ts'}{$hosthash}{$refoid} = $ts;

                my $last_collected =
                    $cref->{'refoid_collected_time'}{$hosthash}{$refoid};

                my $prev_ts = $cref->{'prev_last_ts'}{$hosthash}{$refoid};
                if( defined($prev_ts) and $ts == $prev_ts )
                {
                    my $max_interval = $collector->period();
                    if( scalar(@ts_sorted) > 1 )
                    {
                        my $scale =
                            $cref->{'refoid_scale'}{$hosthash}{$refoid};
                        $max_interval = ($ts_sorted[0] - $ts_sorted[1])/$scale;
                    }

                    $max_interval *= 2; # tolerate one whole period

                    if( $last_collected -
                        $cref->{'prev_collected_time'}{$hosthash}{$refoid} >
                        $max_interval )
                    {
                        $cref->{'refoid_outdated'}{$hosthash}{$refoid} = 1;
                        next;
                    }
                }
                else
                {
                    $cref->{'prev_collected_time'}{$hosthash}{$refoid} =
                        $last_collected;
                }
            }

            foreach my $refoid (sort keys
                                %{$cref->{'refoid_outdated'}{$hosthash}})
            {
                Error("Outdited time series $refoid on $hosthash");
            }
        }

        # actual data collection
        @sessions = ();

        foreach my $hosthash ( @batch )
        {
            my @oids = sort keys %{$cref->{'targets'}{$hosthash}};
            my @collect_oids;
            my $pdu_tokens = {};

            foreach my $oid ( @oids )
            {
                my $refoid = $cref->{'oid_refoid'}{$hosthash}{$oid};
                next unless defined($refoid);

                next if $cref->{'refoid_outdated'}{$hosthash}{$refoid};

                my $ts = $cref->{'last_ts'}{$hosthash}{$refoid};
                my $collect_oid = $oid . '.' . $ts;
                push(@collect_oids, $collect_oid);

                foreach my $token
                    ( keys %{$cref->{'targets'}{$hosthash}{$oid}} )
                {
                    $pdu_tokens->{$collect_oid}{$token} = 1;
                }
            }

            next if scalar(@collect_oids) == 0;

            my $session =
                Torrus::Collector::SNMP::openNonblockingSession
                ( $collector, $reptoken{$hosthash}, $hosthash );

            if( not defined($session) )
            {
                next;
            }
            else
            {
                push( @sessions, $session );
            }

            my $oids_per_pdu = $cref->{'oids_per_pdu'}{$hosthash};

            my @pdu_oids = ();
            my $delay = 0;

            while( scalar(@collect_oids) > 0 )
            {
                my $oid = shift @collect_oids;
                push( @pdu_oids, $oid );

                if( scalar(@collect_oids) == 0 or
                    ( scalar(@pdu_oids) >= $oids_per_pdu ) )
                {
                    if( Torrus::Log::isDebug() )
                    {
                        Debug('Sending SNMP PDU to ' . $hosthash . ':');
                        foreach my $oid ( @pdu_oids )
                        {
                            Debug($oid);
                        }
                    }

                    my $result =
                        $session->
                        get_request( -delay => $delay,
                                     -callback =>
                                     [ \&collectDataCallback,
                                       $collector, $pdu_tokens, $hosthash ],
                                     -varbindlist => \@pdu_oids );
                    if( not defined $result )
                    {
                        Error("Cannot create SNMP request: " .
                              $session->error);
                    }
                    @pdu_oids = ();
                    $delay += 0.01;
                }
            }
        }

        snmp_dispatcher();
    }
}


sub refOidWalkCallback
{
    my $session = shift;
    my $collector = shift;
    my $hosthash = shift;
    my $refoid = shift;

    my $cref = $collector->collectorData('snmp-ts');

    my $result = $session->var_bind_list();
    if( defined $result )
    {
        $cref->{'refoid_collected_time'}{$hosthash}{$refoid} = time();

        my $preflen = length($refoid) + 1;
        while( my( $oid, $val ) = each %{$result} )
        {
            # timestamp is an integer at the end of OID
            my $ts = substr($oid, $preflen);
            $cref->{'refoid_tstamps'}{$hosthash}{$refoid}{$ts} = 1;
        }
    }
    else
    {
        Error("Error retrieving table $refoid from $hosthash: " .
              $session->error());
        $session->close();
        return undef;
    }
    return;
}



sub collectDataCallback
{
    my $session = shift;
    my $collector = shift;
    my $pdu_tokens = shift;
    my $hosthash = shift;

    my $cref = $collector->collectorData('snmp-ts');

    if( not defined( $session->var_bind_list() ) )
    {
        Error('SNMP Error for ' . $hosthash . ': ' . $session->error() .
              ' when retrieving ' . join(' ', sort keys %{$pdu_tokens}));

        return;
    }

    my $timestamp = time();

    while( my ($oid, $value) = each %{$session->var_bind_list()} )
    {
        # Debug("OID=$oid, VAL=$value");
        if( $value eq 'noSuchObject' or
            $value eq 'noSuchInstance' or
            $value eq 'endOfMibView' )
        {
            if( not $cref->{'ignoremiberrors'}{$hosthash}{$oid} )
            {
                Error("Error retrieving $oid from $hosthash: $value");
                    
                foreach my $token ( keys %{$pdu_tokens->{$oid}} )
                {
                    $collector->deleteTarget($token);
                }
            }
        }
        else
        {
            foreach my $token ( keys %{$pdu_tokens->{$oid}} )
            {
                $collector->setValue( $token, $value, $timestamp );
            }
        }
    }
    
    return;
}



    

# Execute this after the collector has finished

$Torrus::Collector::postProcess{'snmp-ts'} = \&postProcess;

sub postProcess
{
    my $collector = shift;
    my $cref = shift;

    # We use some SNMP collector internals
    my $scref = $collector->collectorData('snmp');

    my %remapping_hosts;

    foreach my $token ( keys %{$scref->{'needsRemapping'}},
                        keys %{$cref->{'needsRemapping'}} )
    {
        my $tref = $collector->tokenData( $token );
        my $hosthash = $tref->{'hosthash'};

        $remapping_hosts{$hosthash} = 1;
    }

    while(my ($hosthash, $dummy) = each %remapping_hosts )
    {
        foreach my $token (sort keys %{$cref->{'token_refoid'}{$hosthash}})
        {
            delete $cref->{'needsRemapping'}{$token};
            if( not initTargetAttributes( $collector, $token ) )
            {
                $collector->deleteTarget($token);
            }
        }
    }

    return;
}


# Callback executed by Collector

sub deleteTarget
{
    my $collector = shift;
    my $token = shift;

    my $cref = $collector->collectorData('snmp-ts');
    my $tref = $collector->tokenData($token);
    my $hosthash = $tref->{'hosthash'};
    
    my $refoid = $cref->{'token_refoid'}{$hosthash}{$token};
    my $oid = $tref->{'oid'};

    delete $cref->{'targets'}{$hosthash}{$oid}{$token};
    if( scalar(keys %{$cref->{'targets'}{$hosthash}{$oid}}) == 0 )
    {
        delete $cref->{'targets'}{$hosthash}{$oid};
        delete $cref->{'oid_refoid'}{$hosthash}{$oid};
    }
    
    delete $cref->{'token_refoid'}{$hosthash}{$token};
    delete $cref->{'refoid_token'}{$hosthash}{$refoid}{$token};

    if( scalar(keys %{$cref->{'refoid_token'}{$hosthash}{$refoid}}) == 0 )
    {
        delete $cref->{'refoid_token'}{$hosthash}{$refoid};
        delete $cref->{'refoid_scale'}{$hosthash}{$refoid};
    }
    
    if( scalar(keys %{$cref->{'targets'}{$hosthash}}) == 0 )
    {
        delete $cref->{'activehosts'}{$hosthash};
    }
    
    return;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
