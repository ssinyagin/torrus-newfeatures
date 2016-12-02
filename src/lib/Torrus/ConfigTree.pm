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

    my $wd = $self->_configtree_wd_path();
    
    if( $self->{'iamwriter'} )
    {
        if( defined($Torrus::ConfigTree::writerRemoteRepo) )
        {
            $self->{'remote'} = $Torrus::ConfigTree::writerRemoteRepo;
        }
    }
    else
    {
        if( defined($Torrus::ConfigTree::readerRemoteRepo) )
        {
            $self->{'remote'} = $Torrus::ConfigTree::readerRemoteRepo;
        }
        else
        {
            $self->{'remote'} = $self->_configtree_wd_path(1);
        }
    }

    $self-{'wd'} = $wd;
    
    if( not -d $wd )
    {
        $self->_lock_wd();
        if( not -d $wd )
        {
            $self->{'fresh_wd'} = 1;
            if( $self->{'iamwriter'} )
            {
                $self->_init_new_writer_wd
                    ($wd, $self->_configtree_branch_name());
            }
            else
            {
                if( defined($self->_treehead()) )
                {
                    $self->_init_new_reader_wd
                        ($wd, $self->_configtree_branch_name());
                }
                else
                {
                    # the writer has not yet initialized the tree
                    $self->{'config_not_ready'} = 1;
                }
            }
        }
        $self->_unlock_wd();
    }

    # prepare the agent WD for writer
    if( $self->{'iamwriter'} )
    {
        foreach my $agent ('collector', 'monitor')
        {
            my $nInstances =
                Torrus::SiteConfig::agentInstances( $treename, $agent );
            for( my $instance = 0; $instance < $nInstances; $instance++ )
            {
                my $awd = $self->_agent_wd_path($agent, $instance);
                if( not -d $awd )
                {
                    $self->_init_new_writer_wd
                        ($awd, $self->_agent_branch_name($agent, $instance));
                }
            }
        }
    }
    
    if( $self->{'config_not_ready'} )
    {
        return undef;
    }
    
    return $self;
}


sub _configtree_wd_path
{
    my $self = shift;
    my $iswriter = shift;

    $iswriter = $self->{'iamwriter'} unless defined($iswriter);

    if( $iswriter )
    {
        return $Torrus::Global::writerWD . '/' .
            $self->{'treename'} . '/' .
            $Torrus::ConfigTree::writerConfigtreeWDsubdir;
            
    }
    else
    {
        return $Torrus::Global::readerWD . '/' .
            $self->{'treename'} . '/' .
            $Torrus::ConfigTree::readerConfigtreeWDsubdir;
    }
}


sub _agent_instance_name
{
    my $self = shift;
    my $agent = shift;
    my $instance = shift;

    return sprintf('%s_%.4x', $agent, $instance);
}


sub _agent_wd_path
{
    my $self = shift;
    my $agent = shift;
    my $instance = shift;
    my $iswriter = shift;

    $iswriter = $self->{'iamwriter'} unless defined($iswriter);
    
    if( $iswriter )
    {
        return $Torrus::Global::writerWD . '/' .
            $self->{'treename'} . '/' .
            $Torrus::ConfigTree::writerAgentsWDsubdir . '/' .
            $self->_agent_instance_name($agent, $instance);
    }
    else
    {
        return $Torrus::Global::readerWD . '/' .
            $self->{'treename'} . '/' .
            $Torrus::ConfigTree::readerAgentsWDsubdir . '/' .
            $self->_agent_instance_name($agent, $instance);
    }
}


sub _configtree_branch_name
{
    my $self = shift;
    return $self->{'treename'} . '_configtree';
}


sub _agent_branch_name
{
    my $self = shift;
    my $agent = shift;
    my $instance = shift;
    
    return $self->{'treename'} . '_' .
        $self->_agent_instance_name($agent, $instance);
}
    

sub _signature
{
    return Git::Raw::Signature->now
        ($Torrus::ConfigTree::writerAuthorName,
         $Torrus::ConfigTree::writerAuthorEmail);
}



