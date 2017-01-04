#  Copyright (C) 2002-2017  Stanislav Sinyagin
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


package Torrus::ConfigTree;

use strict;
use warnings;

use Redis;
use Redis::DistLock;
use Git::Raw;
use JSON;
use File::Path qw(make_path);
use Digest::SHA qw(sha1_hex);
use Cache::Ref::CART;

use Torrus::Log;

use Carp;

sub new
{
    my $self = {};
    my $class = shift;
    my %options = @_;
    bless $self, $class;

    my $treename = $options{'-TreeName'};
    die('ERROR: TreeName is mandatory') if not $treename;
    $self->{'treename'} = $treename;

    $self->{'iamwriter'} = $options{'-WriteAccess'} ? 1:0;

    $self->{'redis'} = Redis->new(server => $Torrus::Global::redisServer);
    $self->{'redis_prefix'} = $Torrus::Global::redisPrefix;

    $self->{'json'} = JSON->new->canonical(1)->allow_nonref(1);

    my $repodir = $Torrus::Global::gitRepoDir;
    if( defined($options{'-RepoDir'}) )
    {
        $repodir = $options{'-RepoDir'};
    }

    $self->{'repodir'} = $repodir;
    $self->{'branch'} = $treename . '_configtree';

    if( not -e $repodir . '/config' )
    {
        $self->_lock_repodir();
        if( not -e $repodir . '/config' )
        {
            Debug("Initializing the Git repository in $repodir");
            my $repo = Git::Raw::Repository->init($repodir, 1);
            my $remote_url;

            if( $self->{'iamwriter'} )
            {
                if( $Torrus::ConfigTree::writerPush )
                {
                    $remote_url = $Torrus::ConfigTree::writerRemoteRepo;
                }
            }
            else
            {
                if( $Torrus::ConfigTree::readerPull )
                {
                    $remote_url = $Torrus::ConfigTree::readerRemoteRepo;
                }
            }

            if( defined($remote_url) )
            {
                Git::Raw::Remote->create($repo,
                                         $Torrus::ConfigTree::remoteName,
                                         $remote_url);
            }
        }
        $self->_unlock_repodir();
    }

    if( not $self->{'iamwriter'} )
    {
        if( not $self->gotoHead() )
        {
            # could not retrieve the head commit
            # the writer has not yet written its branch
            return undef;
        }

        $self->_read_paramprops();
    }

    $self->{'objcache'} = Cache::Ref::CART->new
        ( size => $Torrus::ConfigTree::objCacheSize );

    return $self;
}


sub _read_paramprops
{
    my $self = shift;
    $self->{'paramprop'} = $self->_read_json('paramprops');
    $self->{'paramprop'} = {} unless defined($self->{'paramprop'});
    return;
}





sub _lock_repodir
{
    my $self = shift;

    if( not defined($self->{'distlock'}) )
    {
        $self->{'distlock'} = Redis::DistLock->new
            ( servers => [$Torrus::Global::redisServer] );
    }

    Debug('Acquiring a lock for ' . $self->{'repodir'});
    my $lock =
        $self->{'distlock'}->lock($self->{'redis_prefix'} .
                                  'gitlock:' . $self->{'repodir'},
                                  7200);
    if( not defined($lock) )
    {
        die('Failed to acquire a lock for ' . $self->{'repodir'});
    }

    $self->{'mutex'} = $lock;
    return;
}


sub _unlock_repodir
{
    my $self = shift;

    Debug('Releasing the lock for ' . $self->{'repodir'});

    $self->{'distlock'}->release($self->{'mutex'});
    delete $self->{'mutex'};
    return;
}


sub _sha_file
{
    my $self = shift;
    my $sha = shift;
    return join('/', substr($sha, 0, 2), substr($sha, 2, 2), substr($sha, 4));
}


sub _read_file
{
    my $self = shift;
    my $filename = shift;

    if( defined($self->{'gitindex'}) )
    {
        my $entry = $self->{'gitindex'}->find($filename);
        if( defined($entry) )
        {
            return $entry->blob()->content();
        }
        else
        {
            return undef;
        }
    }
    else
    {
        my $entry = $self->{'gittree'}->entry_bypath($filename);
        if( defined($entry) )
        {
            return $entry->object()->content();
        }
        else
        {
            return undef;
        }
    }
}


sub _read_json
{
    my $self = shift;
    my $filename = shift;

    my $blob = $self->_read_file($filename);
    if( defined($blob) )
    {
        return $self->{'json'}->decode($blob);
    }
    else
    {
        return undef;
    }
}



