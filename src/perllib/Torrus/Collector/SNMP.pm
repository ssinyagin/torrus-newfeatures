#  Copyright (C) 2002  Stanislav Sinyagin
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
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>

package Torrus::Collector::SNMP;

use Torrus::Collector::SNMP_Params;
use Torrus::ConfigTree;
use Torrus::Log;

use strict;
use Net::hostent;
use Socket;
use Net::SNMP qw(:snmp);
use Math::BigInt;

# Register the collector type
$Torrus::Collector::collectorTypes{'snmp'} = 1;

# List of needed parameters and default values

$Torrus::Collector::params{'snmp'} = {
    'snmp-version'      => undef,
    'snmp-port'         => undef,
    'snmp-community'    => undef,
    'snmp-username'     => undef,
    'snmp-authkey'      => undef,
    'snmp-authpassword' => undef,
    'snmp-authprotocol' => 'md5',
    'snmp-privkey'      => undef,
    'snmp-privpassword' => undef,
    'snmp-privprotocol' => 'des',
    'snmp-timeout'      => undef,
    'snmp-retries'      => undef,
    'domain-name'       => undef,
    'snmp-host'         => undef,
    'snmp-object'       => undef,
    'snmp-oids-per-pdu' => undef,
    'snmp-object-type'  => 'OTHER',
    'snmp-check-sysuptime' => 'yes'
    };

my $sysUpTime = '1.3.6.1.2.1.1.3.0';

# This is first executed per target

$Torrus::Collector::initTarget{'snmp'} = \&Torrus::Collector::SNMP::initTarget;



sub initTarget
{
    my $collector = shift;
    my $token = shift;

    my $tref = $collector->tokenData( $token );
    my $cref = $collector->collectorData( 'snmp' );

    $collector->registerDeleteCallback
        ( $token, \&Torrus::Collector::SNMP::deleteTarget );

    my $ipaddr = getHostIpAddress( $collector, $token );
    if( not defined( $ipaddr ) )
    {
        $collector->deleteTarget($token);
        return 0;
    }

    $tref->{'ipaddr'} = $ipaddr;

    return Torrus::Collector::SNMP::initTargetAttributes( $collector, $token );
}


sub initTargetAttributes
{
    my $collector = shift;
    my $token = shift;

    my $tref = $collector->tokenData( $token );
    my $cref = $collector->collectorData( 'snmp' );

    my $ipaddr = $tref->{'ipaddr'};
    my $port = $collector->param($token, 'snmp-port');
    my $version = $collector->param($token, 'snmp-version');

    my $community;
    if( $version eq '1' or $version eq '2c' )
    {
        $community = $collector->param($token, 'snmp-community');
    }
    else
    {
        # We use community string to identify the agent.
        # For SNMPv3, it's the user name
        $community = $collector->param($token, 'snmp-username');
    }

    # If the object is defined as a map, retrieve the whole map
    # and cache it.

    if( isHostDead( $collector, $ipaddr, $port, $community ) )
    {
        return 0;
    }
        
    if( not checkUnreachableRetry( $collector, $ipaddr, $port, $community ) )
    {
        $cref->{'needsRemapping'}{$token} = 1;
        return 1;
    }
    
    my $oid = $collector->param($token, 'snmp-object');
    $oid = expandOidMappings( $collector, $token, $ipaddr, $port, $community,
                              $oid );

    if( not $oid )
    {
        if( $cref->{'unreachableHostDeleted'}{$ipaddr}{$port}{$community} )
        {
            # we tried our best, but the target is dead
            return 0;
        }
        else
        {
            # we return OK status, to let the storage initiate
            $cref->{'needsRemapping'}{$token} = 1;
            return 1;
        }
    }
    elsif( $oid eq 'notfound' )
    {
        return 0;
    }

    # Collector should be able to find the target
    # by host, port, community, and oid.
    # There can be several targets with the same host/port/community/oid set.

    $cref->{'targets'}{$ipaddr}{$port}{$community}{$oid}{$token} = 1;

    # One representative for each host:port:community triple.
    # I assume overridiing is faster than checking if it's already there
    $cref->{'reptoken'}{$ipaddr}{$port}{$community} = $token;

    $tref->{'oid'} = $oid;

    $cref->{'oids_per_pdu'}{$ipaddr}{$port}{$community} =
        $collector->param($token, 'snmp-oids-per-pdu');

    if( $collector->param($token, 'snmp-object-type') eq 'COUNTER64' )
    {
        $cref->{'64bit_oid'}{$oid} = 1;
    }

    if( $collector->param($token, 'snmp-check-sysuptime') eq 'no' )
    {
        $cref->{'nosysuptime'}{$ipaddr}{$port}{$community} = 1;
    }
    
    return 1;
}


