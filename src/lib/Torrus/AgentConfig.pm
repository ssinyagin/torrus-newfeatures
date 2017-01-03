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

use Redis;
use Git::Raw;
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

    $self->{'repo'} = Git::Raw::Repository->open($self->{'repodir'});
    
    $self->{'redis'} = Redis->new(server => $Torrus::Global::redisServer);
    $self->{'redis_prefix'} = $Torrus::Global::redisPrefix;

    $self->{'json'} = JSON->new->allow_nonref(1);
    return $self;
}



sub readAll
{
    my $self = shift;
    my $cb_updated = shift;

    my $n_updated = 0;
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

    my $commit = Git::Raw::Commit->lookup($self->{'repo'}, $head);
    die("Cannot lookup commit $head") unless defined($commit);
    my $tree = $commit->tree();

    foreach my $l1entry ($tree->entries())
    {
        my $l1name = $l1entry->name();
        my $l1tree = $l1entry->object();
        die('Expected a tree object') unless $l1tree->is_tree();

        foreach my $l2entry ($l1tree->entries())
        {
            my $l2name = $l2entry->name();
            my $l2tree = $l2entry->object();
            die('Expected a tree object') unless $l2tree->is_tree();

            foreach my $l3entry ($l2tree->entries())
            {
                my $l3name = $l3entry->name();
                my $l3blob = $l3entry->object();
                die('Expected a blob object') unless $l3blob->is_blob();
                
                my $token = $l1name . $l2name . $l3name;
                my $data = $self->{'json'}->decode($l3blob->content());
                &{$cb_updated}($token, $data);
                $n_updated++
            }
        }
    }

    Debug('Read ' . $n_updated . ' entries from ' . $self->{'branch'});
    
    $self->{'current_head'} = $head;
    $self->{'current_tree'} = $tree;
    
    return;
}


sub readUpdates
{
    my $self = shift;
    my $cb_updated = shift;
    my $cb_deleted = shift;

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

    my $n_updated = 0;
    my $n_deleted = 0;

    Debug('Reading new entries in ' . $self->{'branch'});
    my $commit = Git::Raw::Commit->lookup($self->{'repo'}, $head);
    die("Cannot lookup commit $head") unless defined($commit);
    my $tree = $commit->tree();

    my $diff = $self->{'current_tree'}->diff(
        {'tree' => $tree,
         'flags' => {
             'skip_binary_check' => 1,
         },
        });
        
    my @deltas = $diff->deltas();
    foreach my $delta (@deltas)
    {
        my $path = $delta->new_file()->path();
        my $token = join('', split('/', $path));
        
        if( $delta->status() eq 'deleted')
        {
            &{$cb_deleted}($token);
            $n_deleted++;
        }
        else
        {
            my $entry = $tree->entry_bypath($path);
            my $blob = $entry->object();
            die('Expected a blob object') unless $blob->is_blob();
            my $data = $self->{'json'}->decode($blob->content());
            &{$cb_updated}($token, $data);
            $n_updated++;
        }
    }

    $self->{'current_head'} = $head;
    $self->{'current_tree'} = $tree;

    Debug("Updated: $n_updated, Deleted: $n_deleted entries");
    return 1;
}
    






1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
