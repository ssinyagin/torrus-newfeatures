#  Copyright (C) 2002-2011  Stanislav Sinyagin
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

# Stanislav Sinyagin <ssinyagin@yahoo.com>


####  Torrus::DevDiscover::DevDetails: the information container for a device
####

package Torrus::DevDiscover::DevDetails;
use strict;
use warnings;

use Torrus::RPN;
use Torrus::Log;

sub new
{
    my $self = {};
    my $class = shift;
    bless $self, $class;

    $self->{'params'}   = {};
    $self->{'snmpvars'} = {}; # SNMP results stored here
    $self->{'devtype'}  = {}; # Device types
    $self->{'caps'}     = {}; # Device capabilities
    $self->{'data'}     = {}; # Discovery data

    return $self;
}


sub setParams
{
    my $self = shift;
    my $params = shift;

    while( my ($param, $value) = each %{$params} )
    {
        $self->{'params'}->{$param} = $value;
    }
    return;
}


sub setParam
{
    my $self = shift;
    my $param = shift;
    my $value = shift;

    $self->{'params'}->{$param} = $value;
    return;
}


sub param
{
    my $self = shift;
    my $name = shift;
    return $self->{'params'}->{$name};
}


# The following 3 methods get around undefined parameters and
# make "use warnings" happy

sub paramEnabled
{
    my $self = shift;
    my $name = shift;
    my $val = $self->param($name);
    return (defined($val) and ($val eq 'yes'));
}

sub paramDisabled
{
    my $self = shift;
    my $name = shift;
    my $val = $self->param($name);
    return (not defined($val) or ($val ne 'yes'));
}

sub paramString
{
    my $self = shift;
    my $name = shift;
    my $val = $self->param($name);
    return (defined($val) ? $val:'');    
}


##
# store the query results for later use
# WARNING: this method is deprecated. Use $dd->walkSnmpTable() instead.

sub storeSnmpVars
{
    my $self = shift;
    my $vars = shift;

    while( my( $oid, $value ) = each %{$vars} )
    {
        if( $oid !~ /^\d[0-9.]+\d$/o )
        {
            Error('Invalid OID syntax: from ' .
                  $self->paramString('snmp-host') .
                  ': \'' . $oid . '\'');
        }
        else
        {
            $self->{'snmpvars'}{$oid} = $value;
            
            while( $oid ne '' )
            {
                $oid =~ s/\d+$//o;
                $oid =~ s/\.$//o;
                if( not exists( $self->{'snmpvars'}{$oid} ) )
                {
                    $self->{'snmpvars'}{$oid} = undef;
                }
            }
        }
    }

    # Clean the cache of sorted OIDs
    $self->{'sortedoids'} = undef;
    return;
}

##
# check if the stored query results have such OID prefi
# WARNING: this method is deprecated. Use $dd->checkSnmpTable() instead.

sub hasOID
{
    my $self = shift;
    my $oid = shift;

    my $found = 0;
    if( exists( $self->{'snmpvars'}{$oid} ) )
    {
        $found = 1;
    }
    return $found;
}

##
# get the value of stored SNMP variable
# WARNING: this method is deprecated. 

sub snmpVar
{
    my $self = shift;
    my $oid = shift;
    return $self->{'snmpvars'}{$oid};
}

##
# get the list of table indices for the specified prefix
# WARNING: this method is deprecated. Use $dd->walkSnmpTable() instead.

sub getSnmpIndices
{
    my $self = shift;
    my $prefix = shift;

    # Remember the sorted OIDs, as sorting is quite expensive for large
    # arrays.
    
    if( not defined( $self->{'sortedoids'} ) )
    {
        $self->{'sortedoids'} = [];
        push( @{$self->{'sortedoids'}},
              Net::SNMP::oid_lex_sort( keys %{$self->{'snmpvars'}} ) );
    }
        
    my @ret;
    my $prefixLen = length( $prefix ) + 1;
    my $matched = 0;

    foreach my $oid ( @{$self->{'sortedoids'}} )
    {
        if( defined($self->{'snmpvars'}{$oid} ) )
        {
            if( Net::SNMP::oid_base_match( $prefix, $oid ) )
            {
                # Extract the index from OID
                my $index = substr( $oid, $prefixLen );
                push( @ret, $index );
                $matched = 1;
            }
            elsif( $matched )
            {
                last;
            }
        }
    }
    return @ret;
}


