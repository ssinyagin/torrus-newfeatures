#  Copyright (C) 2017  Stanislav Sinyagin
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


package Torrus::AgentConfig;

use strict;
use warnings;

use Torrus::Redis;
use Git::ObjectStore;
use JSON;

use Torrus::Log;

sub new
{
    my $class = shift;
    my $treename = shift;
    my $agent = shift;
    my $instance = shift;
    
    my $self = {};
    bless $self, $class;

    $self->{'treename'} = $treename;
    $self->{'agent'} = $agent;
    $self->{'instance'} = $instance;

    $self->{'repodir'} = $Torrus::Global::gitRepoDir;
    $self->{'branch'} = sprintf('%s_%s_%.4x', $treename, $agent, $instance);
    
    $self->{'redis'} =
        Torrus::Redis->new(server => $Torrus::Global::redisServer);
    $self->{'redis_prefix'} = $Torrus::Global::redisPrefix;

    $self->{'json'} = JSON->new->allow_nonref(1);
    return $self;
}




sub _store
{
    my $self = shift;
    
    my $store = new Git::ObjectStore(
        'repodir' => $self->{'repodir'},
        'branchname' => $self->{'branch'},
        'goto' => $self->{'current_head'});

    return $store;
}


sub needsFlush
{
    my $self = shift;

    if( not defined($self->{'current_head'}) )
    {
        return 1;
    }
    else
    {
        eval { $self->_store() };
        if( $@ )
        {
            return 1;
        }
    }

    return 0;
}
        
    
sub readAll
{
    my $self = shift;
    my $cb_token_updated = shift;

    my $informed_not_ready;

    my $head;
    while( not defined($head) )
    {
        $head = $self->{'redis'}->hget(
            $self->{'redis_prefix'} . 'githeads', $self->{'branch'});
        if( not defined($head) )
        {
            if( not $informed_not_ready )
            {
                Info('Nothing is yet available for branch ' .
                     $self->{'branch'} . '. Waiting for data.');
                $informed_not_ready = 1;
            }
            sleep(20);
        }
    }

    Debug('Reading all entries in ' . $self->{'branch'});
    
    $self->{'current_head'} = $head;
    my $n_updated = 0;
    my $store = $self->_store();
    
    my $cb_read = sub {
        my ($path, $data) = @_;
        my $token = join('', split('/', $path));
        &{$cb_token_updated}($token, $self->{'json'}->decode($data));
        $n_updated++
    };
    
    $store->recursive_read('', $cb_read);

    Debug('Read ' . $n_updated . ' entries from ' . $self->{'branch'});
    
    return;
}


sub readUpdates
{
    my $self = shift;
    my $cb_token_updated = shift;
    my $cb_token_deleted = shift;

    if( not defined($self->{'current_head'}) )
    {
        die('readUpdates was called prior to readAll');
    }

    my $head = $self->{'redis'}->hget(
        $self->{'redis_prefix'} . 'githeads', $self->{'branch'});
    
    if( not defined($head) )
    {
        die('Cannot read the branch head from Redis');
    }

    if( $head eq $self->{'current_head'} )
    {
        return 0;
    }

    my $old_head = $self->{'current_head'};
    $self->{'current_head'} = $head;
    my $store = $self->_store();
    
    my $n_updated = 0;
    my $n_deleted = 0;

    my $cb_updated = sub {
        my ($path, $data) = @_;
        my $token = join('', split('/', $path));
        &{$cb_token_updated}($token, $self->{'json'}->decode($data));
        $n_updated++
    };
    
    my $cb_deleted = sub {
        my ($path) = @_;
        my $token = join('', split('/', $path));
        &{$cb_token_deleted}($token);
        $n_deleted++
    };

    Debug('Reading new entries in ' . $self->{'branch'});
    $store->read_updates($old_head, $cb_updated, $cb_deleted);

    Debug("Updated: $n_updated, Deleted: $n_deleted entries");
    return 1;
}
    






1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