sub getHostIpAddress
{
    my $collector = shift;
    my $token = shift;

    my $cref = $collector->collectorData( 'snmp' );

    my $hostname = $collector->param($token, 'snmp-host');
    my $domain = $collector->param($token, 'domain-name');
    if( $hostname !~ /\./o and length( $domain ) > 0 )
    {
        $hostname .= '.' . $domain;
    }

    my $ipaddr;
    if( $hostname =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/o )
    {
        $ipaddr = $hostname;
    }
    else
    {
        if( not defined( $cref->{'dnscache'}{$hostname} ) )
        {
            my $h = gethost($hostname);

            if( not $h )
            {
                Error("Cannot resolve $hostname in " .
                      $collector->path($token));
                $collector->deleteTarget($token);
                return undef;
            }

            # Save the resolved address
            $ipaddr = inet_ntoa( $h->addr() );
            $cref->{'dnscache'}{$hostname} = $ipaddr;
        }
        else
        {
            $ipaddr = $cref->{'dnscache'}{$hostname};
        }
    }

    return $ipaddr;
}


sub snmpSessionArgs
{
    my $collector = shift;
    my $token = shift;
    my $ipaddr = shift;
    my $port = shift;
    my $community = shift;

    my $version = $collector->param($token, 'snmp-version');
    my @ret = ( -hostname     => $ipaddr,
                -port         => $port,
                -timeout      => $collector->param($token, 'snmp-timeout'),
                -retries      => $collector->param($token, 'snmp-retries'),
                -version      => $version );

    if( $version eq '1' or $version eq '2c' )
    {
        push( @ret, '-community', $community );
    }
    else
    {
        push( @ret, -username, $community);

        foreach my $arg ( qw(-authkey -authpassword -authprotocol
                             -privkey -privpassword -privprotocol) )
        {
            if( defined( $collector->param($token, 'snmp' . $arg) ) )
            {
                push( @ret, $arg, $collector->param($token, 'snmp' . $arg) );
            }
        }
    }

    return @ret;
}
              


sub openBlockingSession
{
    my $collector = shift;
    my $token = shift;
    my $ipaddr = shift;
    my $port = shift;
    my $community = shift;

    my ($session, $error) =
        Net::SNMP->session( snmpSessionArgs( $collector, $token,
                                             $ipaddr, $port, $community ),
                            -nonblocking  => 0,
                            -translate    => ['-all', 0, '-octetstring', 1] );
    if( not defined($session) )
    {
        Error('Cannot create SNMP session for ' . $ipaddr . ': ' . $error);
    }

    return $session;
}

sub openNonblockingSession
{
    my $collector = shift;
    my $token = shift;
    my $ipaddr = shift;
    my $port = shift;
    my $community = shift;

    my ($session, $error) =
        Net::SNMP->session( snmpSessionArgs( $collector, $token,
                                             $ipaddr, $port, $community ),
                            -nonblocking  => 0x1,
                            -translate    => ['-timeticks' => 0] );
    if( not defined($session) )
    {
        Error('Cannot create SNMP session for ' . $ipaddr . ': ' . $error);
    }

    return $session;
}


