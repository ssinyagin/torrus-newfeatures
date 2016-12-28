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

#
# Write access for ConfigTree
#

package Torrus::ConfigTree::Writer;

use strict;
use warnings;

use base 'Torrus::ConfigTree';

use Torrus::Log;
use Torrus::Collector;
use Torrus::SiteConfig;
use Torrus::ServiceID;
    
use Digest::MD5 qw(md5); # needed as hash function
use POSIX; # we use ceil() from here
use Digest::SHA qw(sha1_hex);

our %multigraph_remove_space =
    ('ds-expr-' => 1,
     'graph-legend-' => 0);


# instance of Torrus::ServiceID object, if needed
my $srvIdParams;

# tree names where we initialized service IDs
my %srvIdInitialized;


sub new
{
    my $proto = shift;
    my %options = @_;
    my $class = ref($proto) || $proto;
    $options{'-WriteAccess'} = 1;
    my $self  = $class->SUPER::new( %options );
    if( not defined( $self ) )
    {
        return undef;
    }
    
    bless $self, $class;

    my $repo = $self->{'repo'} =
        Git::Raw::Repository->open($self->{'repodir'});
    
    my $branchname = $self->{'branch'};
    my $branch = Git::Raw::Branch->lookup($repo, $branchname, 1);

    if( not defined($branch) )
    {
        # This is a fresh repo, create the configtree branch
        my $builder = Git::Raw::Tree::Builder->new($repo);
        $builder->clear();
        my $tree = $builder->write();
        my $me = $self->_signature();
        my $refname = 'refs/heads/' / $branchname;
        my $commit = $repo->commit("Initial empty commit in $branchname" ,
                                   $me, $me, [], $tree, $refname);
    
        $branch = $repo->branch($branchname, $commit);
    }

    $self->{'previous_commit'} = $branch->peel('commit');
    
    my $index = Git::Raw::Index->new();
    $repo->index($index);

    # This points to the last commit, and we're writing a new tree with the
    # help of index
    delete $self->{'gittree'};

    my $tree = $branch->peel('tree');
    $index->read_tree($tree);
    $self->{'gitindex'} = $index;
    
    $self->{'viewparent'} = {};
    $self->{'mayRunCollector'} =
        Torrus::SiteConfig::mayRunCollector( $self->treeName() );

    $self->{'collectorInstances'} =
        Torrus::SiteConfig::agentInstances( $self->treeName(), 'collector' );

    $self->{'is_writing'} = 1;
    
    return $self;
}


sub DESTROY
{
    my $self = shift;
    
}

sub _signature
{
    return Git::Raw::Signature->now
        ($Torrus::ConfigTree::writerAuthorName,
         $Torrus::ConfigTree::writerAuthorEmail);
}


sub _node_read
{
    my $self = shift;
    my $token = shift;

    my $ret;
    if( defined($self->{'editing_node'}) and $token eq $self->{'editing_node'} )
    {
        $ret = $self->{'editing'};
    }
    else
    {
        $ret = $self->SUPER::_node_read($token);
    }

    if( defined($ret) )
    {
        foreach my $name (keys %{$ret->{'vars'}})
        {
            $self->{'setvar'}{$token}{$name} = $ret->{'vars'}{$name};
        }
    }

    return $ret;
}


sub _agent_instance_name
{
    my $self = shift;
    my $agent = shift;
    my $instance = shift;

    return sprintf('%s_%.4x', $agent, $instance);
}


sub _agent_branch_name
{
    my $self = shift;
    my $agent = shift;
    my $instance = shift;
    
    return $self->{'treename'} . '_' .
        $self->_agent_instance_name($agent, $instance);
}


sub _write_json
{
    my $self = shift;
    my $filename = shift;
    my $data = shift;
    
    $self->{'gitindex'}->add_frombuffer
        ($filename, $self->{'json'}->encode($data));
    return;
}


sub startEditingOthers
{
    my $self  = shift;
    my $filename  = shift;

    $self->{'others_list_file'} = $filename;
    $self->{'others_list'} = $self->_read_json('other/' . $filename);
}


