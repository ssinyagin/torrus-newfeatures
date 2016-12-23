#  Copyright (C) 2002-2007  Stanislav Sinyagin
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
use Cache::Memcached::Fast;
use Git::Raw;
use JSON;
use File::Path qw(make_path);
use Digest::SHA qw(sha1_hex);
use Cache::Ref::CART;

use Torrus::Log;



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

    $self->{'json'} = JSON->new->canonical(1);

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
                                         $Torrus::ConfigTree::remoteName
                                         $remote_url);
            }
        }
        $self->_unlock_repodir();
    }

    if( not $self->{'iamwriter'} )
    {
        my $head = $self->_branchhead();
        if( not defined($head) )
        {
            # the writer has not yet write to its branch
            return undef;
        }

        if( not $self->gotoHead() )
        {
            # could not retrieve the head commit
            return undef;
        }            
    }

    $self->{'paramprop'} = $self->_read_json('paramprops');
    $self->{'paramprop'} = {} unless defined($self->{'paramprop'});
        
    $self->{'extcache'} =
        new Cache::Memcached::Fast({
            servers => [{ 'address' => $Torrus::Global::memcachedServer,
                          'noreply' => 1 }],
            namespace => $Torrus::Global::memcachedPrefix});

    $self->{'objcache'} = Cache::Ref::CART->new
        ( size => $Torrus::ConfigTree::objCacheSize );
    
    return $self;
}




sub _branchhead
{
    my $self = shift;
    return $self->{'redis'}->hget
        ($self->{'redis_prefix'} . 'githeads', $self->{'branch'});
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


my _read_file
{
    my $self = shift;
    my $filename = shift;

    if( defined($self->{'gitindex'}) )
    {
        my $entry = $self->{'gitindex'}->find($filename);
        if( defined($entry) )
        {
            return $entry->blob();
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


my _read_json
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

    my $head = $self->_branchhead();
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
    return( not $node->{'is_subtree'} );
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

    my $cachekey = 'np:' . $token . ':' . $param;
    my $cacheval = $self->{'extcache'}->get($cachekey);
    if( defined( $cacheval ) )
    {
        my $status = substr( $cacheval, 0, 1 );
        if( $status eq 'U' )
        {
            return undef;
        }
        else
        {
            return substr( $cacheval, 1 );
        }
    }

    $value = $self->retrieveNodeParam( $token, $param );

    if( defined( $value ) )
    {
        $self->{'extcache'}->set( $cachekey, 'D'.$value );
    }
    else
    {
        $self->{'extcache'}->set( $cachekey, 'U' );
    }

    return $value;
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
                if( $token ne $self->token('/') )
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


sub getNodeByNodeid
{
    my $self = shift;
    my $nodeid = shift;

    return $self->{'db_nodeid'}->get( $nodeid );
}

# Returns arrayref or undef.
# Each element is an arrayref to [nodeid, token] pair
sub searchNodeidPrefix
{
    my $self = shift;
    my $prefix = shift;

    return $self->{'db_nodeid'}->searchPrefix( $prefix );
}


# Returns arrayref or undef.
# Each element is an arrayref to [nodeid, token] pair
sub searchNodeidSubstring
{
    my $self = shift;
    my $substring = shift;

    return $self->{'db_nodeid'}->searchSubstring( $substring );
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
            $view = $self->getParam('SS', 'default-tsetlist-view');
        }
        else
        {
            $view = $self->getParam($token, 'default-tset-view');
            if( not defined( $view ) )
            {
                $view = $self->getParam('SS', 'default-tset-view');
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
        return $self->getParam($name, $param);
    }
}


sub getViewNames
{
    my $self = shift;
    return $self->{'db_otherconfig'}->getListItems( 'V:' );
}


sub viewExists
{
    my $self = shift;
    my $vname = shift;
    return $self->searchOtherList('V:', $vname);
}


sub getMonitorNames
{
    my $self = shift;
    return $self->{'db_otherconfig'}->getListItems( 'M:' );
}

sub monitorExists
{
    my $self = shift;
    my $mname = shift;
    return $self->searchOtherList('M:', $mname);
}


sub getActionNames
{
    my $self = shift;
    return $self->{'db_otherconfig'}->getListItems( 'A:' );
}


sub actionExists
{
    my $self = shift;
    my $mname = shift;
    return $self->searchOtherList('A:', $mname);
}


# Search for a value in comma-separated list
sub searchOtherList
{
    my $self = shift;
    my $key = shift;
    my $name = shift;

    return $self->{'db_otherconfig'}->searchList($key, $name);
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
    $self->{'db_sets'}->addToList('S:', $tset);
    return;
}


sub tsetExists
{
    my $self = shift;
    my $tset = shift;
    return $self->{'db_sets'}->searchList('S:', $tset);
}

sub getTsets
{
    my $self = shift;
    return $self->{'db_sets'}->getListItems('S:');
}

sub tsetMembers
{
    my $self = shift;
    my $tset = shift;

    return $self->{'db_sets'}->getListItems('s:'.$tset);
}

sub tsetMemberOrigin
{
    my $self = shift;
    my $tset = shift;
    my $token = shift;
    
    return $self->{'db_sets'}->get('o:'.$tset.':'.$token);
}

sub tsetAddMember
{
    my $self = shift;
    my $tset = shift;
    my $token = shift;
    my $origin = shift;

    $self->{'db_sets'}->addToList('s:'.$tset, $token);
    $self->{'db_sets'}->put('o:'.$tset.':'.$token, $origin);
    return;
}


sub tsetDelMember
{
    my $self = shift;
    my $tset = shift;
    my $token = shift;

    $self->{'db_sets'}->delFromList('s:'.$tset, $token);
    $self->{'db_sets'}->del('o:'.$tset.':'.$token);
    return;
}

# Definitions manipulation

sub getDefinition
{
    my $self = shift;
    my $name = shift;
    return $self->{'db_dsconfig'}->get( 'd:'.$name );
}

sub getDefinitionNames
{
    my $self = shift;
    return $self->{'db_dsconfig'}->getListItems( 'D:' );
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