sub _node_read
{
    my $self = shift;
    my $token = shift;

    my $ret = $self->{'objcache'}->get($token);
    if( not defined($ret) )
    {
        my $sha_file = $self->_sha_file($token);

        $ret = $self->_read_json('nodes/' . $sha_file);
        if( not defined($ret) )
        {
            return undef;
        }

        if( $ret->{'is_subtree'} )
        {
            my $children = $self->_read_json('children/' . $sha_file);
            die('Cannot find list of children for ' . $token)
                unless defined($children);
            $ret->{'children'} = $children;
        }

        $self->{'objcache'}->set($token => $ret);
    }

    return $ret;
}


sub _other_read
{
    my $self = shift;
    my $name = shift;

    my $ret = $self->{'objcache'}->get($name);
    if( not defined($ret) )
    {
        $ret = $self->_read_json('other/' . $name);
        if( defined($ret) )
        {
            $self->{'objcache'}->set($name => $ret);
        }
    }

    return $ret;
}


sub _node_file_exists
{
    my $self = shift;
    my $token = shift;

    my $filename = 'nodes/' . $self->_sha_file($token);

    if( defined($self->{'gitindex'}) )
    {
        return defined($self->{'gitindex'}->find($filename));
    }
    else
    {
        return defined($self->{'gittree'}->entry_bypath($filename));
    }
}


sub gotoHead
{
    my $self = shift;

    my $head = $self->{'redis'}->hget(
        $self->{'redis_prefix'} . 'githeads', $self->{'branch'});

    return 0 unless defined($head);

    if( not defined($self->{'repo'}) )
    {
        $self->{'repo'} = Git::Raw::Repository->open($self->{'repodir'});
    }

    my $commit = Git::Raw::Commit->lookup($self->{'repo'}, $head);
    die("Cannot lookup commit $head") unless defined($commit);

    $self->{'gittree'} = $commit->tree();

    return 1;
}




sub treeName
{
    my $self = shift;
    return $self->{'treename'};
}



sub nodeName
{
    my $self = shift;
    my $path = shift;
    $path =~ s/.*\/([^\/]+)\/?$/$1/o;
    return $path;
}



sub token
{
    my $self = shift;
    my $path = shift;
    my $nocheck = shift;

    my $token = sha1_hex($self->{'treename'} . ':' . $path);
    if( $nocheck or $self->_node_file_exists($token) )
    {
        return $token;
    }
    else
    {
        return undef;
    }
}

sub path
{
    my $self = shift;
    my $token = shift;

    my $node = $self->_node_read($token);
    return $node->{'path'};
}


sub nodeExists
{
    my $self = shift;
    my $path = shift;

    return defined( $self->token($path) );
}


sub tokenExists
{
    my $self = shift;
    my $token = shift;

    return $self->_node_file_exists($token);
}


sub isLeaf
{
    my $self = shift;
    my $token = shift;

    my $node = $self->_node_read($token);
    return( not $node->{'is_subtree'} );
}


sub isSubtree
{
    my $self = shift;
    my $token = shift;

    my $node = $self->_node_read($token);
    return( $node->{'is_subtree'} );
}


sub isRoot
{
    my $self = shift;
    my $token = shift;

    my $node = $self->_node_read($token);
    return( $node->{'parent'} eq '');
}


sub getOtherParam
{
    my $self = shift;
    my $name = shift;
    my $param = shift;

    my $obj = $self->_other_read($name);

    if( defined($obj) )
    {
        return $obj->{'params'}{$param};
    }
    else
    {
        return undef;
    }
}


sub _read_node_param
{
    my $self = shift;
    my $token = shift;
    my $param = shift;

    my $node = $self->_node_read($token);
    if( defined($node) )
    {
        return $node->{'params'}{$param};
    }
    else
    {
        return undef;
    }
}


sub retrieveNodeParam
{
    my $self = shift;
    my $token = shift;
    my $param = shift;

    # walk up the tree and save the grandparent's value at parent's cache

    my $value;
    my $currtoken = $token;
    my @ancestors;
    my $walked = 0;

    while( not defined($value) and defined($currtoken) )
    {
        $value = $self->_read_node_param( $currtoken, $param );
        if( not defined $value )
        {
            if( $walked )
            {
                push( @ancestors, $currtoken );
            }
            else
            {
                $walked = 1;
            }
            # walk up to the parent
            $currtoken = $self->getParent($currtoken);
        }
    }

    foreach my $ancestor ( @ancestors )
    {
        my $node = $self->{'objcache'}->get($ancestor);
        if( defined($node) )
        {
            $node->{'params'}{$param} = $value;
        }
    }

    return $self->expandNodeParam( $token, $param, $value );
}