sub addOtherObject
{
    my $self  = shift;
    my $name  = shift;

    if( not defined($self->{'others_list_file'}) )
    {
        die('startEditingOthers() was not called');
    }

    $self->{'others_list'}{$name} = 1;
    $self->editOther($name);
    return;
}
    

sub endEditingOthers
{
    my $self  = shift;

    $self->_write_json('other/' . $filename, $self->{'others_list'});
    return;
}
    

sub editOther
{
    my $self  = shift;
    my $name  = shift;

    if( defined($self->{'editing'}) )
    {
        die('another object is being edited');
    }

    my $obj = $self->_other_read($name);
    if( not defined($obj) )
    {
        $obj = {'params' => {}};
    }
    
    $self->{'editing'} = $obj;
    $self->{'editing_name'} = $name;
    
    return;
}


sub setOtherParam
{
    my $self  = shift;
    my $param = shift;
    my $value = shift;

    if( $self->getParamProperty( $param, 'remspace' ) )
    {
        $value =~ s/\s+//go;
    }

    my $oldval = $self->{'editing'}{'params'}{$param};
    if( not defined($oldval) or $oldval ne $value )
    {
        $self->{'editing'}{'params'}{$param} = $value;
        $self->{'editing_dirty'} = 1;
    }
    
    return;
}

sub commitOther
{
    my $self  = shift;
    
    if( not defined($self->{'editing'}) )
    {
        die('setOtherParam() called before editOther()');
    }
    if( not defined($self->{'editing_name'}) )
    {
        die('a node object is being edited');
    }

    if( $self->{'editing_dirty'} )
    {
        $self->_write_json('other/' . $self->{'editing_name'},
                           $self->{'editing'});
    }

    delete $self->{'editing'};
    delete $self->{'editing_name'};
    delete $self->{'editing_dirty'};
}


# editNode can be called more than once on the same node, so we do
# nothing in this case.
# If it's called for a different node, we commit the previous one.

sub editNode
{
    my $self  = shift;
    my $path  = shift;

    my $token = $self->token($path, 1);
    
    if( defined($self->{'editing'}) )
    {
        if( $self->{'editing_node'} eq $token )
        {
            return $token;
        }
        else
        {
            $self->commitNode();
        }
    }

    my $is_subtree = ($path =~ /\/$/) ? 1:0;
    my $parent_token;
    
    my $slashpos = rindex($path, '/');
    if( $slashpos > 0 )
    {
        my $parent_path = substr($path, 0, $slashpos+1);
        $parent_token = $self->token($parent_path, 1);
        my $parent_node = $self->_node_read($parent_token);
        
        if( not defined($parent_node) or
            not $parent_node->{'children'}->{$token} )
        {
            $self->editNode($parentpath);
            $self->_add_child_token($token);
            $self->commitNode();
        }
    }
    else
    {
        $parent_token = '';
    }

    my $node = $self->_node_read($token);
    if( not defined($node) )
    {
        $node = {
            'is_subtree' => $is_subtree,
            'parent' => $parent_node,
            'path' => $path,
            'params' => {},
            'vars' => {},
        };
        
        if( $is_subtree )
        {
            $node->{'children'} = {};
        }
    }
    
    $self->{'editing'} = $node;
    $self->{'editing_node'} = $token;
    
    return $token;
}



sub setNodeParam
{
    my $self  = shift;
    my $name  = shift;
    my $param = shift;
    my $value = shift;

    if( $self->getParamProperty( $param, 'remspace' ) )
    {
        $value =~ s/\s+//go;
    }

    my $oldval = $self->{'editing'}{'params'}{$param};
    if( not defined($oldval) or $oldval ne $value )
    {
        $self->{'editing'}{'params'}{$param} = $value;
        $self->{'editing_dirty'} = 1;
    }
    
    return;
}


sub _add_child_token
{
    my $self  = shift;
    my $ctoken  = shift;

    if( not $self->{'editing'}{'is_subtree'} )
    {
        die($self->{'editing'}{'path'} . ' (' . $ctoken . ' is not a subtree');
    }

    if( not $self->{'editing'}{'children'}{$ctoken} )
    {
        $self->{'editing'}{'children'}{$ctoken} = 1;
        $self->{'editing_dirty_children'} = 1;
    }
    return;
}
        


