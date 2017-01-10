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

# Stanislav Sinyagin <ssinyagin@k-open.com>


# Search database interface

package Torrus::Search;
use strict;
use warnings;

use Torrus::Log;
use Git::ObjectStore;
use JSON;

sub new
{
    my $class = shift;
    my $self = {};
    bless $self, $class;

    $self->{'store'} = new Git::ObjectStore(
        'repodir' => $Torrus::Global::gitRepoDir,
        'branchname' => 'searchdb');

    $self->{'json'} = JSON->new->canonical(1)->allow_nonref(1);
    
    return $self;
}



sub searchTree
{
    my $self = shift;
    my $substring = lc( shift );
    my $tree = shift;

    my $ret = {};

    my $cb_read = sub {
        my ($dummy, $xtree, $word, $token, $param) = split('/', $_[0]);
        if( index($word, $substring) >= 0 )
        {
            $ret->{$token}{$param} = 1;
        }
    };

    $self->{'store'}->recursive_read('words/' . $tree, $cb_read, 1);

    return $ret;
}


sub searchGlobal
{
    my $self = shift;
    my $substring = lc( shift );

    my $ret = {};

    my $cb_read = sub {
        my ($dummy, $word, $token, $param) = split('/', $_[0]);
        my $content = $_[1];
        
        if( index($word, $substring) >= 0 )
        {
            if( $param eq '__TREENAME__' )
            {
                $ret->{$token}{$param} = $self->{'json'}->decode($content);
            }
            else
            {
                $ret->{$token}{$param} = 1;
            }
        }
    };

    $self->{'store'}->recursive_read('wordsglobal', $cb_read);

    return $ret;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