sub expandNodeParam
{
    my $self = shift;
    my $token = shift;
    my $param = shift;
    my $value = shift;

    # %parameter_substitutions% in ds-path-* in multigraph leaves
    # are expanded by the Writer post-processing
    if( defined $value and $self->getParamProperty( $param, 'expand' ) )
    {
        $value = $self->expandSubstitutions( $token, $param, $value );
    }
    return $value;
}


sub expandSubstitutions
{
    my $self = shift;
    my $token = shift;
    my $param = shift;
    my $value = shift;

    my $ok = 1;
    my $changed = 1;

    while( $changed and $ok )
    {
        $changed = 0;

        # Substitute definitions
        if( index($value, '$') >= 0 )
        {
            if( not $value =~ /\$(\w+)/o )
            {
                my $path = $self->path($token);
                Error("Incorrect definition reference: $value in $path");
                $ok = 0;
            }
            else
            {
                my $dname = $1;
                my $dvalue = $self->getDefinition($dname);
                if( not defined( $dvalue ) )
                {
                    my $path = $self->path($token);
                    Error("Cannot find definition $dname in $path");
                    $ok = 0;
                }
                else
                {
                    $value =~ s/\$$dname/$dvalue/g;
                    $changed = 1;
                }
            }
        }

        # Substitute parameter references
        if( index($value, '%') >= 0 and $ok )
        {
            if( not $value =~ /\%([a-zA-Z0-9\-_]+)\%/o )
            {
                Error("Incorrect parameter reference: $value");
                $ok = 0;
            }
            else
            {
                my $pname = $1;
                my $pval = $self->getNodeParam( $token, $pname );

                if( not defined( $pval ) )
                {
                    my $path = $self->path($token);
                    Error("Cannot expand parameter reference %".
                          $pname."% in ".$path);
                    $ok = 0;
                }
                else
                {
                    $value =~ s/\%$pname\%/$pval/g;
                    $changed = 1;
                }
            }
        }
    }

    if( ref( $Torrus::ConfigTree::nodeParamHook ) )
    {
        $value = &{$Torrus::ConfigTree::nodeParamHook}( $self, $token,
                                                        $param, $value );
    }

    return $value;
}


sub getNodeParam
{
    my $self = shift;
    my $token = shift;
    my $param = shift;
    my $noclimb = shift;

    my $value;
    if( $noclimb )
    {
        $value = $self->_read_node_param( $token, $param );
        return $self->expandNodeParam( $token, $param, $value );
    }

    if( $self->{'is_writing'} )
    {
        return $self->retrieveNodeParam( $token, $param );
    }

    return $self->retrieveNodeParam( $token, $param );
}




sub getOtherParams
{
    my $self = shift;
    my $name = shift;

    my $obj = $self->_other_read($name);

    if( defined($obj) )
    {
        return $obj->{'params'};
    }
    else
    {
        return {};
    }
}


sub getNodeParams
{
    my $self = shift;
    my $token = shift;

    my $obj = $self->_node_read($token);

    if( defined($obj) )
    {
        return $obj->{'params'};
    }
    else
    {
        return {};
    }
}



sub getParent
{
    my $self = shift;
    my $token = shift;

    my $node = $self->_node_read($token);
    my $parent = $node->{'parent'};
    if( $parent eq '' )
    {
        return undef;
    }
    else
    {
        return $parent;
    }
}


sub getChildren
{
    my $self = shift;
    my $token = shift;

    my $node = $self->_node_read($token);
    if( not $node->{'is_subtree'} )
    {
        return;
    }

    my @ret;
    while( my ($key, $val) = each %{$node->{'children'}} )
    {
        if($val)
        {
            push(@ret, $key);
        }
    }

    return @ret;
}


sub getParamProperty
{
    my $self = shift;
    my $param = shift;
    my $prop = shift;

    return $self->{'paramprop'}{$prop}{$param};
}


sub getParamProperties
{
    my $self = shift;

    return $self->{'paramprop'};
}