sub setVar
{
    my $self = shift;
    my $token = shift;
    my $name = shift;
    my $value = shift;
    
    $self->{'setvar'}{$token}{$name} = $value;

    my $oldval = $self->{'editing'}{'vars'}{$name};
    if( not defined($oldval) or $oldval ne $value )
    {
        $self->{'editing'}{'vars'}{$name} = $value;
        $self->{'editing_dirty'} = 1;
    }

    return;
}


sub commitNode
{
    my $self  = shift;
    
    if( not defined($self->{'editing'}) )
    {
        die('setOtherParam() called before editOther()');
    }
    if( not defined($self->{'editing_node'}) )
    {
        die('an object being edited is not a node');
    }

    my $sha_file = $self->_sha_file($self->{'editing_node'});
    
    if( $self->{'editing_dirty'} )
    {
        my $data = {
            'is_subtree' => $self->{'editing'}{'is_subtree'},
            'parent' => $self->{'editing'}{'parent'},
            'path' => $self->{'editing'}{'path'},
            'params' => $self->{'editing'}{'params'},
            'vars' => $self->{'editing'}{'vars'},
        };

        $self->_write_json('nodes/' . $sha_file, $data);
    }

    if( $self->{'editing_dirty_children'} )
    {
        $self->_write_json('children/' . $sha_file,
                           $self->{'editing'}{'children'});
    }
    
    delete $self->{'editing'};
    delete $self->{'editing_node'};
    delete $self->{'editing_dirty'};
    delete $self->{'editing_dirty_children'};
    return;
}




sub setParamProperty
{
    my $self = shift;
    my $param = shift;
    my $prop = shift;
    my $value = shift;

    $self->{'paramprop'}{$prop}{$param} = $value;
    return;
}



sub initRoot
{
    my $self  = shift;

    if( not $self->{'init_root_done'} )
    {
        my $token = $self->editNode('/');
        $self->setNodeParam($token, 'tree-name', $self->treeName());
        $self->commitNode();
        $self->{'init_root_done'} = 1;
    }
    return;
}




sub addView
{
    my $self = shift;
    my $vname = shift;
    my $parent = shift;

    if( defined( $parent ) )
    {
        $self->{'viewparent'}{$vname} = $parent;
    }

    $self->addOtherObject($vname);
    return;
}



sub addDefinition
{
    my $self = shift;
    my $name = shift;
    my $value = shift;

    $self->_write_json('definitions/' . $name, $value);
    return;
}




sub isTrueVar
{
    my $self = shift;
    my $token = shift;
    my $name = shift;

    my $ret = 0;
    
    while( $token ne '' and
           not defined($self->{'setvar'}{$token}{$name}) )
    {
        my $node = $self->_node_read($token);
        $token = $node->{'parent'};
    }
    
    if( $token ne '' )
    {
        my $value = $self->{'setvar'}{$token}{$name};
        if( defined($value) )
        {
            if( $value eq 'true' or
                $value =~ /^\d+$/o and $value )
            {
                $ret = 1;
            }
        }
    }
    
    return $ret;
}





sub commitConfig
{
    my $self = shift;

    my $ok = $self->_post_process_nodes();
    return($ok) unless $ok;
    
    # Propagate view inherited parameters
    $self->{'viewParamsProcessed'} = {};
    foreach my $vname ( $self->getViewNames() )
    {
        $self->_propagate_view_params( $vname );
    }

    $self->_write_json('paramprops', $self->{'paramprop'});

    Debug('Writing a commit in branch: ' . $self->{'branch'});
    my $branchname = $self->{'branch'};
    my $branch = Git::Raw::Branch->lookup($self->{'repo'}, $branchname, 1);
    my $parent = $branch->peel('commit');
    
    my $me = $self->_signature();
    
    my $tree = $self->{'gitindex'}->write_tree();
    
    my $commit = $self->{'repo'}->commit
        (scalar(localtime(time())),
         $me, $me, [$parent], $tree, $branch->name());

    $self->{'new_commit'} = $commit->id();
    Debug('Wrote ' . $commit->id());

    delete $self->{'gitindex'};
    # release the index memory, as it may be quite large
    my $index = Git::Raw::Index->new();
    $self->{'repo'}->index($index);

    $self->_init_extcache($commit);

    $self->{'is_writing'} = undef;

    # clean up tokenset members if their nodes were removed
    foreach my $ts ( $self->getTsets() )
    {
        foreach my $member ( $self->tsetMembers($ts) )
        {
            if( not $self->tokenExists($member) )
            {
                $self->tsetDelMember($ts, $member);
            }
        }
    }

    return $ok;
}