sub expandOidMappings
{
    my $collector = shift;
    my $token = shift;
    my $ipaddr = shift;
    my $port = shift;
    my $community = shift;
    my $oid_in = shift;
        
    my $tref = $collector->tokenData( $token );
    my $cref = $collector->collectorData( 'snmp' );

    my $oid = $oid_in;

    # Process Map statements

    while( index( $oid, 'M(' ) >= 0 )
    {
        if( not $oid =~ /^(.*)M\(\s*([0-9\.]+)\s*,\s*([^\)]+)\)(.*)$/o )
        {
            Error("Error in OID mapping syntax: $oid");
            return undef;
        }

        my $head = $1;
        my $map = $2;
        my $key = $3;
        my $tail = $4;

        # Remove trailing space from key
        $key =~ s/\s+$//o;

        my $value =
            lookupMap( $collector, $token, $ipaddr, $port, $community,
                       $map, $key );

        if( defined( $value ) )
        {
            if( $value eq 'notfound' )
            {
                return 'notfound';
            }
            else
            {
                $oid = $head . $value . $tail;
            }
        }
        else
        {
            return undef;
        }
    }

    # process value lookups

    while( index( $oid, 'V(' ) >= 0 )
    {
        if( not $oid =~ /^(.*)V\(\s*([0-9\.]+)\s*\)(.*)$/o )
        {
            Error("Error in OID value lookup syntax: $oid");
            return undef;
        }

        my $head = $1;
        my $key = $2;
        my $tail = $4;

        my $value;

        if( not defined( $cref->{'value-lookups'}
                         {$ipaddr}{$port}{$community}{$key} ) )
        {
            # Retrieve the OID value from host

            my $session = openBlockingSession( $collector, $token,
                                               $ipaddr, $port, $community );
            if( not defined($session) )
            {
                return undef;
            }

            my $result = $session->get_request( -varbindlist => [$key] );
            $session->close();
            if( defined $result )
            {
                $value = $result->{$key};
                $cref->{'value-lookups'}{$ipaddr}{$port}{$community}{$key} =
                    $value;
            }
            else
            {
                Error("Error retrieving $key from $ipaddr: " .
                      $session->error());
                probablyDead( $collector, $ipaddr, $port, $community );
                return undef;
            }
        }
        else
        {
            $value =
                $cref->{'value-lookups'}{$ipaddr}{$port}{$community}{$key};
        }
        if( defined( $value ) )
        {
            $oid = $head . $value . $tail;
        }
        else
        {
            return 'notfound';
        }
    }

    # Debug("OID expanded: $oid_in -> $oid");
    return $oid;
}

# Look up table index in a map by value

sub lookupMap
{
    my $collector = shift;
    my $token = shift;
    my $ipaddr = shift;
    my $port = shift;
    my $community = shift;
    my $map = shift;
    my $key = shift;

    my $cref = $collector->collectorData( 'snmp' );

    if( not defined( $cref->{'maps'}{$ipaddr}{$port}{$community}{$map} ) )
    {
        # Retrieve map from host
        Debug("Retrieving map $map from $ipaddr");

        my $session = openBlockingSession( $collector, $token,
                                           $ipaddr, $port, $community );
        if( not defined($session) )
        {
            return undef;
        }

        # Retrieve the map table

        my $result = $session->get_table( -baseoid => $map );
        
        if( defined $result )
        {
            while( my( $val, $key ) = each %{$result} )
            {
                my $quoted = quotemeta( $map );
                $val =~ s/^$quoted\.//;
                $cref->{'maps'}{$ipaddr}{$port}{$community}{$map}{$key} =
                    $val;
                # Debug("Map $map discovered: '$key' -> '$val'");
            }
            $session->close();
        }
        else
        {
            Error("Error retrieving table $map from $ipaddr: " .
                  $session->error());
            $session->close();
            probablyDead( $collector, $ipaddr, $port, $community );
            return undef;
        }
    }

    my $value = $cref->{'maps'}{$ipaddr}{$port}{$community}{$map}{$key};
    if( not defined $value )
    {
        Error("Cannot find value $key in map $map for $ipaddr in ".
              $collector->path($token));
        if( defined ( $cref->{'maps'}{$ipaddr}{$port}{$community}{$map} ) )
        {
            Error("Current map follows");
            while( my($key, $val) = each
                   %{$cref->{'maps'}{$ipaddr}{$port}{$community}{$map}} )
            {
                Error("'$key' => '$val'");
            }
        }
        return 'notfound';
    }
    else
    {
        return $value;
    }    
}

# The target host is unreachable. We try to reach it few more times and
# give it the final diagnose.

