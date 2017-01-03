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

    return $self;

    my $writing = $options{'-WriteAccess'};

    $self->{'db_users'} = new Torrus::DB('users', -WriteAccess => $writing );
    defined( $self->{'db_users'} ) or return( undef );

    $self->{'db_acl'} = new Torrus::DB('acl', -WriteAccess => $writing );
    defined( $self->{'db_acl'} ) or return( undef );

    $self->{'is_writing'} = $writing;

    return $self;
}


sub DESTROY
{
    my $self = shift;

    Debug('Destroying ACL object');

    delete $self->{'db_users'};
    delete $self->{'db_acl'};
    return;
}


sub hasPrivilege
{
    my $self = shift;
    my $uid = shift;
    my $object = shift;
    my $privilege = shift;

    foreach my $group ( $self->memberOf( $uid ) )
    {
        if( $self->{'db_acl'}->get( $group.':'.$object.':'.$privilege ) )
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

    my $glist = $self->{'db_users'}->get( 'gm:' . $uid );
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

    return $self->{'db_users'}->get( 'ua:' . $uid . ':' . $attr );
}


sub groupAttribute
{
    my $self = shift;
    my $group = shift;
    my $attr = shift;

    return $self->{'db_users'}->get( 'ga:' . $group . ':' . $attr );
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