sub _post_process_nodes
{
    my $self = shift;
    my $token = shift;

    my $ok = 1;

    if( not defined( $token ) )
    {
        $token = $self->token('/');
    }

    my $path = $self->path($token);
    
    my $nodeid = $self->getNodeParam( $token, 'nodeid', 1 );
    if( defined( $nodeid ) )
    {
        # verify the uniqueness of nodeid

        my $nodeid_sha = sha1_hex($nodeid);
        my $sha_file = 'nodeid/' . $self->_sha_file($nodeid_sha);
        my $old_entry = $self->_read_json($sha_file);
        if( defined($old_entry) )
        {
            if( $old_entry->[1] ne $token )
            {
                Error('Non-unique nodeid ' . $nodeid .
                      ' in ' . $path .
                      ' and ' . $self->path($old_entry->[1]));
                $ok = 0;
            }
        }
        else
        {
            $self->_write_json($sha_file, [$nodeid, $token]);

            my $pos = 0;
            while( ($pos = index($nodeid, '//', $pos)) >= 0 )
            {
                my $prefix = substr($nodeid, 0, $pos);
                my $dir = $self->_nodeidpx_sha_dir($prefix);
                $self->{'gitindex'}->add_frombuffer(
                    $dir . '/' . $nodeid_sha, '');
            }
        }
    }

    
    if( $self->isLeaf($token) )
    {
        # Process static tokenset members

        my $tsets = $self->getNodeParam($token, 'tokenset-member');
        if( defined( $tsets ) )
        {
            foreach my $tset ( split(/,/o, $tsets) )
            {
                my $tsetName = 'S'.$tset;
                if( not $self->tsetExists($tsetName) )
                {
                    Error("Referenced undefined tokenset $tset in $path");
                    $ok = 0;
                }
                else
                {
                    $self->tsetAddMember( $tsetName, $token, 'static' );
                }
            }
        }

        my $dsType = $self->getNodeParam( $token, 'ds-type' );
        if( defined( $dsType ) )
        {
            if( $dsType eq 'rrd-multigraph' )
            {
                # Expand parameter substitutions in multigraph leaves

                $self->editNode($path);

                my @dsNames =
                    split(/,/o, $self->getNodeParam($token, 'ds-names') );
                
                foreach my $dname ( @dsNames )
                {
                    foreach my $param ( 'ds-expr-', 'graph-legend-' )
                    {
                        my $dsParam = $param . $dname;
                        my $value = $self->getNodeParam( $token, $dsParam );
                        if( defined( $value ) )
                        {
                            my $newValue = $value;
                            if( $multigraph_remove_space{$param} )
                            {
                                $newValue =~ s/\s+//go;
                            }
                            $newValue =
                                $self->expandSubstitutions( $token, $dsParam,
                                                            $newValue );
                            if( $newValue ne $value )
                            {
                                $self->setNodeParam( $token, $dsParam,
                                                     $newValue );
                            }
                        }
                    }
                }

                $self->commitNode();
            }
            elsif( $dsType eq 'collector' )
            {
                $self->editNode($path);

                # Split the collecting job between collector instances
                my $instance = 0;
                my $nInstances = $self->{'collectorInstances'};

                my $oldOffset =
                    $self->getNodeParam($token, 'collector-timeoffset');
                my $newOffset = $oldOffset;
                
                my $period =
                    $self->getNodeParam($token, 'collector-period');
                
                if( $nInstances > 1 )
                {
                    my $hashString =
                        $self->getNodeParam($token,
                                            'collector-instance-hashstring');
                    if( not defined( $hashString ) )
                    {
                        Error('collector-instance-hashstring is not defined ' .
                              'in ' . $self->path( $token ));
                        $hashString = '';
                    }
                    
                    $instance =
                        unpack( 'N', md5( $hashString ) ) % $nInstances;
                }          

                $self->setNodeParam( $token,
                                     'collector-instance',
                                     $instance );
                
                my $dispersed =
                    $self->getNodeParam($token,
                                        'collector-dispersed-timeoffset');
                if( defined( $dispersed ) and $dispersed eq 'yes' )
                {
                    # Process dispersed collector offsets
                    
                    my %p;
                    foreach my $param ( 'collector-timeoffset-min',
                                        'collector-timeoffset-max',
                                        'collector-timeoffset-step',
                                        'collector-timeoffset-hashstring' )
                    {
                        my $val = $self->getNodeParam( $token, $param );
                        if( not defined( $val ) )
                        {
                            Error('Mandatory parameter ' . $param . ' is not '.
                                  ' defined in ' . $self->path( $token ));
                            $ok = 0;
                        }
                        else
                        {
                            $p{$param} = $val;
                        }
                    }

                    if( $ok )
                    {
                        my $min = $p{'collector-timeoffset-min'};
                        my $max = $p{'collector-timeoffset-max'};
                        if( $max < $min )
                        {
                            Error('collector-timeoffset-max is less than ' .
                                  'collector-timeoffset-min in ' .
                                  $self->path( $token ));
                            $ok = 0;
                        }
                        else
                        {
                            my $step = $p{'collector-timeoffset-step'};
                            my $hashString =
                                $p{'collector-timeoffset-hashstring'};
                            
                            my $bucketSize = ceil(($max-$min)/$step);
                            $newOffset =
                                $min
                                +
                                $step * ( unpack('N', md5($hashString)) %
                                          $bucketSize )
                                +
                                $instance * ceil($step/$nInstances);
                        }
                    }
                }
                else
                {
                    $newOffset += $instance * ceil($period/$nInstances); 
                } 

                $newOffset %= $period;
                
                if( $newOffset != $oldOffset )
                {
                    $self->setNodeParam( $token,
                                         'collector-timeoffset',
                                         $newOffset );
                }

                my $storagetypes =
                    $self->getNodeParam( $token, 'storage-type' );
                foreach my $stype ( split(/,/o, $storagetypes) )
                {
                    if( $stype eq 'ext' )
                    {
                        if( not defined( $srvIdParams ) )
                        {
                            $srvIdParams =
                                new Torrus::ServiceID( -WriteAccess => 1 );
                        }

                        my $srvTrees =
                            $self->getNodeParam($token, 'ext-service-trees');

                        if( not defined( $srvTrees ) or
                            length( $srvTrees ) == 0 )
                        {
                            $srvTrees = $self->treeName();
                        }
                                                
                        my $serviceid =
                            $self->getNodeParam($token, 'ext-service-id');

                        foreach my $srvTree (split(/\s*,\s*/o, $srvTrees))
                        {
                            if( not Torrus::SiteConfig::treeExists($srvTree) )
                            {
                                Error
                                    ('Error processing ext-service-trees' .
                                     'for ' . $self->path( $token ) .
                                     ': tree ' . $srvTree .
                                     ' does not exist');
                                $ok = 0;
                            }
                            else
                            {
                                if( not $srvIdInitialized{$srvTree} )
                                {
                                    $srvIdParams->cleanAllForTree
                                        ( $srvTree );
                                    $srvIdInitialized{$srvTree} = 1;
                                }
                                else
                                {
                                    if( $srvIdParams->idExists( $serviceid,
                                                                $srvTree ) )
                                    {
                                        Error('Duplicate ServiceID: ' .
                                              $serviceid . ' in tree ' .
                                              $srvTree);
                                        $ok = 0;
                                    }
                                }
                            }
                        }

                        if( $ok )
                        {
                            # sorry for ackward Emacs auto-indent
                            my $params = {
                                'trees' => $srvTrees,
                                'token' => $token,
                                'dstype' =>
                                    $self->getNodeParam($token,
                                                        'ext-dstype'),
                                    'units' =>
                                    $self->getNodeParam
                                    ($token, 'ext-service-units')
                                };
                            
                            $srvIdParams->add( $serviceid, $params );
                        }
                    }
                }
                
                $self->commitNode();
            }
        }
        else
        {
            Error("Mandatory parameter 'ds-type' is not defined for $path");
            $ok = 0;
        }            
    }
    else
    {
        foreach my $ctoken ( $self->getChildren($token) )
        {
            $ok = $self->_post_process_nodes( $ctoken ) ? $ok:0;
        }
    }
    
    return $ok;
}