sub probablyDead
{
    my $collector = shift;
    my $ipaddr = shift;
    my $port = shift;
    my $community = shift;

    my $cref = $collector->collectorData( 'snmp' );

    # Stop all collection for this host, until next initTargetAttributes
    # is successful
    delete $cref->{'reptoken'}{$ipaddr}{$port}{$community};

    my $probablyAlive = 1;

    if( defined( $cref->{'hostUnreachableSeen'}{$ipaddr}{$port}{$community} ) )
    {
        if( $Torrus::Collector::SNMP::unreachableTimeout > 0 and
            time() -
            $cref->{'hostUnreachableSeen'}{$ipaddr}{$port}{$community} >
            $Torrus::Collector::SNMP::unreachableTimeout )
        {
            $probablyAlive = 0;
        }
    }
    else
    {
        $cref->{'hostUnreachableSeen'}{$ipaddr}{$port}{$community} = time();
    }

    if( $probablyAlive )
    {
        Info('Target host is unreachable. Will try again later: ' .
             "$ipaddr:$port:$community");
    }
    else
    {
        # It is dead indeed. Delete all tokens associated with this host
        Info('Target host is unreachable during last ' .
             $Torrus::Collector::SNMP::unreachableTimeout .
             " seconds. Giving it up: $ipaddr:$port:$community");
        my @deleteTargets = ();
        while( my ($oid, $ref1) =
               each %{$cref->{'targets'}{$ipaddr}{$port}{$community}} )
        {
            while( my ($token, $dummy) = each %{$ref1} )
            {
                push( @deleteTargets, $token );
            }
        }
        
        Debug('Deleting ' . scalar( @deleteTargets ) . ' tokens');
        foreach my $token ( @deleteTargets )
        {
            $collector->deleteTarget($token);
        }
        
        delete $cref->{'reptoken'}{$ipaddr}{$port}{$community};
        delete $cref->{'hostUnreachableSeen'}{$ipaddr}{$port}{$community};
        delete $cref->{'hostUnreachableRetry'}{$ipaddr}{$port}{$community};
        $cref->{'unreachableHostDeleted'}{$ipaddr}{$port}{$community} = 1;
    }
    
    return $probablyAlive;
}

# Return false if the try is too early

sub checkUnreachableRetry
{
    my $collector = shift;
    my $ipaddr = shift;
    my $port = shift;
    my $community = shift;

    my $cref = $collector->collectorData( 'snmp' );

    my $ret = 1;
    if( exists( $cref->{'hostUnreachableSeen'}{$ipaddr}{$port}{$community} ) )
    {
        my $lastRetry = $cref->{'hostUnreachableRetry'}{
            $ipaddr}{$port}{$community};

        if( not defined( $lastRetry ) )
        {
            $lastRetry =
                $cref->{'hostUnreachableSeen'}{$ipaddr}{$port}{$community};
        }
            
        if( time() < $lastRetry +
            $Torrus::Collector::SNMP::unreachableRetryDelay )
        {
            $ret = 0;
        }
        else
        {
            $cref->{'hostUnreachableRetry'}{
                $ipaddr}{$port}{$community} = time();
        }            
    }
    
    return $ret;
}


sub isHostDead
{
    my $collector = shift;
    my $ipaddr = shift;
    my $port = shift;
    my $community = shift;

    my $cref = $collector->collectorData( 'snmp' );
    return $cref->{'unreachableHostDeleted'}{$ipaddr}{$port}{$community};
}


sub hostReachableAgain
{
    my $collector = shift;
    my $ipaddr = shift;
    my $port = shift;
    my $community = shift;

    my $cref = $collector->collectorData( 'snmp' );
    if( exists( $cref->{'hostUnreachableSeen'}{$ipaddr}{$port}{$community} ) )
    {
        delete $cref->{'hostUnreachableSeen'}{$ipaddr}{$port}{$community};
    }
}


# Callback executed by Collector

