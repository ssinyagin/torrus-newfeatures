#  Copyright (C) 2010  Stanislav Sinyagin
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

# Stanislav Sinyagin <ssinyagin@k-open.com>

# this policy is paranoic about our read() method
## no critic (Subroutines::ProhibitBuiltinHomonyms)

# SNMP failures statistics interface

package Torrus::SNMP_Failures;
use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use Torrus::Redis;

use Torrus::Log;


sub new
{
    my $self = {};
    my $class = shift;
    my %options = @_;
    bless $self, $class;

    %{$self->{'options'}} = %options;

    die() if ( not defined($options{'-Tree'}) or
               not defined($options{'-Instance'}) );

    $self->{'redis'} =
        Torrus::Redis->new(server => $Torrus::Global::redisServer);
    $self->{'redis_hname'} =
        $Torrus::Global::redisPrefix . 'snmp_failures:' . $options{'-Tree'};
    
    $self->{'counters'} = ['unreachable', 'deleted', 'mib_errors'];
    
    return $self;
}



sub init
{
    my $self = shift;

    $self->{'redis'}->del($self->{'redis_hname'});
    
    foreach my $c ( @{$self->{'counters'}} )
    {
        $self->{'redis'}->hset($self->{'redis_hname'}, 'c:' . $c, 0);
    }
    return;
}



sub host_failure
{
    my $self = shift;    
    my $type = shift;
    my $hosthash = shift;

    $self->{'redis'}->hset($self->{'redis_hname'}, 'h:' . $hosthash,
                           $type . ':' . time());
    return;
}


sub is_host_available
{
    my $self = shift;    
    my $hosthash = shift;

    return( not defined($self->{'redis'}->hget($self->{'redis_hname'},
                                               'h:' . $hosthash)) );
}


sub set_counter
{
    my $self = shift;    
    my $type = shift;
    my $count = shift;

    $self->{'redis'}->hset($self->{'redis_hname'}, 'c:' . $type, $count);
    return;
}
    

sub remove_host
{
    my $self = shift;    
    my $hosthash = shift;

    $self->{'redis'}->hdel($self->{'redis_hname'}, 'h:' . $hosthash);
    return;
}

    
sub mib_error
{
    my $self = shift;    
    my $hosthash = shift;
    my $path = shift;

    my $redis = $self->{'redis'};
    my $hname = $self->{'redis_hname'};
    
    my $count = $redis->hget($hname, 'M:' . $hosthash);
    $count = 0 unless defined($count);

    $redis->hset($hname, 'm:' . md5_hex($path) . ':' . $hosthash,
                 $path . ':' . time());    
    $redis->hset($hname, 'M:' . $hosthash, $count + 1);

    my $global_count = $redis->hget($hname, 'c:mib_errors');
    $redis->hset($hname, 'c:mib_errors', $global_count + 1);
    return;
}



sub read
{
    my $self = shift;
    my $out = shift;
    my %options = @_;

    my $redis = $self->{'redis'};
    my $hname = $self->{'redis_hname'};
    
    foreach my $c ( @{$self->{'counters'}} )
    {
        if( not defined( $out->{'total_' . $c} ) )
        {
            $out->{'total_' . $c} = 0;
        }
        
        $out->{'total_' . $c} += $redis->hget($hname, 'c:' . $c);

        if( $options{'-details'} and
            not defined( $out->{'detail_' . $c} ) )
        {
            $out->{'detail_' . $c} = {};
        }
    }

    if( $options{'-details'} )
    {
        my $all = $redis->hgetall($hname);
        while( scalar(@{$all}) > 0 )
        {
            my $key = shift @{$all};
            my $val = shift @{$all};
            
            if( $key =~ /^h:(.+)$/o )
            {
                my $hosthash = $1;
                my ($counter, $timestamp) = split(/:/o, $val);

                $out->{'detail_' . $counter}{$hosthash} = {
                    'timestamp' => 0 + $timestamp,
                    'time' => scalar(localtime( $timestamp )),
                };
            }
            elsif( $key =~ /^m:[0-9a-f]+:(.+)$/o )
            {
                my $hosthash = $1;
                my ($path, $timestamp) = split(/:/o, $val);

                $out->{'detail_mib_errors'}{$hosthash}{'nodes'}{$path} = {
                    'timestamp' => 0 + $timestamp,
                    'time' => scalar(localtime( $timestamp )),
                }
            }
            elsif( $key =~ /^M:(.+)$/o )
            {
                my $hosthash = $1;
                my $count = 0 + $val;
                
                if( not defined
                    ( $out->{'detail_mib_errors'}{$hosthash}{'count'}) )
                {
                    $out->{'detail_mib_errors'}{$hosthash}{'count'} = 0;
                }
                
                $out->{'detail_mib_errors'}{$hosthash}{'count'} += $count;
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