sub _propagate_view_params
{
    my $self = shift;
    my $vname = shift;

    # Avoid processing the same view twice
    if( $self->{'viewParamsProcessed'}{$vname} )
    {
        return;
    }

    # First we do the same for parent
    my $parent = $self->{'viewparent'}{$vname};
    if( defined( $parent ) )
    {
        $self->_propagate_view_params( $parent );

        my $parentParams = $self->getParams( $parent );
        foreach my $param ( keys %{$parentParams} )
        {
            if( not defined( $self->getOtherParam( $vname, $param ) ) )
            {
                $self->setOtherParam( $vname, $param, $parentParams->{$param} );
            }
        }
    }

    # mark this view as processed
    $self->{'viewParamsProcessed'}{$vname} = 1;
    return;
}


sub validate
{
    my $self = shift;

    my $ok = 1;

    if( not $self->{'-NoDSRebuild'} )
    {
        $ok = Torrus::ConfigTree::Validator::validateNodes($self);
    }
    $ok = Torrus::ConfigTree::Validator::validateViews($self) ? $ok:0;
    $ok = Torrus::ConfigTree::Validator::validateMonitors($self) ? $ok:0;
    $ok = Torrus::ConfigTree::Validator::validateTokensets($self) ? $ok:0;

    return $ok;
}


