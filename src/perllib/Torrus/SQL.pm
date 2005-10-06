#  Copyright (C) 2005  Stanislav Sinyagin
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

# Package for RDBMS communication management in Torrus
# Classes should inherit Torrus::SQL and execute Torrus::SQL->new(),
# and then use methods of DBIx::Abstract.

package Torrus::SQL;

use strict;
use DBI;
use DBIx::Abstract;

use base 'DBIx::Abstract';

use Torrus::Log;


# Obtain connection attributes for particular class and object subtype.
# The attributes are defined in torrus-siteconfig.pl, in a hash
# %Torrus::SQL::connections. The default attributes are defined in
# 'Default' key, then they may be overwritten by 'Class' key for a given
# perl class, and then overwritten by 'Class/subtype' for a given object
# subtype (optional). The key attributes are:
# 'dsn', 'username', and 'password'.
# Returns a hash reference with the same keys.

sub getConnectionArgs
{
    my $class = shift;
    my $objClass = shift;
    my $subtype = shift;

    my @lookup = ('Default', $objClass);
    if( defined( $subtype ) and length( $subtype ) > 0 )
    {
        push( @lookup, $objClass . '/' . $subtype );
    }

    my $ret = {};
    foreach my $attr ( 'dsn', 'username', 'password' )
    {
        my $val;
        foreach my $key ( @lookup )
        {
            if( defined( $Torrus::SQL::connections{$key} ) )
            {
                if( defined( $Torrus::SQL::connections{$key}{$attr} ) )
                {
                    $val = $Torrus::SQL::connections{$key}{$attr};
                }
            }
        }
        if( not defined( $val ) )
        {
            die('Undefined attribute in %Torrus::SQL::connections: ' . $attr);
        }
        $ret->{$attr} = $val;
    }

    return $ret;
}


sub new
{
    my $class = shift;
    my $subtype = shift;

    my $attrs = Torrus::SQL->getConnectionArgs( $class, $subtype );
    my $self = Torrus::SQL->connect( $attrs );
    die('Error creating SQL connection: ' . $!) unless defined( $self );

    $self->{'subtype'} = $subtype;
}


# For those who want direct DBI manipulation, simply call
# Class->dbh($subtype) with optional subtype. Then you don't use
# any other methods of Torrus::SQL.

sub dbh
{
    my $class = shift;
    my $subtype = shift;

    my $attrs = Torrus::SQL->getConnectionArgs( $class, $subtype );
    
    my $dbh = DBI->connect( $attrs->{'dsn'},
                            $attrs->{'username'},
                            $attrs->{'password'},
                            { 'PrintError' => 0,
                              'AutoCommit' => 0 } );

    if( not defined( $dbh ) )
    {
        Error('Error connecting to DBI source ' . $attrs->{'dsn'} . ': ' .
              $DBI::errstr);
    }

    return $dbh;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
