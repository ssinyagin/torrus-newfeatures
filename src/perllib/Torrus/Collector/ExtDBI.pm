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

## Pluggable backend module for ExternalStorage
## Stores data in a generic SQL database

package Torrus::Collector::ExtDBI;

use strict;
use DBI;
use Math::BigFloat lib => 'GMP';

$Torrus::Collector::ExternalStorage::backendInit =
    \&Torrus::Collector::ExtDBI::backendInit;

$Torrus::Collector::ExternalStorage::backendOpenSession =
    \&Torrus::Collector::ExtDBI::backendOpenSession;

$Torrus::Collector::ExternalStorage::backendStoreData =
    \&Torrus::Collector::ExtDBI::backendStoreData;

$Torrus::Collector::ExternalStorage::backendCloseSession =
    \&Torrus::Collector::ExtDBI::backendCloseSession;


# Configurables from torrus-siteconfig.pl
our $dsn;
our $username;
our $password;
our $sqlStatement;

my $dbh;
my $sth;

sub backendInit
{
    my $collector = shift;
    my $token = shift;
}

sub backendOpenSession
{
    $dbh = DBI->connect( $dsn, $username, $password,
                         { 'PrintError' => 0,
                           'AutoCommit' => 0 } );

    if( not defined( $dbh ) )
    {
        Error('Error connecting to DBI source: ' . $DBI::errstr);
    }
    else
    {
        $sth = $dbh->prepare( $sqlStatement );
        if( not defined( $sth ) )
        {
            Error('Error preparing the SQL statement: ' . $dbh->errstr);
        }
    }
}


sub backendStoreData
{
    # $timestamp, $serviceid, $value
    my @triple = @_;

    if( defined( $dbh ) and defined( $sth ) )
    {
        if( $sth->execute( @triple ) )
        {
            return 1;
        }
        else
        {
            Error('Error executing SQL: ' . $dbh->errstr);
        }
    }

    return undef;
}


sub backendCloseSession
{
    undef $sth;
    if( defined( $dbh ) )
    {
        $dbh->commit();
        $dbh->disconnect();
        undef $dbh;
    }
}


    
1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