sub deleteTarget
{
    my $collector = shift;
    my $token = shift;

    my $tref = $collector->tokenData( $token );
    my $cref = $collector->collectorData( 'snmp' );
    my $ipaddr = $tref->{'ipaddr'};
    my $oid = $tref->{'oid'};
    my $port = $collector->param($token, 'snmp-port');
    my $community = $collector->param($token, 'snmp-community');

    delete $cref->{'targets'}{$ipaddr}{$port}{$community}{$oid}{$token};
    if( not %{$cref->{'targets'}{$ipaddr}{$port}{$community}{$oid}} )
    {
        delete $cref->{'targets'}{$ipaddr}{$port}{$community}{$oid};

        if( not %{$cref->{'targets'}{$ipaddr}{$port}{$community}} )
        {
            delete $cref->{'targets'}{$ipaddr}{$port}{$community};

            if( not %{$cref->{'targets'}{$ipaddr}{$port}} )
            {
                delete $cref->{'targets'}{$ipaddr}{$port};

                if( not %{$cref->{'targets'}{$ipaddr}} )
                {
                    delete $cref->{'targets'}{$ipaddr};
                }
            }
        }
    }

    delete $cref->{'needsRemapping'}{$token};
}

# Main collector cycle

$Torrus::Collector::runCollector{'snmp'} =
    \&Torrus::Collector::SNMP::runCollector;