##
# device type is the registered discovery module name

sub setDevType
{
    my $self = shift;
    my $type = shift;
    $self->{'devtype'}{$type} = 1;
    return;
}

sub isDevType
{
    my $self = shift;
    my $type = shift;
    return $self->{'devtype'}{$type};
}

sub getDevTypes
{
    my $self = shift;
    return keys %{$self->{'devtype'}};
}

##
# device capabilities. Each discovery module may define its own set of
# capabilities and use them for information exchange between checkdevtype(),
# discover(), and buildConfig() of its own and dependant modules

sub setCap
{
    my $self = shift;
    my $cap = shift;
    Debug('Device capability: ' . $cap);
    $self->{'caps'}{$cap} = 1;
    return;
}

sub hasCap
{
    my $self = shift;
    my $cap = shift;
    return $self->{'caps'}{$cap};
}

sub clearCap
{
    my $self = shift;
    my $cap = shift;
    Debug('Clearing device capability: ' . $cap);
    if( exists( $self->{'caps'}{$cap} ) )
    {
        delete $self->{'caps'}{$cap};
    }
    return;
}



sub data
{
    my $self = shift;
    return $self->{'data'};
}


sub screenSpecialChars
{
    my $self = shift;
    my $txt = shift;

    $txt =~ s/:/{COLON}/gm;
    $txt =~ s/;/{SEMICOL}/gm;
    $txt =~ s/%/{PERCENT}/gm;

    return $txt;
}


sub applySelectors
{
    my $self = shift;

    my $selList = $self->param('selectors');
    return if not defined( $selList );

    my $reg = \%Torrus::DevDiscover::selectorsRegistry;
    
    foreach my $sel ( split('\s*,\s*', $selList) )
    {
        my $type = $self->param( $sel . '-selector-type' );
        if( not defined( $type ) )
        {
            Error('Parameter ' . $sel . '-selector-type must be defined ' .
                  'for ' . $self->param('snmp-host'));
        }
        elsif( not exists( $reg->{$type} ) )
        {
            Error('Unknown selector type: ' . $type .
                  ' for ' . $self->param('snmp-host'));
        }
        else
        {
            Debug('Initializing selector: ' . $sel);
            
            my $treg = $reg->{$type};
            my @objects = &{$treg->{'getObjects'}}( $self, $type );

            foreach my $object ( @objects )
            {
                Debug('Checking object: ' .
                      &{$treg->{'getObjectName'}}( $self, $object, $type ));

                my $expr = $self->param( $sel . '-selector-expr' );
                if( not defined($expr) or $expr eq '' )
                {
                    $expr = '1';
                }

                my $callback = sub
                {
                    my $attr = shift;
                    my $checkval = $self->param( $sel . '-' . $attr );
                    
                    Debug('Checking attribute: ' . $attr .
                          ' and value: ' . $checkval);
                    my $ret = &{$treg->{'checkAttribute'}}( $self,
                                                            $object, $type,
                                                            $attr, $checkval );
                    Debug(sprintf('Returned value: %d', $ret));
                    return $ret;                    
                };
                
                my $rpn = new Torrus::RPN;
                my $result = $rpn->run( $expr, $callback );
                Debug('Selector result: ' . $result);
                if( $result )
                {
                    my $actions = $self->param( $sel . '-selector-actions' );
                    foreach my $action ( split('\s*,\s*', $actions) )
                    {
                        my $arg =
                            $self->param( $sel . '-' . $action . '-arg' );
                        $arg = 1 if not defined( $arg );
                        
                        Debug('Applying action: ' . $action .
                              ' with argument: ' . $arg);
                        &{$treg->{'applyAction'}}( $self, $object, $type,
                                                   $action, $arg );
                    }
                }
            }
        }
    }

    return;
}    

1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