sub finalize
{
    my $self = shift;
    my $status = shift;

    if( $status )
    {
        $self->{'redis'}->hset
            ($self->{'redis_prefix'} . 'githeads',
             $self->{'branch'},
             $self->{'new_commit'});

        $self->{'redis'}->pub
            ($self->{'redis_prefix'} . 'treecommits:' . $self->treeName(),
             $self->{'new_commit'});
                
        Verbose('Configuration has compiled successfully');
    }
    return;
}


sub updateAgentConfigs
{
    my $self = shift;

    my $repos = {};
    my @reponames;

    foreach my $instance ( 0 .. ($self->{'collectorInstances'} - 1) )
    {
        push(@branchnames, $self->_agent_branch_name('collector', $instance));
    }

    push(@branchnames, $self->_agent_branch_name('monitor', 0));

    # open repo objects for every agent branch, and initialize in-memory
    # indexes for writing
    
    foreach my $branchname (@branchnames)
    {
        my $repo = Git::Raw::Repository->open($self->{'repodir'});

        my $branch = Git::Raw::Branch->lookup($repo, $branchname, 1);
        if( not defined($branch) )
        {
            Debug("Creating a new branch $branchname");
            # This is a fresh repo, create the agent branch
            my $builder = Git::Raw::Tree::Builder->new($repo);
            $builder->clear();
            my $tree = $builder->write();
            my $me = $self->_signature();
            my $refname = 'refs/heads/' / $branchname;
            my $commit = $repo->commit("Initial empty commit in $branchname" ,
                                       $me, $me, [], $tree, $refname);
            
            $branch = $repo->branch($branchname, $commit);
        }
        
        my $index = Git::Raw::Index->new();
        $repo->index($index);
        
        my $tree = $branch->peel('tree');
        $index->read_tree($tree);

        $repos->{$branchname} = $repo;
    }

    Debug('Collecting node parameters and poulating indexes');
    $self->_walk_nodes_for_agent_configs($repos, undef);

    foreach my $branchname (@branchnames)
    {
        Debug("Writing a commit in $branchname");
        
        my $repo = $repos->{$branchname};
        my $branch = Git::Raw::Branch->lookup($repo, $branchname, 1);
        my $parent = $branch->peel('commit');
        my $me = $self->_signature();

        my $tree = $repo->index()->write_tree();
    
        my $commit = $repo->commit
            (scalar(localtime(time())),
             $me, $me, [$parent], $tree, $branch->name());

        Debug('Wrote ' . $commit->id());

        $self->{'redis'}->hset
            ($self->{'redis_prefix'} . 'githeads',
             $branchname,
             $commit->id());
    }
    
    return;
}
    