sub runCollector
{
    my $collector = shift;
    my $cref = shift;

    my @sessions;

    # Create one SNMP session per host address.
    # We assume that version, timeout and retries are the same
    # within one address

    while( my ($ipaddr, $ref1) = each %{$cref->{'reptoken'}} )
    {
        while( my ($port, $ref2) = each %{$ref1} )
        {
            while( my ($community, $token) = each %{$ref2} )
            {
                my $session =
                    openNonblockingSession( $collector, $token,
                                            $ipaddr, $port, $community );
                if( not defined($session) )
                {
                    return 0;
                }
                else
                {
                    push( @sessions, $session );
                    Debug("Created SNMP session for " .
                          "$ipaddr:$port:$community");
                    # We set SO_RCVBUF only once, because Net::SNMP shares
                    # one UDP socket for all sessions.
                    if( scalar( @sessions ) == 1 )
                    {
                        my $buflen = int($Torrus::Collector::SNMP::RxBuffer);
                        my $ok = $session->transport()->socket()->
                            sockopt( SO_RCVBUF, $buflen );
                        if( not $ok )
                        {
                            Error('Could not set SO_RCVBUF to ' .
                                  $buflen . ': ' . $!);
                        }
                        else
                        {
                            Debug('Set SO_RCVBUF to ' . $buflen);
                        }
                    }
                }

                my $oids_per_pdu =
                    $cref->{'oids_per_pdu'}{$ipaddr}{$port}{$community};

                my @oids = sort keys
                    %{$cref->{'targets'}{$ipaddr}{$port}{$community}};
                my @pdu_oids = ();
                while( scalar( @oids ) > 0 )
                {
                    my $oid = shift @oids;
                    push( @pdu_oids, $oid );

                    if( scalar( @oids ) == 0 or
                        ( scalar( @pdu_oids ) >= $oids_per_pdu ) )
                    {
                        if( not $cref->{'nosysuptime'}{$ipaddr}->
                            {$port}{$community} )
                        {
                            # We insert sysUpTime into every PDU, because
                            # we need it in further processing
                            push( @pdu_oids, $sysUpTime );
                        }
                        
                        if( Torrus::Log::isDebug() )
                        {
                            Debug("Sending SNMP PDU to $ipaddr:");
                            foreach my $oid ( @pdu_oids )
                            {
                                Debug($oid);
                            }
                        }

                        # Generate the list of tokens that form this PDU
                        my $pdu_tokens = {};
                        foreach my $oid ( @pdu_oids )
                        {
                            foreach my $token
                                ( keys %{$cref->{'targets'}{$ipaddr}
                                         {$port}{$community}{$oid}} )
                            {
                                $pdu_tokens->{$oid}{$token} = 1;
                            }
                        }
                        my $result =
                            $session->
                            get_request( -callback =>
                                         [ \&Torrus::Collector::SNMP::callback,
                                           $collector, $pdu_tokens,
                                           $port, $community ],
                                         -varbindlist => \@pdu_oids );
                        if( not defined $result )
                        {
                            Error("Cannot create SNMP request: " .
                                  $session->error);
                        }
                        @pdu_oids = ();
                    }
                }
            }
        }
    }

    snmp_dispatcher();

    foreach my $idx ( 0 .. $#sessions )
    {
        if( $idx == 0 and defined( $sessions[0]->transport() ) )
        {
            $sessions[0]->transport()->socket()->close();
        }
        $sessions[$idx]->close();
        delete $sessions[$idx];
    }
}


sub callback
{
    my $session = shift;
    my $collector = shift;
    my $pdu_tokens = shift;
    my $port = shift;
    my $community = shift;

    my $cref = $collector->collectorData( 'snmp' );
    my $ipaddr = $session->hostname();

    Debug("SNMP Callback executed for $ipaddr:$port:$community");

    if( not defined( $session->var_bind_list() ) )
    {
        Error("SNMP Error for $ipaddr:$port:$community: " . $session->error() .
              ' when retrieving ' . join(' ', sort keys %{$pdu_tokens}));

        probablyDead( $collector, $ipaddr, $port, $community );
        
        # Clear the mapping
        delete $cref->{'maps'}{$ipaddr}{$port}{$community};
        foreach my $oid ( keys %{$pdu_tokens} )
        {
            foreach my $token ( keys %{$pdu_tokens->{$oid}} )
            {
                $cref->{'needsRemapping'}{$token} = 1;
            }
        }
        return;
    }
    else
    {
        hostReachableAgain( $collector, $ipaddr, $port, $community );
    }

    my $timestamp = time();

    my $checkUptime = not $cref->{'nosysuptime'}{$ipaddr}{$port}{$community};
    my $doSetValue = 1;
    
    my $uptime = 0;

    if( $checkUptime )
    {
        my $uptimeTicks = $session->var_bind_list()->{$sysUpTime};
        if( defined $uptimeTicks )
        {
            $uptime = $uptimeTicks / 100;
            Debug("Uptime: $uptime");
        }
        else
        {
            Error("Did not receive sysUpTime for $ipaddr:$port:$community. ");
        }

        if( $uptime < $collector->period() or
            ( defined($cref->{'knownUptime'}{$ipaddr}{$port}{$community})
              and
              $uptime + $collector->period() <
              $cref->{'knownUptime'}{$ipaddr}{$port}{$community} ) )
        {
            # The agent has reloaded. Clean all maps and push UNDEF
            # values to the storage
            
            Info("Agent rebooted: $ipaddr:$port:$community");
            delete $cref->{'maps'}{$ipaddr}{$port}{$community};

            $timestamp -= $uptime;
            foreach my $oid ( keys %{$pdu_tokens} )
            {
                foreach my $token ( keys %{$pdu_tokens->{$oid}} )
                {
                    $collector->setValue( $token, 'U', $timestamp, $uptime );
                    $cref->{'needsRemapping'}{$token} = 1;
                }
            }
            
            $doSetValue = 0;
        }
        $cref->{'knownUptime'}{$ipaddr}{$port}{$community} = $uptime;
    }
    
    if( $doSetValue )
    {
        while( my ($oid, $value) = each %{ $session->var_bind_list() } )
        {
            # Debug("OID=$oid, VAL=$value");
            if( $value eq 'noSuchObject' or
                $value eq 'noSuchInstance' or
                $value eq 'endOfMibView' )
            {
                Error("Error retrieving $oid from " .
                      "$ipaddr:$port:$community: $value");
            }
            else
            {
                if( $cref->{'64bit_oid'}{$oid} )
                {
                    $value = Math::BigInt->new($value);
                }

                foreach my $token ( keys %{$pdu_tokens->{$oid}} )
                {
                    $collector->setValue( $token, $value,
                                          $timestamp, $uptime );
                }
            }
        }
    }
}


# Execute this after the collector has finished

$Torrus::Collector::postProcess{'snmp'} =
    \&Torrus::Collector::SNMP::postProcess;

sub postProcess
{
    my $collector = shift;
    my $cref = shift;

    # First time is executed right after collector initialization,
    # so there's no need to initTargetAttributes()

    if( exists( $cref->{'notFirstTimePostProcess'} ) )
    {
        foreach my $token ( keys %{$cref->{'needsRemapping'}} )
        {
            delete $cref->{'needsRemapping'}{$token};
            if( not Torrus::Collector::SNMP::initTargetAttributes
                ( $collector, $token ) )
            {
                $collector->deleteTarget($token);
            }
        }
    }
    else
    {
        $cref->{'notFirstTimePostProcess'} = 1;
    }
}

1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
