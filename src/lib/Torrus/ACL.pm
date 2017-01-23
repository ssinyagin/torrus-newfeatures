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

# Stanislav Sinyagin <ssinyagin@k-open.com>


package Torrus::ACL;

use strict;
use warnings;

use Torrus::Redis;
use Torrus::Log;


BEGIN
{
    if( not eval('require ' . $Torrus::ACL::userAuthModule) or $@ )
    {
        die($@);
    }
}

sub new
{
    my $self = {};
    my $class = shift;
    my %options = @_;
    bless $self, $class;

    if( not eval('$self->{"auth"} = new ' . $Torrus::ACL::userAuthModule)
        or $@ )
    {
        die($@);
    }

    $self->{'redis'} =
        Torrus::Redis->new(server => $Torrus::Global::redisServer);
    $self->{'users_hname'} = $Torrus::Global::redisPrefix . 'users';
    $self->{'acl_hname'} = $Torrus::Global::redisPrefix . 'acl';

    return $self;
}


sub _users_get
{
    my $self = shift;
    my $key = shift;

    return $self->{'redis'}->hget($self->{'users_hname'}, $key);
}


sub hasPrivilege
{
    my $self = shift;
    my $uid = shift;
    my $object = shift;
    my $privilege = shift;

    foreach my $group ( $self->memberOf( $uid ) )
    {
        if( $self->{'redis'}->hget($self->{'acl_hname'},
                                   $group.':'.$object.':'.$privilege ) )
        {
            Debug('User ' . $uid . ' has privilege ' . $privilege .
                  ' for ' . $object);
            return 1;
        }
    }

    if( $object ne '*' )
    {
        return $self->hasPrivilege( $uid, '*', $privilege );
    }
    
    Debug('User ' . $uid . ' has NO privilege ' . $privilege .
          ' for ' . $object);
    return undef;
}


sub memberOf
{
    my $self = shift;
    my $uid = shift;

    my $glist = $self->_users_get('gm:' . $uid);
    return( defined( $glist ) ? split(',', $glist) : () );
}


sub authenticateUser
{
    my $self = shift;
    my $uid = shift;
    my $password = shift;

    my @attrList = $self->{'auth'}->getUserAttrList();
    my $attrValues = {};
    foreach my $attr ( @attrList )
    {
        $attrValues->{$attr} = $self->userAttribute( $uid, $attr );
    }

    my $ret = $self->{'auth'}->authenticateUser( $uid, $password,
                                                 $attrValues );
    Debug('User authentication: uid=' . $uid . ', result=' .
          ($ret ? 'true':'false'));
    return $ret;
}


sub userAttribute
{
    my $self = shift;
    my $uid = shift;
    my $attr = shift;

    return $self->_users_get('ua:' . $uid . ':' . $attr);
}


sub groupAttribute
{
    my $self = shift;
    my $group = shift;
    my $attr = shift;

    return $self->_users_get('ga:' . $group . ':' . $attr);
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