sub _write_agent_params
{
    my $self = shift;
    my $repos = shift;
    my $token = shift;
    my $agent = shift;
    my $instance = shift;
    my $params = shift;

    my $index =
        $repos->{$self->_agent_branch_name($agent, $instance)}->index();

    $index->add_frombuffer($self->_sha_file($token),
                           $self->{'json'}->encode($params));
    return;
}

    

sub _walk_nodes_for_agent_configs
{
    my $self = shift;
    my $repos = shift;
    my $token = shift;

    if( not defined( $token ) )
    {
        $token = $self->token('/');
    }

    if( $self->isLeaf($token) )
    {
        my $dsType = $self->getNodeParam($token, 'ds-type');
        if( $dsType eq 'collector' )
        {
            my $instance = $self->getNodeParam($token, 'collector-instance');
            
            my $params = {};
            foreach my $param (
                'collector-timeoffset',
                'collector-period',
                'collector-type',
                'storage-type',
                'transform-value',
                'collector-scale',
                'value-map')
            {
                my $val = $self->getNodeParam($token, $param);
                if( defined($val) )
                {
                    $params->{$param} = $val;
                }
            }

            $self->_fetch_collector_params($token, $params);
                
            $self->_write_agent_params($repos, $token,
                                       'collector', $instance, $params);
        }

        if( $dsType ne 'rrd-multigraph' )
        {
            # monitor
            my $mlist = $self->getNodeParam($token, 'monitor');
            if( defined $mlist )
            {
                my $params = {'monitor' => $mlist};
                
                foreach my $param ('monitor-period',
                                   'monitor-timeoffset')
                {
                    $params->{$param} = $self->getNodeParam($token, $param);
                }

                $self->_write_agent_params($repos, $token,
                                           'monitor', 0, $params);
            }
        }
    }
    else
    {
        foreach my $ctoken ( $self->getChildren($token) )
        {
            $self->_walk_nodes_for_agent_configs($repos, $ctoken);
        }
    }
}


sub _fetch_collector_params
{
    my $self = shift;
    my $token = shift;
    my $params = shift;

    my $type = $params->{'collector-type'};

    if( not defined( $Torrus::Collector::params{$type} ) )
    {
        die("\%Torrus::Collector::params does not have member $type");
    }

    my @maps = ( $Torrus::Collector::params{$type} );

    while( scalar( @maps ) > 0 )
    {
        my @next_maps = ();
        foreach my $map ( @maps )
        {
            foreach my $param ( keys %{$map} )
            {
                my $value = $config_tree->getNodeParam( $token, $param );

                if( ref( $map->{$param} ) )
                {
                    if( defined $value )
                    {
                        if( exists $map->{$param}->{$value} )
                        {
                            if( defined $map->{$param}->{$value} )
                            {
                                push( @next_maps,
                                      $map->{$param}->{$value} );
                            }
                        }
                        else
                        {
                            Error("Parameter $param has unknown value: " .
                                  $value . " in " . $self->path($token));
                        }
                    }
                }
                else
                {
                    if( not defined $value )
                    {
                        # We know the default value
                        $value = $map->{$param};
                    }
                }
                # Finally store the value
                if( defined $value )
                {
                    $params->{$param} = $value;
                }
            }
        }
        @maps = @next_maps;
    }
    
    return;
}




1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