sub _init_new_writer_wd
{
    my $self = shift;
    my $dir = shift;
    my $branchname = shift;
    
    Debug("Initializing a writer working directory in $dir");
    make_path($dir) or die("Cannot create $dir: $!");
    
    if( defined($self->{'remote'}) )
    {
        # first, try to check out an existing branch
        Debug('Trying to clone branch ' . $branchname .
              ' from ' . $self->{'remote'});
        eval {
            Git::Raw::Repository->clone
                ($self->{'remote'}, $dir,
                 {'checkout_branch' => $self->{'remote_branch'}});
            Debug('OK');
        };
        
        if( not $@ )
        {
            return;
        }
        Debug('Could not clone: ' . $@);
    }
            
    Debug("Creating an empty repo in $dir");
    my $repo = Git::Raw::Repository->init($dir);
    
    my $index = $repo->index;
    $index->write;
    my $tree = $index->write_tree;
    my $me = $self->_signature();
    
    $repo->commit('Initial empty commit', $me, $me, [], $tree);

    my $branch = Git::Raw::Branch->lookup($repo, 'master', 1);
    $branch->move($branchname, 1);
    

    if( defined($self->{'remote'}) )
    {
        Debug('Adding a remote for pushing: ' . $self->{'remote'}); 
        my $remote =
            Git::Raw::Remote->create($repo, 'origin', $self->{'remote'});

        $remote->push(['refs/heads/master:refs/heads/' . $branchname]);
        my $br = Git::Raw::Branch->lookup( $repo, 'master', 1 );
        my $ref = Git::Raw::Reference->lookup
            ('refs/remotes/origin/' $branchname, $repo);
        $br->upstream($ref);
    }                
    
    return;
}



sub _init_new_reader_wd
{
    my $self = shift;
    my $dir = shift;
    my $branchname = shift;

    Debug("Setting up a reader working directory in $dir");
    Debug('Cloning branch ' . $branchname . 'from ' . $self->{'remote'});
    
    Git::Raw::Repository->clone
        ($self->{'remote'}, $dir, {'checkout_branch' => $branchname});

    return;
}


sub _treehead
{
    my $self = shift;

    return $self->{'redis'}->get
        ($self->{'redis_prefix'} . 'treehead:' . $self->treeName());
}



sub _lock_wd
{
    my $self = shift;
    my $dir = shift;

    if( not defined($self->{'wd_rd'}) )
    {
        $self->{'wd_rd'} = Redis::DistLock->new
            ( servers => [$Torrus::Global::redisServer] );
    }
    
    Debug('Acquiring a lock for ' . $dir);
    my $lock =
        $self->{'wd_rd'}->lock($self->{'redis_prefix'} . 'wdlock:' . $dir,
                               7200);
    if( not defined($lock) )
    {
        die('Failed to acquire a lock for ' . $dir);
    }
    
    $self->{'wd_mutex'} = $lock;
    return;
}


sub _unlock_wd
{
    my $self = shift;
    $self->{'wd_rd'}->release($self->{'wd_mutex'});
    delete $self->{'wd_mutex'};        
    return;
}
            
                             


# This should be called after Torrus::TimeStamp::init();

sub getTimestamp
{
    die('getTimestamp is deprecated');
}

sub treeName
{
    my $self = shift;
    return $self->{'treename'};
}


# Returns array with path components

sub splitPath
{
    my $self = shift;
    my $path = shift;
    my @ret = ();
    while( length($path) > 0 )
    {
        my $node;
        $path =~ s/^([^\/]*\/?)//o;
        if( defined($1) )
        {
            $node = $1;
            push(@ret, $node);
        }
        else
        {
            last;
        }
    }
    return @ret;
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

    my $token = $self->{'db_dsconfig'}->get( 'pt:'.$path );
    if( not defined( $token ) )
    {
        my $prefixLen = 1; # the leading slash is anyway there
        my $pathLen = length( $path );
        while( not defined( $token ) and $prefixLen < $pathLen )
        {
            my $result = $self->{'db_aliases'}->getBestMatch( $path );
            if( not defined( $result ) )
            {
                $prefixLen = $pathLen; # exit the loop
            }
            else
            {
                # Found a partial match
                $prefixLen = length( $result->{'key'} );
                my $aliasTarget = $self->path( $result->{'value'} );
                $path = $aliasTarget . substr( $path, $prefixLen );
                $token = $self->{'db_dsconfig'}->get( 'pt:'.$path );
            }
        }
    }
    return $token;
}

sub path
{
    my $self = shift;
    my $token = shift;
    return $self->{'db_dsconfig'}->get( 'tp:'.$token );
}

sub nodeExists
{
    my $self = shift;
    my $path = shift;

    return defined( $self->{'db_dsconfig'}->get( 'pt:'.$path ) );
}


sub nodeType
{
    my $self = shift;
    my $token = shift;

    my $type = $self->{'nodetype_cache'}{$token};
    if( not defined( $type ) )
    {
        $type = $self->{'db_dsconfig'}->get( 'n:'.$token );
        if( not defined( $type ) )
        {
            $type = -1;
        }
        $self->{'nodetype_cache'}{$token} = $type;
    }
    return $type;
}
    

sub isLeaf
{
    my $self = shift;
    my $token = shift;

    return ( $self->nodeType($token) == 1 );
}