#
# Recognizes absolute or relative path, '..' as the parent subtree
#
sub getRelative
{
    my $self = shift;
    my $token = shift;
    my $relPath = shift;

    if( $relPath =~ s/^\[\[(.+)\]\]//o )
    {
        my $nodeid = $1;
        $token = $self->getNodeByNodeid( $nodeid );
        return(undef) unless defined($token);
    }

    if( $relPath =~ /^\//o )
    {
        return $self->token( $relPath );
    }
    else
    {
        if( length( $relPath ) > 0 )
        {
            $token = $self->getParent( $token );
        }

        while( length( $relPath ) > 0 )
        {
            if( $relPath =~ /^\.\.\//o )
            {
                $relPath =~ s/^\.\.\///o;
                if( not $self->isRoot($token) )
                {
                    $token = $self->getParent( $token );
                }
            }
            else
            {
                my $childName;
                $relPath =~ s/^([^\/]*\/?)//o;
                if( defined($1) )
                {
                    $childName = $1;
                }
                else
                {
                    last;
                }
                my $path = $self->path( $token );
                $token = $self->token( $path . $childName );
                if( not defined $token )
                {
                    return undef;
                }
            }
        }
        return $token;
    }
}


sub _nodeid_sha_file
{
    my $self = shift;
    my $nodeid = shift;

    return ('nodeid/' . $self->_sha_file(sha1_hex($nodeid)));
}

sub _nodeidpx_sha_dir
{
    my $self = shift;
    my $prefix = shift;

    return ('nodeidpx/' . $self->_sha_file(sha1_hex($prefix)));
}


sub getNodeByNodeid
{
    my $self = shift;
    my $nodeid = shift;

    my $result = $self->_read_json( $self->_nodeid_sha_file($nodeid) );
    if( defined($result) )
    {
        return $result->[1];
    }
    else
    {
        return undef;
    }
}

# Returns arrayref.
# Each element is an arrayref to [nodeid, token] pair
sub searchNodeidPrefix
{
    my $self = shift;
    my $prefix = shift;

    $prefix =~ s/\/\/$//; # remove trailing separator if any
    my $dir = $self->_nodeidpx_sha_dir($prefix);

    my $tree_entry = $self->{'gittree'}->entry_bypath($dir);
    return undef unless defined($tree_entry);

    my $dir_tree = $tree_entry->object();
    die('Expected a tree object') unless $dir_tree->is_tree();

    my $ret = [];
    foreach my $entry ($dir_tree->entries())
    {
        my $nodeid_sha = $entry->name();
        my $nodeid_entry =
            $self->{'gittree'}->entry_bypath(
                'nodeid/' . $self->_sha_file($nodeid_sha));
        push(@{$ret},
             $self->{'json'}->decode(
                 $nodeid_entry->object()->content()));
    }

    return $ret;
}


# Returns arrayref.
# Each element is an arrayref to [nodeid, token] pair
sub searchNodeidSubstring
{
    my $self = shift;
    my $substring = shift;

    my $top_entry = $self->{'gittree'}->entry_bypath('nodeid');
    die('Cannot find nodeid/ tree entry') unless defined($top_entry);

    my $top_tree = $top_entry->object();
    die('Expected a tree object') unless $top_tree->is_tree();

    my $ret = [];
    foreach my $l1entry ($top_tree->entries())
    {
        my $l1tree = $l1entry->object();
        die('Expected a tree object') unless $l1tree->is_tree();

        foreach my $l2entry ($l1tree->entries())
        {
            my $l2tree = $l2entry->object();
            die('Expected a tree object') unless $l2tree->is_tree();

            foreach my $l3entry ($l2tree->entries())
            {
                my $l3blob = $l3entry->object();
                die('Expected a blob object') unless $l3blob->is_blob();

                my $data = $self->{'json'}->decode($l3blob->content());

                if( index($data->[0], $substring) >= 0 )
                {
                    push(@{$ret}, $data);
                }
            }
        }
    }

    return $ret;
}



sub getDefaultView
{
    my $self = shift;
    my $token = shift;

    my $view;
    if( $self->isTset($token) )
    {
        if( $token eq 'SS' )
        {
            $view = $self->getOtherParam('SS', 'default-tsetlist-view');
        }
        else
        {
            $view = $self->getOtherParam($token, 'default-tset-view');
            if( not defined( $view ) )
            {
                $view = $self->getOtherParam('SS', 'default-tset-view');
            }
        }
    }
    elsif( $self->isSubtree($token) )
    {
        $view = $self->getNodeParam($token, 'default-subtree-view');
    }
    else
    {
        # This must be leaf
        $view = $self->getNodeParam($token, 'default-leaf-view');
    }

    if( not defined( $view ) )
    {
        Error("Cannot find default view for $token");
    }
    return $view;
}


sub getInstanceParam
{
    my $self = shift;
    my $type = shift;
    my $name = shift;
    my $param = shift;

    if( $type eq 'node' )
    {
        return $self->getNodeParam($name, $param);
    }
    else
    {
        return $self->getOtherParam($name, $param);
    }
}


sub _other_object_names
{
    my $self = shift;
    my $filename = shift;

    my @ret;
    my $data = $self->_read_json('other/' . $filename);
    if( defined($data) )
    {
        foreach my $name ( keys %{$data} )
        {
            if( $data->{$name} )
            {
                push(@ret, $name);
            }
        }
    }

    return @ret;
}

sub _other_object_exists
{
    my $self = shift;
    my $filename = shift;
    my $objname = shift;

    my $data = $self->_read_json('other/' . $filename);

    if( defined($data) )
    {
        return $data->{$objname};
    }

    return undef;
}


sub getViewNames
{
    my $self = shift;
    return $self->_other_object_names('__VIEWS__');
}


sub viewExists
{
    my $self = shift;
    my $vname = shift;
    return $self->_other_object_exists('__VIEWS__', $vname);
}


sub getMonitorNames
{
    my $self = shift;
    return $self->_other_object_names('__MONITORS__');
}


sub monitorExists
{
    my $self = shift;
    my $mname = shift;
    return $self->_other_object_exists('__MONITORS__', $mname);
}


sub getActionNames
{
    my $self = shift;
    return $self->_other_object_names('__ACTIONS__');
}


sub actionExists
{
    my $self = shift;
    my $aname = shift;
    return $self->_other_object_exists('__ACTIONS__', $aname);
}



# Token sets manipulation

sub isTset
{
    my $self = shift;
    my $token = shift;
    return substr($token, 0, 1) eq 'S';
}

sub addTset
{
    my $self = shift;
    my $tset = shift;
    $self->{'redis'}->hset($self->{'redis_prefix'} . 'tsets:' .
                           $self->treeName(), $tset, '1');
    return;
}

sub tsetExists
{
    my $self = shift;
    my $tset = shift;
    return $self->{'redis'}->hget($self->{'redis_prefix'} . 'tsets:' .
                                  $self->treeName(), $tset) ? 1:0;
}

sub getTsets
{
    my $self = shift;
    return $self->{'redis'}->hkeys($self->{'redis_prefix'} . 'tsets:' .
                                   $self->treeName());
}

sub tsetMembers
{
    my $self = shift;
    my $tset = shift;

    return $self->{'redis'}->hkeys($self->{'redis_prefix'} . 'tset:' .
                                   $self->treeName() . ':' . $tset);
}

sub tsetMemberOrigin
{
    my $self = shift;
    my $tset = shift;
    my $token = shift;

    return $self->{'redis'}->hget($self->{'redis_prefix'} . 'tset:' .
                                  $self->treeName() . ':' . $tset,
                                  $token);
}

sub tsetAddMember
{
    my $self = shift;
    my $tset = shift;
    my $token = shift;
    my $origin = shift;

    $self->{'redis'}->hget($self->{'redis_prefix'} . 'tset:' .
                           $self->treeName() . ':' . $tset,
                           $token,
                           $origin);
    return;
}


sub tsetDelMember
{
    my $self = shift;
    my $tset = shift;
    my $token = shift;

    $self->{'redis'}->hdel($self->{'redis_prefix'} . 'tset:' .
                           $self->treeName() . ':' . $tset,
                           $token);
    return;
}

# Definitions manipulation

sub getDefinition
{
    my $self = shift;
    my $name = shift;

    return $self->_read_json('definitions/' . $name);
}

sub getDefinitionNames
{
    my $self = shift;

    my @ret;
    my $tree_entry = $self->{'gittree'}->entry_bypath('definitions');
    return undef unless defined($tree_entry);

    my $dir_tree = $tree_entry->object();
    die('Expected a tree object') unless $dir_tree->is_tree();

    foreach my $entry ($dir_tree->entries())
    {
        push(@ret, $entry->name());
    }

    return @ret;
}


sub getSrcFiles
{
    my $self = shift;
    my $token = shift;

    my $node = $self->_node_read($token);
    if( defined($node->{'src'}) )
    {
        return sort keys %{$node->{'src'}};
    }
    else
    {
        return ();
    }
}




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