sub isSubtree
{
    my $self = shift;
    my $token = shift;

    return( $self->nodeType($token) == 0 );
}

# Returns the real token or undef
sub isAlias
{
    my $self = shift;
    my $token = shift;

    return( ( $self->nodeType($token) == 2 ) ?
            $self->{'db_dsconfig'}->get( 'a:'.$token ) : undef );
}

# Returns the list of tokens pointing to this one as an alias
sub getAliases
{
    my $self = shift;
    my $token = shift;

    return $self->{'db_dsconfig'}->getListItems('ar:'.$token);
}


sub getParam
{
    my $self = shift;
    my $name = shift;
    my $param = shift;
    my $fromDS = shift;

    if( exists( $self->{'paramcache'}{$name}{$param} ) )
    {
        return $self->{'paramcache'}{$name}{$param};
    }
    else
    {
        my $db = $fromDS ? $self->{'db_dsconfig'} : $self->{'db_otherconfig'};
        my $val = $db->get( 'P:'.$name.':'.$param );
        $self->{'paramcache'}{$name}{$param} = $val;
        return $val;
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
        $value = $self->getParam( $currtoken, $param, 1 );
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
        $self->{'paramcache'}{$ancestor}{$param} = $value;
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
        $value = $self->getParam( $token, $param, 1 );
        return $self->expandNodeParam( $token, $param, $value );
    }

    if( $self->{'is_writing'} )
    {
        return $self->retrieveNodeParam( $token, $param );
    }

    my $cachekey = $token.':'.$param;
    my $cacheval = $self->{'db_nodepcache'}->get( $cachekey );
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
        $self->{'db_nodepcache'}->put( $cachekey, 'D'.$value );
    }
    else
    {
        $self->{'db_nodepcache'}->put( $cachekey, 'U' );
    }

    return $value;
}


sub getParamNames
{
    my $self = shift;
    my $name = shift;
    my $fromDS = shift;

    my $db = $fromDS ? $self->{'db_dsconfig'} : $self->{'db_otherconfig'};

    return $db->getListItems('Pl:'.$name);
}


sub getParams
{
    my $self = shift;
    my $name = shift;
    my $fromDS = shift;

    my $ret = {};
    foreach my $param ( $self->getParamNames( $name, $fromDS ) )
    {
        $ret->{$param} = $self->getParam( $name, $param, $fromDS );
    }
    return $ret;
}

sub getParent
{
    my $self = shift;
    my $token = shift;
    if( exists( $self->{'parentcache'}{$token} ) )
    {
        return $self->{'parentcache'}{$token};
    }
    else
    {
        my $parent = $self->{'db_dsconfig'}->get( 'p:'.$token );
        $self->{'parentcache'}{$token} = $parent;
        return $parent;
    }
}


sub getChildren
{
    my $self = shift;
    my $token = shift;

    if( (my $alias = $self->isAlias($token)) )
    {
        return $self->getChildren($alias);
    }
    else
    {
        return $self->{'db_dsconfig'}->getListItems( 'c:'.$token );
    }
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

# Recognize the regexp patterns within a path,
# like /Netflow/Exporters/.*/.*/bps.
# Each pattern is applied against direct child names only.
#
sub getNodesByPattern
{
    my $self = shift;
    my $pattern = shift;

    if( $pattern !~ /^\//o )
    {
        Error("Incorrect pattern: $pattern");
        return undef;
    }

    my @retlist = ();
    foreach my $nodepattern ( $self->splitPath($pattern) )
    {
        my @next_retlist = ();

        # Cut the trailing slash, if any
        my $patternname = $nodepattern;
        $patternname =~ s/\/$//o;

        if( $patternname =~ /\W/o )
        {
            foreach my $candidate ( @retlist )
            {
                # This is a pattern, let's get all matching children
                foreach my $child ( $self->getChildren( $candidate ) )
                {
                    # Cut the trailing slash and leading path
                    my $childname = $self->path($child);
                    $childname =~ s/\/$//o;
                    $childname =~ s/.*\/([^\/]+)$/$1/o;
                    if( $childname =~ $patternname )
                    {
                        push( @next_retlist, $child );
                    }
                }
            }

        }
        elsif( length($patternname) == 0 )
        {
            @next_retlist = ( $self->token('/') );
        }
        else
        {
            foreach my $candidate ( @retlist )
            {
                my $proposal = $self->path($candidate).$nodepattern;
                if( defined( my $proptoken = $self->token($proposal) ) )
                {
                    push( @next_retlist, $proptoken );
                }
            }
        }
        @retlist = @next_retlist;
    }
    return @retlist;
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
